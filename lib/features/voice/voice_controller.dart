import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/conversation_store.dart';
import '../../data/models.dart';
import '../../services/ai/ai_service.dart';
import '../../services/voice/audio_io.dart';

enum VoiceState { idle, connecting, listening, speaking, error }

class TranscriptLine {
  TranscriptLine(this.fromUser, this.text);
  final bool fromUser;
  String text;
  bool finished = false;
}

/// Runs a live voice session: mic -> Gemini Live -> speaker, plus transcripts.
class VoiceController extends ChangeNotifier {
  VoiceController({
    required this.ai,
    required this.mic,
    required this.output,
    required this.store,
    required this.systemPrompt,
    required this.voice,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AiService ai;
  final MicInput mic;
  final AudioOutput output;
  final ConversationStore store;
  final String Function() systemPrompt;
  final String Function() voice;
  final DateTime Function() _clock;

  VoiceState state = VoiceState.idle;
  String? error;

  /// Voice loudness 0..1 for the orb. Separate notifier so the orb can
  /// redraw ~10x a second without rebuilding the whole screen.
  final level = ValueNotifier<double>(0);
  final List<TranscriptLine> lines = [];

  LiveConnection? _conn;
  StreamSubscription<LiveEvent>? _events;
  StreamSubscription<Uint8List>? _micSub;
  StreamSubscription<double>? _levelSub;
  Timer? _doneSpeaking;
  DateTime _speakingUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _reconnected = false;
  int _session = 0;
  bool _disposed = false;

  bool get isActive => state == VoiceState.connecting || state == VoiceState.listening || state == VoiceState.speaking;

  Future<void> toggle() => isActive ? stop() : start();

  Future<void> start() async {
    if (isActive) return;
    lines.clear();
    _reconnected = false;
    error = null;
    _set(VoiceState.connecting);
    final session = ++_session;
    try {
      if (!await mic.hasPermission()) {
        _fail('Viora needs microphone access for voice mode. Allow it in your settings and try again.');
        return;
      }
      if (!await _connect(session)) return;
      final audio = await mic.start();
      if (session != _session) {
        // Ended while the mic was starting; release it unless a newer session owns it.
        if (!isActive) await mic.stop();
        return;
      }
      _micSub = audio.listen((pcm) => _conn?.sendAudio(pcm).catchError((Object _) {}));
      _levelSub = mic.levels.listen((l) {
        if (state == VoiceState.listening) _setLevel(l);
      });
      _set(VoiceState.listening);
    } catch (e) {
      if (session != _session) return;
      await _closeAll();
      _fail(friendlyError(e));
    }
  }

  Future<bool> _connect(int session) async {
    final conn = await ai.connectLive(systemPrompt: systemPrompt(), voice: voice());
    if (conn.playsAudio && session == _session) {
      try {
        await output.init();
      } catch (_) {
        await conn.close();
        rethrow;
      }
    }
    if (session != _session) {
      await conn.close();
      return false;
    }
    _conn = conn;
    _events = conn.events.listen(_onEvent);
    return true;
  }

  Future<void> stop() async {
    if (state == VoiceState.idle) return;
    _session++;
    await _closeAll();
    await _saveTranscript();
    _setLevel(0);
    _set(VoiceState.idle);
  }

  void _onEvent(LiveEvent event) {
    switch (event) {
      case LiveAudio(:final pcm):
        output.add(pcm);
        final now = _clock();
        _speakingUntil = (_speakingUntil.isAfter(now) ? _speakingUntil : now).add(pcmDuration(pcm));
        _setLevel(pcmLevel(pcm));
        _set(VoiceState.speaking);
      case LiveTranscript(:final fromUser, :final text, :final finished):
        _append(fromUser, text, finished);
        if (!fromUser && text.isNotEmpty && state == VoiceState.listening) {
          _setLevel(0.55);
          _set(VoiceState.speaking);
        }
      case LiveInterrupted():
        unawaited(output.interrupt());
        _speakingUntil = _clock();
        _finishOpenLines();
        _backToListening();
      case LiveTurnComplete():
        _finishOpenLines();
        _doneSpeaking?.cancel();
        final wait = _speakingUntil.difference(_clock());
        _doneSpeaking = Timer(wait.isNegative ? Duration.zero : wait, _backToListening);
      case LiveEnded(:final error):
        unawaited(_onEnded(error));
    }
  }

  Future<void> _onEnded(Object? cause) async {
    if (!isActive) return;
    // The server closes sessions now and then (time limits, network). Retry once.
    if (cause == null && !_reconnected) {
      _reconnected = true;
      final session = _session;
      unawaited(_events?.cancel());
      _events = null;
      final old = _conn;
      _conn = null;
      try {
        await old?.close();
      } catch (_) {}
      if (session != _session) return; // the user pressed End meanwhile
      _set(VoiceState.connecting);
      try {
        if (await _connect(session) && session == _session) _set(VoiceState.listening);
      } catch (e) {
        if (session == _session) await _endWithError(friendlyError(e));
      }
      return;
    }
    await _endWithError(cause == null ? 'The voice session ended.' : friendlyError(cause));
  }

  /// Session died mid-conversation: keep what was said, then show the error.
  Future<void> _endWithError(String message) async {
    _session++;
    await _closeAll();
    await _saveTranscript();
    _fail(message);
  }

  void _backToListening() {
    if (state == VoiceState.speaking) {
      _setLevel(0);
      _set(VoiceState.listening);
    }
  }

  void _append(bool fromUser, String text, bool finished) {
    final last = lines.lastOrNull;
    if (last != null && last.fromUser == fromUser && !last.finished) {
      last.text += text;
      last.finished = finished;
    } else if (text.trim().isNotEmpty) {
      lines.add(TranscriptLine(fromUser, text)..finished = finished);
    }
    _notify();
  }

  void _finishOpenLines() {
    for (final l in lines) {
      l.finished = true;
    }
  }

  /// Saves the transcript to history once, then clears it.
  Future<void> _saveTranscript() async {
    final messages = [
      for (final l in lines)
        if (l.text.trim().isNotEmpty)
          ChatMessage(sender: l.fromUser ? Sender.user : Sender.assistant, text: l.text.trim()),
    ];
    lines.clear();
    if (messages.isEmpty) return;
    await store.save(Conversation(mode: ConversationMode.voice, messages: messages));
  }

  Future<void> _closeAll() async {
    _doneSpeaking?.cancel();
    // Not awaited: cancelling never needs to finish before we move on.
    for (final sub in [_micSub, _levelSub, _events]) {
      unawaited(sub?.cancel());
    }
    _micSub = _levelSub = _events = null;
    final conn = _conn;
    _conn = null;
    try {
      await mic.stop();
      await output.interrupt();
      await conn?.close();
    } catch (e) {
      debugPrint('Voice cleanup: $e');
    }
  }

  void _fail(String message) {
    error = message;
    _setLevel(0);
    _set(VoiceState.error);
  }

  void _setLevel(double l) {
    if (!_disposed) level.value = l;
  }

  void _set(VoiceState s) {
    state = s;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    unawaited(_closeAll());
    level.dispose();
    super.dispose();
  }
}

/// Short, human error text for anything thrown by the AI or audio layers.
String friendlyError(Object e) {
  final s = '$e';
  if (s.contains('SocketException') || s.contains('Failed host lookup') || s.contains('ClientException')) {
    return "I can't reach the internet right now. Check your connection and try again.";
  }
  if (s.contains('PERMISSION_DENIED') || s.contains('API key') || s.contains('App Check')) {
    return 'Gemini rejected the request. Check that Firebase AI Logic is enabled for this project.';
  }
  if (s.contains('quota') || s.contains('RESOURCE_EXHAUSTED') || s.contains('429')) {
    return "I've hit the usage limit for now. Please try again in a minute.";
  }
  if (s.contains('blocked')) return "I can't help with that one.";
  return 'Something went wrong. Please try again.';
}
