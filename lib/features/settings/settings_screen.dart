import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_services.dart';
import '../../core/config.dart';
import '../../data/conversation_store.dart';
import '../../widgets/common.dart';
import '../chat/chat_controller.dart';
import 'settings_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _clearHistory(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all history?'),
        content: const Text('This deletes every saved chat and voice conversation on this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await context.read<ConversationStore>().clear();
    if (!context.mounted) return;
    context.read<ChatController>().newChat();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('History cleared')));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final services = context.read<AppServices>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AuroraBackground(
        child: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              const _Section('Appearance'),
              _Card(children: [
                _Row(
                  title: 'Theme',
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                      ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                    ],
                    selected: {s.themeMode},
                    onSelectionChanged: (v) => s.setThemeMode(v.first),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Reduce motion'),
                  subtitle: const Text('Calmer orb and fewer animations'),
                  value: s.reduceMotion,
                  onChanged: s.setReduceMotion,
                ),
              ]),
              const _Section('Voice & language'),
              _Card(children: [
                _Row(
                  title: 'Reply language',
                  child: SegmentedButton<ReplyLanguage>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: ReplyLanguage.auto, label: Text('Auto')),
                      ButtonSegment(value: ReplyLanguage.english, label: Text('English')),
                      ButtonSegment(value: ReplyLanguage.hindi, label: Text('हिंदी')),
                    ],
                    selected: {s.language},
                    onSelectionChanged: (v) => s.setLanguage(v.first),
                  ),
                ),
                ListTile(
                  title: const Text('Voice'),
                  subtitle: const Text('Used in live voice mode'),
                  trailing: DropdownButton<String>(
                    value: s.voice,
                    underline: const SizedBox.shrink(),
                    borderRadius: BorderRadius.circular(14),
                    items: [
                      for (final v in SettingsController.voices) DropdownMenuItem(value: v, child: Text(v)),
                    ],
                    onChanged: (v) => v == null ? null : s.setVoice(v),
                  ),
                ),
              ]),
              const _Section('Notifications'),
              _Card(children: [
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Allow reminder notifications'),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final ok = await services.reminders.scheduler.requestPermission();
                    messenger.showSnackBar(SnackBar(
                      content: Text(ok ? 'Notifications are on.' : 'Enable notifications in system settings.'),
                    ));
                  },
                ),
              ]),
              const _Section('Data'),
              _Card(children: [
                ListTile(
                  leading: Icon(Icons.delete_sweep_outlined, color: theme.colorScheme.error),
                  title: const Text('Clear conversation history'),
                  onTap: () => _clearHistory(context),
                ),
              ]),
              const _Section('About'),
              _Card(children: [
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: Text(services.isDemo ? 'Demo mode' : 'Gemini via Firebase AI Logic'),
                  subtitle: Text(services.isDemo
                      ? 'Answers are scripted. Add a Firebase config to use real Gemini (see README).'
                      : 'Chat: ${AppConfig.chatModel}\nLive: ${AppConfig.liveModel}'),
                ),
                const ListTile(
                  leading: Icon(Icons.info_outline_rounded),
                  title: Text('Viora 2.0'),
                  subtitle: Text('Built with Flutter · Open-Meteo weather data'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(title,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: child),
          ],
        ),
      );
}
