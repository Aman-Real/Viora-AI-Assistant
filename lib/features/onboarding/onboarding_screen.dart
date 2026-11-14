import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/common.dart';
import '../../widgets/viora_orb.dart';
import '../settings/settings_controller.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;

  static const _features = [
    (Icons.graphic_eq_rounded, 'Real-time voice', 'Talk naturally and interrupt anytime, powered by Gemini Live.'),
    (Icons.photo_camera_outlined, 'Chat & photos', 'Ask anything or snap a photo and ask about it.'),
    (Icons.alarm_rounded, 'Gets things done', 'Reminders, weather, quick calls, messages and searches.'),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_index == 2) {
      context.read<SettingsController>().completeOnboarding();
      return;
    }
    unawaited(_pages.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = context.select<SettingsController, bool>((s) => s.reduceMotion);

    final pages = [
      _Page(
        visual: VioraOrb(size: 240, reduceMotion: reduceMotion),
        title: 'Meet Viora',
        body: 'Your real-time AI voice assistant. Speak, type or show it a photo.',
      ),
      _Page(
        visual: Column(
          children: [
            for (final (icon, title, text) in _features)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: ListTile(
                    leading: Icon(icon, color: theme.colorScheme.secondary),
                    title: Text(title),
                    subtitle: Text(text),
                  ),
                ),
              ),
          ],
        ),
        title: 'What it can do',
        body: 'One assistant for questions, photos and everyday tasks.',
      ),
      _Page(
        visual: Column(
          children: [
            _Permission(icon: Icons.mic_none_rounded, title: 'Microphone', text: 'Only while voice mode is on.'),
            _Permission(icon: Icons.notifications_none_rounded, title: 'Notifications', text: 'So reminders can reach you.'),
            _Permission(icon: Icons.photo_camera_outlined, title: 'Camera & photos', text: 'Only when you attach one.'),
          ],
        ),
        title: 'You stay in control',
        body: 'Viora asks for permissions when a feature needs them. Calls and messages always need your OK.',
      ),
    ];

    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: ContentWidth(
            maxWidth: 520,
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.read<SettingsController>().completeOnboarding(),
                    child: const Text('Skip'),
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pages,
                    onPageChanged: (i) => setState(() => _index = i),
                    children: pages,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < pages.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _index ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: i == _index ? theme.colorScheme.primary : theme.colorScheme.outline,
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _next,
                      child: Text(_index == 2 ? 'Get started' : 'Next'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.visual, required this.title, required this.body});
  final Widget visual;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          visual,
          const SizedBox(height: 28),
          Text(title, style: theme.textTheme.displaySmall, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Permission extends StatelessWidget {
  const _Permission({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          child: ListTile(
            leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
            title: Text(title),
            subtitle: Text(text),
          ),
        ),
      );
}
