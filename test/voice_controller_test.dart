import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:viora/data/conversation_store.dart';
import 'package:viora/data/key_value_store.dart';
import 'package:viora/data/models.dart';
import 'package:viora/features/voice/voice_controller.dart';
import 'package:viora/services/ai/ai_service.dart';

import 'helpers/fakes.dart';

void main() {
  late FakeAi ai;
  late FakeMic mic;
  late FakeAudioOut out;
  late ConversationStore store;
  late VoiceController voice;
  late List<VoiceState> states;

  setUp(() {
    ai = FakeAi();
    mic = FakeMic();
    out = FakeAudioOut();
    store = ConversationStore(MemoryStore());
    voice = VoiceController(
      ai: ai,
      mic: mic,
      output: out,
      store: store,
      systemPrompt: () => 'prompt',
      voice: () => 'Kore',
    );
    states = [];
    voice.addListener(() {
      if (states.isEmpty || states.last != voice.state) states.add(voice.state);
    });
  });

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));

  test('start goes connecting -> listening and streams mic audio to Gemini', () async {
    await voice.start();
    expect(states, [VoiceState.connecting, VoiceState.listening]);
    expect(mic.recording, isTrue);
    mic.speak(Uint8List.fromList([1, 2, 3, 4]));
    await settle();
    expect(ai.live!.audioSent, hasLength(1));
  });

  test('model audio switches to speaking, turn complete returns to listening', () async {
    await voice.start();
    ai.live!.emit(LiveAudio(Uint8List(48)));
    await settle();
    expect(voice.state, VoiceState.speaking);
    expect(out.played, hasLength(1));
    ai.live!.emit(const LiveTurnComplete());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(voice.state, VoiceState.listening);
  });

  test('interruption stops playback and listens again', () async {
    await voice.start();
    ai.live!.emit(LiveAudio(Uint8List(48000)));
    await settle();
    ai.live!.emit(const LiveInterrupted());
    await settle();
    expect(out.interrupts, greaterThanOrEqualTo(1));
    expect(voice.state, VoiceState.listening);
  });

  test('denied microphone shows an error and never connects', () async {
    mic.permitted = false;
    await voice.start();
    expect(voice.state, VoiceState.error);
    expect(voice.error, contains('microphone'));
    expect(ai.connects, 0);
  });

  test('connection failure shows a friendly error and releases the mic', () async {
    ai.connectError = Exception('SocketException: Failed host lookup');
    await voice.start();
    expect(voice.state, VoiceState.error);
    expect(voice.error, contains('internet'));
    expect(mic.recording, isFalse);
  });

  test('stop saves the transcript as a voice conversation', () async {
    await voice.start();
    ai.live!
      ..emit(const LiveTranscript(fromUser: true, text: 'What time '))
      ..emit(const LiveTranscript(fromUser: true, text: 'is it?', finished: true))
      ..emit(const LiveTranscript(fromUser: false, text: 'It is noon.', finished: true));
    await settle();
    expect(voice.lines.map((l) => l.text), ['What time is it?', 'It is noon.']);
    final live = ai.live!;
    await voice.stop();
    expect(voice.state, VoiceState.idle);
    expect(live.closed, isTrue);
    expect(mic.recording, isFalse);
    final saved = store.conversations.single;
    expect(saved.mode, ConversationMode.voice);
    expect(saved.messages.map((m) => m.sender), [Sender.user, Sender.assistant]);
  });

  test('server closing the session triggers one reconnect, then an error', () async {
    await voice.start();
    ai.live!.emit(const LiveEnded());
    await settle();
    expect(ai.connects, 2);
    expect(voice.state, VoiceState.listening);
    ai.live!.emit(const LiveEnded());
    await settle();
    expect(voice.state, VoiceState.error);
  });

  test('stopping while connecting does not leave a session open', () async {
    final starting = voice.start();
    await voice.stop();
    await starting;
    await settle();
    expect(voice.state, VoiceState.idle);
    expect(ai.live?.closed ?? true, isTrue);
    expect(mic.recording, isFalse);
  });
}
