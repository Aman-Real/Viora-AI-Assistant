import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';

import 'core/config.dart';
import 'data/conversation_store.dart';
import 'data/key_value_store.dart';
import 'services/ai/ai_service.dart';
import 'services/ai/demo_ai_service.dart';
import 'services/ai/gemini_ai_service.dart';
import 'services/platform/device_actions.dart';
import 'services/reminders/reminder_scheduler.dart';
import 'services/reminders/reminder_service.dart';
import 'services/tools/tool_box.dart';
import 'services/voice/audio_io.dart';

/// Everything the UI depends on. Tests build this with fakes.
class AppServices {
  AppServices({
    required this.kv,
    required this.ai,
    required this.tools,
    required this.reminders,
    required this.conversations,
    required this.mic,
    required this.audioOut,
    required this.photos,
    required this.navigatorKey,
    required this.messengerKey,
  });

  final KeyValueStore kv;
  final AiService ai;
  final ToolBox tools;
  final ReminderService reminders;
  final ConversationStore conversations;
  final MicInput mic;
  final AudioOutput audioOut;
  final PhotoPicker photos;
  final GlobalKey<NavigatorState> navigatorKey;
  final GlobalKey<ScaffoldMessengerState> messengerKey;

  bool get isDemo => ai.isDemo;

  static Future<void> _activateAppCheck() {
    final token = AppConfig.appCheckDebugToken.isEmpty ? null : AppConfig.appCheckDebugToken;
    final debug = kDebugMode || token != null;
    return FirebaseAppCheck.instance.activate(
      providerAndroid: debug ? AndroidDebugProvider(debugToken: token) : const AndroidPlayIntegrityProvider(),
      providerWeb: debug || AppConfig.recaptchaSiteKey.isEmpty
          ? WebDebugProvider(debugToken: token)
          : ReCaptchaEnterpriseProvider(AppConfig.recaptchaSiteKey),
    );
  }

  static Future<AppServices> create() async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    final kv = PrefsStore();

    var demo = AppConfig.demoRequested;
    if (!demo) {
      try {
        await Firebase.initializeApp(options: AppConfig.firebaseOptions);
        await _activateAppCheck();
      } catch (e) {
        debugPrint('Firebase init failed, falling back to demo mode: $e');
        demo = true;
      }
    }

    final ReminderScheduler scheduler;
    if (kIsWeb) {
      scheduler = InAppReminderScheduler()
        ..onDue = (r) => messengerKey.currentState?.showSnackBar(
              SnackBar(content: Text('Reminder: ${r.message}'), duration: const Duration(seconds: 8)),
            );
    } else {
      scheduler = NotificationReminderScheduler();
    }
    try {
      await scheduler.init();
    } catch (e) {
      debugPrint('Reminder scheduler unavailable: $e');
    }

    final reminders = ReminderService(kv, scheduler);
    final conversations = ConversationStore(kv);
    await Future.wait([reminders.load(), conversations.load()]);

    final tools = ToolBox(reminders: reminders, links: UrlLinkOpener(), confirmer: DialogConfirmer(navigatorKey));
    return AppServices(
      kv: kv,
      ai: demo ? DemoAiService(tools) : GeminiAiService(tools),
      tools: tools,
      reminders: reminders,
      conversations: conversations,
      mic: RecordMicInput(),
      audioOut: SoloudAudioOutput(),
      photos: DevicePhotoPicker(),
      navigatorKey: navigatorKey,
      messengerKey: messengerKey,
    );
  }
}
