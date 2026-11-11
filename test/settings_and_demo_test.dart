import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:viora/data/key_value_store.dart';
import 'package:viora/data/models.dart';
import 'package:viora/features/settings/settings_controller.dart';
import 'package:viora/services/ai/ai_service.dart';
import 'package:viora/services/ai/demo_ai_service.dart';
import 'package:viora/services/reminders/reminder_service.dart';
import 'package:viora/services/tools/tool_box.dart';

import 'helpers/fakes.dart';

void main() {
  group('settings', () {
    test('choices persist across restarts', () async {
      final kv = MemoryStore();
      SettingsController(kv)
        ..setThemeMode(ThemeMode.light)
        ..setLanguage(ReplyLanguage.hindi)
        ..setVoice('Puck')
        ..setReduceMotion(true)
        ..completeOnboarding();
      await Future<void>.delayed(Duration.zero);

      final reloaded = SettingsController(kv);
      await reloaded.load();
      expect(reloaded.themeMode, ThemeMode.light);
      expect(reloaded.language, ReplyLanguage.hindi);
      expect(reloaded.voice, 'Puck');
      expect(reloaded.reduceMotion, isTrue);
      expect(reloaded.onboarded, isTrue);
    });

    test('defaults: dark theme, auto language, motion on, not onboarded', () async {
      final s = SettingsController(MemoryStore({SettingsController.storageKey: 'garbage'}));
      await s.load();
      expect(s.themeMode, ThemeMode.dark);
      expect(s.language, ReplyLanguage.auto);
      expect(s.reduceMotion, isFalse);
      expect(s.onboarded, isFalse);
    });

    test('system prompt follows language, mode, time and recent context', () {
      final s = SettingsController(MemoryStore(), clock: () => DateTime(2026, 11, 11, 18, 5))
        ..setLanguage(ReplyLanguage.hindi);
      final voice = s.systemPrompt(
        voiceMode: true,
        recent: [ChatMessage(sender: Sender.user, text: 'My name is Aman')],
      );
      expect(voice, contains('Hindi (Devanagari'));
      expect(voice, contains('speaking out loud'));
      expect(voice, contains('Wednesday 11 November 2026, 6:05 PM'));
      expect(voice, contains('User: My name is Aman'));
      s.setLanguage(ReplyLanguage.english);
      expect(s.systemPrompt(), allOf(contains('Always reply in English'), contains('markdown')));
    });
  });

  group('demo AI', () {
    final now = DateTime(2026, 11, 11, 10);
    late FakeScheduler scheduler;
    late DemoAiService demo;

    setUp(() {
      scheduler = FakeScheduler();
      final tools = ToolBox(
        reminders: ReminderService(MemoryStore(), scheduler, clock: () => now),
        links: FakeLinks(),
        confirmer: FakeConfirmer(),
        httpClient: MockClient((_) async => http.Response('offline', 500)),
        clock: () => now,
      );
      demo = DemoAiService(tools, tick: Duration.zero);
    });

    Future<String> ask(String text) =>
        demo.startChat(history: const [], systemPrompt: '').send(text).join();

    test('understands reminder phrasings and really schedules them', () async {
      expect(await ask('Remind me to drink water in 10 minutes'), contains('drink water'));
      expect(await ask('remind me in 2 hours to call mom'), contains('call mom'));
      expect(scheduler.scheduled.map((r) => r.when),
          [now.add(const Duration(minutes: 10)), now.add(const Duration(hours: 2))]);
    });

    test('handles weather outages, dates and photos gracefully', () async {
      expect(await ask("What's the weather in Delhi?"), contains("couldn't get the weather"));
      expect(await ask("What's the date today?"), contains('Wednesday'));
      final photo = await demo
          .startChat(history: const [], systemPrompt: '')
          .send('what is this', image: Uint8List.fromList(tinyPng))
          .join();
      expect(photo, contains('demo mode'));
    });

    test('demo voice session plays a scripted exchange', () async {
      final live = await demo.connectLive(systemPrompt: '', voice: 'Kore');
      final events = <LiveEvent>[];
      final sub = live.events.listen(events.add);
      await Future<void>.delayed(const Duration(seconds: 3));
      await sub.cancel();
      await live.close();
      expect(events.whereType<LiveTranscript>().where((e) => e.fromUser), isNotEmpty);
      expect(events.whereType<LiveTurnComplete>(), hasLength(1));
      expect(live.playsAudio, isFalse);
    });
  });
}
