import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../services/reminders/reminder_service.dart';
import '../../widgets/common.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_screen.dart';

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  static const example = 'Remind me to stretch in 20 minutes';

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ReminderService>();
    final upcoming = service.upcoming;
    final past = service.past;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders'),
        actions: [
          IconButton(
            tooltip: 'Allow notifications',
            icon: const Icon(Icons.notifications_active_outlined),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final ok = await service.scheduler.requestPermission();
              messenger.showSnackBar(SnackBar(
                content: Text(ok ? 'Notifications are on.' : 'Notifications are off. Enable them in system settings.'),
              ));
            },
          ),
        ],
      ),
      body: AuroraBackground(
        child: ContentWidth(
          child: upcoming.isEmpty && past.isEmpty
              ? EmptyState(
                  icon: Icons.alarm_add_rounded,
                  title: 'No reminders yet',
                  message: 'Just ask: "$example".',
                  action: FilledButton.icon(
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: const Text('Try it'),
                    onPressed: () {
                      context.read<ChatController>().newChat();
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(builder: (_) => const ChatScreen(initialPrompt: example)),
                      );
                    },
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    if (upcoming.isNotEmpty) const _Header('Upcoming'),
                    for (final r in upcoming) _ReminderTile(r, onDelete: () => service.remove(r.id)),
                    if (past.isNotEmpty) const _Header('Done'),
                    for (final r in past) _ReminderTile(r, past: true, onDelete: () => service.remove(r.id)),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile(this.reminder, {required this.onDelete, this.past = false});
  final Reminder reminder;
  final VoidCallback onDelete;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: past ? 0.55 : 1,
        child: Card(
          child: ListTile(
            leading: Icon(past ? Icons.check_circle_outline : Icons.alarm_rounded, color: scheme.secondary),
            title: Text(reminder.message),
            subtitle: Text(DateFormat('EEE d MMM · h:mm a').format(reminder.when)),
            trailing: IconButton(
              tooltip: 'Delete reminder',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: onDelete,
            ),
          ),
        ),
      ),
    );
  }
}
