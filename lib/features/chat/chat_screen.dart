import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_services.dart';
import '../../services/platform/device_actions.dart';
import '../../widgets/common.dart';
import '../home/home_screen.dart' show homeSuggestions;
import 'chat_controller.dart';
import 'message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.initialPrompt, this.pickPhotoOnOpen = false});

  final String? initialPrompt;
  final bool pickPhotoOnOpen;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  PickedPhoto? _photo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.initialPrompt != null) {
        unawaited(_send(widget.initialPrompt!));
      } else if (widget.pickPhotoOnOpen) {
        unawaited(_choosePhoto());
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final chat = context.read<ChatController>();
    final text = preset ?? _text.text;
    final photo = _photo;
    if (chat.sending || (text.trim().isEmpty && photo == null)) return;
    _text.clear();
    setState(() => _photo = null);
    _scrollSoon();
    await chat.send(text, image: photo?.bytes, imageMime: photo?.mimeType ?? 'image/jpeg');
    _scrollSoon();
  }

  void _scrollSoon({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (jump) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(end, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _choosePhoto() async {
    final picker = context.read<AppServices>().photos;
    final fromCamera = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (fromCamera == null) return;
    try {
      final photo = await picker.pick(fromCamera: fromCamera);
      if (photo != null && mounted) {
        setState(() => _photo = photo);
        _focus.requestFocus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open the camera or gallery. Check app permissions.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final messages = chat.messages;
    final theme = Theme.of(context);
    final demo = context.read<AppServices>().isDemo;
    if (chat.sending) _scrollSoon(jump: true);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          messages.isEmpty ? 'New chat' : chat.conversation.displayTitle,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (demo) const Padding(padding: EdgeInsets.only(right: 4), child: Center(child: DemoBadge())),
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: chat.newChat,
          ),
        ],
      ),
      body: AuroraBackground(
        child: SafeArea(
          top: false,
          child: ContentWidth(
            maxWidth: 760,
            child: Column(
              children: [
                Expanded(
                  child: messages.isEmpty
                      ? _EmptyChat(onPick: _send)
                      : SelectionArea(
                          child: ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            itemCount: messages.length,
                            itemBuilder: (context, i) => MessageBubble(
                              key: ValueKey(messages[i].id),
                              message: messages[i],
                              onRetry: i == messages.length - 1 ? chat.retry : null,
                            ),
                          ),
                        ),
                ),
                if (_photo != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.memory(_photo!.bytes, height: 72, width: 72, fit: BoxFit.cover),
                          ),
                          Positioned(
                            right: -10,
                            top: -10,
                            child: IconButton.filledTonal(
                              tooltip: 'Remove photo',
                              iconSize: 16,
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(() => _photo = null),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Add photo',
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        onPressed: chat.sending ? null : _choosePhoto,
                      ),
                      Expanded(
                        child: TextField(
                          key: const Key('chat-input'),
                          controller: _text,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: _photo == null ? 'Message Viora' : 'Ask about this photo',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ListenableBuilder(
                        listenable: _text,
                        builder: (context, _) {
                          final canSend = !chat.sending && (_text.text.trim().isNotEmpty || _photo != null);
                          return IconButton.filled(
                            tooltip: 'Send',
                            style: IconButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              minimumSize: const Size(48, 48),
                            ),
                            icon: chat.sending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.arrow_upward_rounded),
                            onPressed: canSend ? _send : null,
                          );
                        },
                      ),
                    ],
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

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.onPick});
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Column(
        children: [
          Image.asset('assets/brand/logo_mark.png', width: 72, height: 72, excludeFromSemantics: true),
          const SizedBox(height: 16),
          Text('Ask me anything', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Chat, attach a photo, or ask me to set a reminder.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (icon, text) in homeSuggestions) PromptChip(icon: icon, label: text, onTap: () => onPick(text)),
            ],
          ),
        ],
      ),
    );
  }
}
