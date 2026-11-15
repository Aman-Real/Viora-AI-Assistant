import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_services.dart';
import 'core/theme.dart';
import 'features/chat/chat_controller.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/settings/settings_controller.dart';
import 'features/voice/voice_controller.dart';

class VioraApp extends StatelessWidget {
  const VioraApp({super.key, required this.services, required this.settings});

  final AppServices services;
  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    String recentPrompt() {
      final latest = services.conversations.conversations.firstOrNull?.messages ?? const [];
      final recent = latest.length > 6 ? latest.sublist(latest.length - 6) : latest;
      return settings.systemPrompt(voiceMode: true, recent: recent);
    }

    return MultiProvider(
      providers: [
        Provider.value(value: services),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: services.conversations),
        ChangeNotifierProvider.value(value: services.reminders),
        ChangeNotifierProvider(
          create: (_) => ChatController(
            ai: services.ai,
            store: services.conversations,
            tools: services.tools,
            systemPrompt: settings.systemPrompt,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => VoiceController(
            ai: services.ai,
            mic: services.mic,
            output: services.audioOut,
            store: services.conversations,
            systemPrompt: recentPrompt,
            voice: () => settings.voice,
          ),
        ),
      ],
      child: Consumer<SettingsController>(
        builder: (context, s, _) => MaterialApp(
          title: 'Viora',
          debugShowCheckedModeBanner: false,
          navigatorKey: services.navigatorKey,
          scaffoldMessengerKey: services.messengerKey,
          themeMode: s.themeMode,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeAnimationDuration: s.reduceMotion ? Duration.zero : const Duration(milliseconds: 250),
          home: s.onboarded ? const HomeScreen() : const OnboardingScreen(),
        ),
      ),
    );
  }
}
