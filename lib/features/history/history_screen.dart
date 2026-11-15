import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/conversation_store.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  static String sectionFor(DateTime t, DateTime now) {
    final day = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return 'This week';
    return 'Earlier';
  }

  Future<void> _delete(BuildContext context, Conversation c) async {
    final store = context.read<ConversationStore>();
    final messenger = ScaffoldMessenger.of(context);
    await store.delete(c.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Conversation deleted'),
        action: SnackBarAction(label: 'Undo', onPressed: () => store.save(c)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final items = context.watch<ConversationStore>().conversations;
    final now = DateTime.now();
    final theme = Theme.of(context);
    String? lastSection;

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: AuroraBackground(
        child: ContentWidth(
          child: items.isEmpty
              ? const EmptyState(
                  icon: Icons.forum_outlined,
                  title: 'No conversations yet',
                  message: 'Your chats and voice sessions will show up here so you can pick them up later.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    for (final c in items) ...[
                      if (sectionFor(c.updatedAt, now) != lastSection)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                          child: Text(
                            lastSection = sectionFor(c.updatedAt, now),
                            style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                            leading: CircleAvatar(
                              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                              child: Icon(
                                c.mode == ConversationMode.voice ? Icons.graphic_eq_rounded : Icons.chat_bubble_outline,
                                color: theme.colorScheme.primary,
                                size: 20,
                              ),
                            ),
                            title: Text(c.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              '${DateFormat.jm().format(c.updatedAt)} · ${c.preview}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              tooltip: 'Delete conversation',
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () => _delete(context, c),
                            ),
                            onTap: () {
                              context.read<ChatController>().open(c);
                              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ChatScreen()));
                            },
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
