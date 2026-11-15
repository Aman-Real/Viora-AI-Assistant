import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_services.dart';
import '../../widgets/common.dart';
import '../../widgets/viora_orb.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_screen.dart';
import '../history/history_screen.dart';
import '../reminders/reminders_screen.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_screen.dart';
import '../voice/voice_controller.dart';

const homeSuggestions = [
  (Icons.alarm_rounded, 'Remind me to drink water in 10 minutes'),
  (Icons.wb_sunny_outlined, 'What\'s the weather in Dehradun?'),
  (Icons.event_outlined, 'What\'s the date today?'),
  (Icons.lightbulb_outline_rounded, 'Explain black holes simply'),
];

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _openChat(BuildContext context, {String? prompt, bool newChat = true, bool pickPhoto = false}) {
    final voice = context.read<VoiceController>();
    if (voice.isActive) unawaited(voice.stop());
    if (newChat) context.read<ChatController>().newChat();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatScreen(initialPrompt: prompt, pickPhotoOnOpen: pickPhoto),
    ));
  }

  void _push(BuildContext context, Widget page) {
    final voice = context.read<VoiceController>();
    if (voice.isActive) unawaited(voice.stop());
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final voice = context.watch<VoiceController>();
    final reduceMotion = context.select<SettingsController, bool>((s) => s.reduceMotion);
    final demo = context.read<AppServices>().isDemo;

    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: ContentWidth(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                  child: Row(
                    children: [
                      const BrandMark(),
                      if (demo) ...[const SizedBox(width: 10), const DemoBadge()],
                      const Spacer(),
                      IconButton(
                        tooltip: 'History',
                        icon: const Icon(Icons.history_rounded),
                        onPressed: () => _push(context, const HistoryScreen()),
                      ),
                      IconButton(
                        tooltip: 'Reminders',
                        icon: const Icon(Icons.notifications_none_rounded),
                        onPressed: () => _push(context, const RemindersScreen()),
                      ),
                      IconButton(
                        tooltip: 'Settings',
                        icon: const Icon(Icons.tune_rounded),
                        onPressed: () => _push(context, const SettingsScreen()),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final orbSize = (box.maxHeight * 0.48).clamp(180.0, 300.0);
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: box.maxHeight),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _Headline(voice: voice),
                              const SizedBox(height: 8),
                              Semantics(
                                button: true,
                                label: voice.isActive ? 'Stop voice' : 'Start voice',
                                excludeSemantics: true,
                                child: GestureDetector(
                                  key: const Key('voice-orb'),
                                  onTap: voice.toggle,
                                  child: ValueListenableBuilder<double>(
                                    valueListenable: voice.level,
                                    builder: (context, level, _) => VioraOrb(
                                      size: orbSize,
                                      level: level,
                                      mood: _mood(voice.state),
                                      reduceMotion: reduceMotion,
                                    ),
                                  ),
                                ),
                              ),
                              _StatusLine(voice: voice),
                              const SizedBox(height: 12),
                              _Transcript(voice: voice),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (!voice.isActive) ...[
                  _Suggestions(onPick: (text) => _openChat(context, prompt: text)),
                  const SizedBox(height: 12),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Material(
                    color: theme.colorScheme.surfaceContainerHigh,
                    shape: StadiumBorder(side: BorderSide(color: theme.colorScheme.outline)),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            customBorder: const StadiumBorder(),
                            onTap: () => _openChat(context),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              child: Text('Type a message…',
                                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Ask about a photo',
                          icon: const Icon(Icons.photo_camera_outlined),
                          onPressed: () => _openChat(context, pickPhoto: true),
                        ),
                        const SizedBox(width: 6),
                      ],
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

  static OrbMood _mood(VoiceState s) => switch (s) {
        VoiceState.idle => OrbMood.idle,
        VoiceState.connecting => OrbMood.connecting,
        VoiceState.listening => OrbMood.listening,
        VoiceState.speaking => OrbMood.speaking,
        VoiceState.error => OrbMood.error,
      };
}

/// One scrolling row on phones; wraps on wide screens where sideways
/// scrolling is awkward with a mouse.
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.onPick});
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    final chips = [
      for (final (icon, text) in homeSuggestions) PromptChip(icon: icon, label: text, onTap: () => onPick(text)),
    ];
    if (MediaQuery.sizeOf(context).width >= 600) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: chips),
      );
    }
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.voice});
  final VoiceController voice;

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: voice.isActive
          ? const SizedBox(height: 64)
          : Column(
              key: const ValueKey('greeting'),
              children: [
                Text(_greeting(),
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text('How can I help?', style: theme.textTheme.headlineMedium),
              ],
            ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.voice});
  final VoiceController voice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = switch (voice.state) {
      VoiceState.idle => 'Tap the orb to talk',
      VoiceState.connecting => 'Connecting…',
      VoiceState.listening => 'Listening…',
      VoiceState.speaking => 'Speaking…',
      VoiceState.error => voice.error ?? 'Something went wrong',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              text,
              key: const Key('voice-status'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: voice.state == VoiceState.error ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (voice.state == VoiceState.error)
            TextButton.icon(
              onPressed: voice.start,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          if (voice.isActive)
            TextButton.icon(
              onPressed: voice.stop,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('End'),
            ),
        ],
      ),
    );
  }
}

/// The end of [text], cut at a word, so a long answer shows what is being
/// said now instead of pushing the newest words off the screen.
String latestWords(String text, int max) {
  final t = text.trim();
  if (t.length <= max) return t;
  final tail = t.substring(t.length - max);
  final space = tail.indexOf(' ');
  return '…${space < 0 ? tail : tail.substring(space + 1)}';
}

class _Transcript extends StatelessWidget {
  const _Transcript({required this.voice});
  final VoiceController voice;

  @override
  Widget build(BuildContext context) {
    if (voice.lines.isEmpty) return const SizedBox(height: 24);
    final theme = Theme.of(context);
    final shown = voice.lines.length > 2 ? voice.lines.sublist(voice.lines.length - 2) : voice.lines;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          for (final line in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                latestWords(line.text, line.fromUser ? 100 : 160),
                textAlign: TextAlign.center,
                style: line.fromUser
                    ? theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)
                    : theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
        ],
      ),
    );
  }
}
