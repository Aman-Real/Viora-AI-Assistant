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
    required this.systemPrompt,
  });

  final AiService ai;
  final ConversationStore store;
  final String Function() systemPrompt;

  Conversation _conversation = Conversation();
  AiChat? _chat;
  bool sending = false;
  bool _disposed = false;

  Conversation get conversation => _conversation;
  List<ChatMessage> get messages => _conversation.messages;

  /// Bumped whenever the open conversation changes, so a reply that is still
  /// streaming stops writing into the screen the user has moved on from.
  int _turn = 0;

  void newChat() => _switchTo(Conversation());

  void open(Conversation c) => _switchTo(c);

  void _switchTo(Conversation c) {
    _turn++;
    sending = false;
    _conversation = c;
    _chat = null;
    _notify();
  }

  Future<void> send(String text, {Uint8List? image, String imageMime = 'image/jpeg'}) async {
    var prompt = text.trim();
    if (sending || (prompt.isEmpty && image == null)) return;
    if (prompt.isEmpty) prompt = 'What is in this photo?';

    final convo = _conversation;
    final turn = ++_turn;
    final epoch = store.epoch;
    final chat = _chat ??= ai.startChat(history: messages, systemPrompt: systemPrompt());
    final reply = ChatMessage(sender: Sender.assistant, isStreaming: true);
    convo.messages
      ..add(ChatMessage(sender: Sender.user, text: prompt, image: image))
      ..add(reply);
    sending = true;
    _notify();

    void onTool(ToolActivity a) {
      reply.toolNotes.add(a.summary);
      _notify();
    }

    try {
      await ToolBox.capture(onTool, () async {
        await for (final chunk in chat.send(prompt, image: image, imageMime: imageMime)) {
          if (turn != _turn) break; // user switched chats: stop this reply
          reply.text += chunk;
          _notify();
        }
      });
      if (reply.text.trim().isEmpty) {
        reply.text = turn == _turn ? "I couldn't come up with an answer. Could you rephrase?" : '(Reply stopped)';
      }
    } catch (e) {
      debugPrint('Chat error: $e');
      reply
        ..isError = true
        ..text = friendlyError(e);
      if (turn == _turn) _chat = null; // rebuild the session from saved history next time
    } finally {
      reply.isStreaming = false;
      if (turn == _turn) sending = false;
      convo.updatedAt = DateTime.now();
      // Don't bring back a conversation the user deleted or cleared meanwhile.
      if (store.epoch == epoch && !store.wasDeleted(convo.id)) await store.save(convo);
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
