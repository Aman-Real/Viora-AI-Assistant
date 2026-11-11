import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:viora/app.dart';
import 'package:viora/app_services.dart';
import 'package:viora/data/key_value_store.dart';
import 'package:viora/data/models.dart';
import 'package:viora/features/home/home_screen.dart';
import 'package:viora/features/settings/settings_controller.dart';
import 'package:viora/features/voice/voice_controller.dart';
import 'package:viora/widgets/viora_orb.dart';

import 'helpers/fakes.dart';

void main() {
  late AppServices services;
  late SettingsController settings;
  late FakeAi ai;

  Future<void> launch(WidgetTester tester, {bool onboarded = true}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    ai = FakeAi();
    final kv = MemoryStore();
    services = fakeServices(ai: ai, kv: kv);
    settings = SettingsController(kv);
    settings.setReduceMotion(true);
    if (onboarded) settings.completeOnboarding();
    await tester.pumpWidget(VioraApp(services: services, settings: settings));
    await tester.pumpAndSettle();
  }

  testWidgets('onboarding walks through three pages into the home screen', (tester) async {
    await launch(tester, onboarded: false);
    expect(find.text('Meet Viora'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('What it can do'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('How can I help?'), findsOneWidget);
    expect(settings.onboarded, isTrue);
  });

  testWidgets('home shows the orb, suggestions and navigation', (tester) async {
    await launch(tester);
    expect(find.byType(VioraOrb), findsOneWidget);
    expect(find.text('Tap the orb to talk'), findsOneWidget);
    expect(find.byTooltip('History'), findsOneWidget);
    expect(find.byTooltip('Reminders'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.textContaining('Remind me to drink water'), findsOneWidget);
  });

  testWidgets('tapping the orb starts and ends a voice session', (tester) async {
    await launch(tester);
    await tester.tap(find.byKey(const Key('voice-orb')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Listening…'), findsOneWidget);
    final voice = tester.element(find.byType(HomeScreen)).read<VoiceController>();
    await tester.tap(find.widgetWithText(TextButton, 'End'));
    await tester.pumpAndSettle();
    expect(voice.state, VoiceState.idle, reason: 'error was: ${voice.error}');
    expect(find.text('Tap the orb to talk'), findsOneWidget);
    expect(ai.live!.closed, isTrue);
  });

  testWidgets('chat: a suggestion sends a message and shows the streamed reply', (tester) async {
    await launch(tester);
    await tester.tap(find.textContaining('Remind me to drink water'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Remind me to drink water in 10 minutes'), findsWidgets);
    expect(find.text('Hello there!', findRichText: true), findsWidgets);

    await tester.enterText(find.byKey(const Key('chat-input')), 'And quasars?');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('And quasars?'), findsOneWidget);
    expect(ai.histories, hasLength(1));
  });

  testWidgets('chat: attaching a photo shows a preview and sends it', (tester) async {
    await launch(tester);
    await tester.tap(find.byTooltip('Ask about a photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove photo'), findsOneWidget);
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(ai.sentImages.single, isNotNull);
    expect(ai.sent.single, 'What is in this photo?');
  });

  testWidgets('history lists conversations, reopens and deletes them', (tester) async {
    await launch(tester);
    await services.conversations.save(Conversation(messages: [
      ChatMessage(sender: Sender.user, text: 'Plan my trip to Goa'),
      ChatMessage(sender: Sender.assistant, text: 'Sure! Day 1: beaches.'),
    ]));
    await tester.tap(find.byTooltip('History'));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Plan my trip to Goa'), findsOneWidget);

    await tester.tap(find.text('Plan my trip to Goa'));
    await tester.pumpAndSettle();
    expect(find.text('Sure! Day 1: beaches.', findRichText: true), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete conversation'));
    await tester.pumpAndSettle();
    expect(find.text('No conversations yet'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Plan my trip to Goa'), findsOneWidget);
  });

  testWidgets('reminders screen lists and deletes reminders', (tester) async {
    await launch(tester);
    await services.reminders.add('Call the bank', DateTime.now().add(const Duration(hours: 2)));
    await tester.tap(find.byTooltip('Reminders'));
    await tester.pumpAndSettle();
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Call the bank'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete reminder'));
    await tester.pumpAndSettle();
    expect(find.text('No reminders yet'), findsOneWidget);
  });

  testWidgets('settings switch theme, language and reduce motion', (tester) async {
    await launch(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(settings.themeMode, ThemeMode.light);
    expect(Theme.of(tester.element(find.text('Theme'))).brightness, Brightness.light);

    await tester.tap(find.text('हिंदी'));
    await tester.pumpAndSettle();
    expect(settings.language, ReplyLanguage.hindi);

    await tester.tap(find.text('Reduce motion'));
    await tester.pumpAndSettle();
    expect(settings.reduceMotion, isFalse);
  });

  testWidgets('reduce motion holds the orb still', (tester) async {
    await launch(tester);
    final orb = tester.widget<VioraOrb>(find.byType(VioraOrb));
    expect(orb.reduceMotion, isTrue);
    // With motion reduced nothing keeps animating, so the frame settles.
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
