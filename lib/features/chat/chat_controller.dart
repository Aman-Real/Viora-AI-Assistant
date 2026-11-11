import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/conversation_store.dart';
import '../../data/models.dart';
import '../../services/ai/ai_service.dart';
import '../../services/tools/tool_box.dart';
import '../voice/voice_controller.dart' show friendlyError;

/// The open text conversation: sends messages, streams replies, saves history.
class ChatController extends ChangeNotifier {
  ChatController({
    required this.ai,
    required this.store,
    required this.tools,
    required this.systemPrompt,
  });

  final AiService ai;
  final ConversationStore store;
  final ToolBox tools;
  final String Function() systemPrompt;

  Conversation _conversation = Conversation();
  AiChat? _chat;
  bool sending = false;
  bool _disposed = false;

  Conversation get conversation => _conversation;
  List<ChatMessage> get messages => _conversation.messages;

  void newChat() {
    if (sending) return;
    _conversation = Conversation();
    _chat = null;
    _notify();
  }

  void open(Conversation c) {
    if (sending) return;
    _conversation = c;
    _chat = null;
    _notify();
  }

  Future<void> send(String text, {Uint8List? image, String imageMime = 'image/jpeg'}) async {
    var prompt = text.trim();
    if (sending || (prompt.isEmpty && image == null)) return;
    if (prompt.isEmpty) prompt = 'What is in this photo?';

    final chat = _chat ??= ai.startChat(history: messages, systemPrompt: systemPrompt());
    final reply = ChatMessage(sender: Sender.assistant, isStreaming: true);
    messages
      ..add(ChatMessage(sender: Sender.user, text: prompt, image: image))
      ..add(reply);
    sending = true;
    _notify();

    final toolSub = tools.activity.listen((a) {
      reply.toolNotes.add(a.summary);
      _notify();
    });
    try {
      await for (final chunk in chat.send(prompt, image: image, imageMime: imageMime)) {
        reply.text += chunk;
        _notify();
      }
      if (reply.text.trim().isEmpty) reply.text = "I couldn't come up with an answer. Could you rephrase?";
    } catch (e) {
      debugPrint('Chat error: $e');
      reply
        ..isError = true
        ..text = friendlyError(e);
      _chat = null; // rebuild the session from saved history next time
    } finally {
      unawaited(toolSub.cancel());
      reply.isStreaming = false;
      sending = false;
      _conversation.updatedAt = DateTime.now();
      await store.save(_conversation);
      _notify();
    }
  }

  /// Sends the last user message again after an error.
  Future<void> retry() async {
    if (sending || messages.length < 2 || !messages.last.isError) return;
    messages.removeLast();
    final last = messages.removeLast();
    await send(last.text, image: last.image);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
