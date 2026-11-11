import 'dart:async';
import 'dart:typed_data';

import '../../data/models.dart';
import '../tools/tool_box.dart';
import 'ai_service.dart';

/// Offline stand-in used when Firebase isn't configured. It understands a few
/// phrasings and runs the real tools, so reminders and weather still work.
class DemoAiService implements AiService {
  DemoAiService(this.tools, {this.tick = const Duration(milliseconds: 28)});

  final ToolBox tools;
  final Duration tick;

  @override
  bool get isDemo => true;

  @override
  AiChat startChat({required List<ChatMessage> history, required String systemPrompt}) =>
      _DemoChat(this);

  @override
  Future<LiveConnection> connectLive({required String systemPrompt, required String voice}) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return _DemoLive(tick);
  }

  Future<String> reply(String text, {bool hasImage = false}) async {
    final lower = text.toLowerCase();

    if (hasImage) {
      return "**Nice photo!** In demo mode I can't actually see it — connect Firebase and "
          'Gemini will describe objects, read text and answer questions about any image.';
    }

    const units = r'(min|minutes?|hours?|hrs?)\b';
    final a = RegExp('remind me (?:to )?(.+?) in (\\d+) ?$units').firstMatch(lower);
    final b = a == null ? RegExp('remind me in (\\d+) ?$units,? (?:to )?(.+)').firstMatch(lower) : null;
    if (a != null || b != null) {
      final what = (a?[1] ?? b![3]!).replaceAll(RegExp(r'[.!?]+$'), '');
      final amount = int.parse(a?[2] ?? b![1]!);
      final minutes = (a?[3] ?? b![2]!).startsWith('h') ? amount * 60 : amount;
      final result = await tools.run('set_reminder', {'message': _cap(what), 'in_minutes': minutes});
      return result['error'] != null
          ? "I couldn't set that reminder: ${result['error']}"
          : "Done! I'll remind you to **$what** at ${result['scheduled_for']}.";
    }

    final weather = RegExp(r'weather (?:in|at|for) ([a-z .]+)').firstMatch(lower);
    if (weather != null) {
      final city = weather[1]!.trim().replaceAll(RegExp(r'[?.!]+$'), '');
      final w = await tools.run('get_weather', {'city': city});
      if (w['error'] != null) return "I couldn't get the weather right now (${w['error']}).";
      return 'It\'s **${w['temperature_c']}°C** and ${w['conditions']} in ${w['place']} '
          '(feels like ${w['feels_like_c']}°C). Today: ${w['today_low_c']}–${w['today_high_c']}°C.';
    }

    if (RegExp(r'\b(time|date|day|today)\b').hasMatch(lower)) {
      final now = await tools.run('get_current_datetime', {});
      return "It's ${now['readable']}.";
    }

    if (lower.contains('reminders')) {
      final list = (await tools.run('list_reminders', {}))['reminders'] as List;
      if (list.isEmpty) return 'You have no upcoming reminders.';
      return 'Your upcoming reminders:\n\n${list.map((r) => '- **${(r as Map)['message']}** · ${r['when']}').join('\n')}';
    }

    return "Hi! I'm **Viora** running in *demo mode*, so my answers are scripted.\n\n"
        'Things you can try right now:\n'
        '- "Remind me to drink water in 10 minutes"\n'
        '- "What\'s the weather in Dehradun?"\n'
        '- "What\'s the date today?"\n\n'
        'Connect a Firebase project to unlock real Gemini answers, photos and live voice.';
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _DemoChat implements AiChat {
  _DemoChat(this._ai);
  final DemoAiService _ai;

  @override
  Stream<String> send(String text, {Uint8List? image, String imageMime = 'image/jpeg'}) async* {
    final answer = await _ai.reply(text, hasImage: image != null);
    for (final word in RegExp(r'\S+\s*').allMatches(answer)) {
      await Future<void>.delayed(_ai.tick);
      yield word[0]!;
    }
  }
}

/// Plays a short scripted exchange so the voice UI can be explored offline.
class _DemoLive implements LiveConnection {
  _DemoLive(Duration tick) {
    const question = 'Hey Viora, what can you do?';
    const answer = 'I can chat, look at photos, check the weather and set reminders for you, '
        'all hands-free. This is demo mode; connect Firebase to talk to me for real.';
    var at = const Duration(milliseconds: 1200);
    void later(Duration d, LiveEvent e) => _timers.add(Timer(d, () => _emit(e)));
    for (final w in question.split(' ')) {
      later(at, LiveTranscript(fromUser: true, text: '$w '));
      at += tick * 6;
    }
    later(at, const LiveTranscript(fromUser: true, text: '', finished: true));
    at += const Duration(milliseconds: 700);
    for (final w in answer.split(' ')) {
      later(at, LiveTranscript(fromUser: false, text: '$w '));
      at += tick * 7;
    }
    later(at, const LiveTranscript(fromUser: false, text: '', finished: true));
    later(at + const Duration(milliseconds: 200), const LiveTurnComplete());
  }

  // Single-subscription: buffers anything that arrives before the UI listens.
  final _events = StreamController<LiveEvent>();
  final _timers = <Timer>[];

  void _emit(LiveEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  @override
  Stream<LiveEvent> get events => _events.stream;

  @override
  bool get playsAudio => false;

  @override
  Future<void> sendAudio(Uint8List pcm) async {}

  @override
  Future<void> close() async {
    for (final t in _timers) {
      t.cancel();
    }
    unawaited(_events.close());
  }
}
