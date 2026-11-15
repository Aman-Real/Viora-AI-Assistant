import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:viora/data/conversation_store.dart';
import 'package:viora/data/key_value_store.dart';
import 'package:viora/data/models.dart';
import 'package:viora/features/chat/chat_controller.dart';
import 'package:viora/services/reminders/reminder_service.dart';
import 'package:viora/services/tools/tool_box.dart';

import 'helpers/fakes.dart';

void main() {
  late FakeAi ai;
  late ConversationStore store;
  late ToolBox tools;
  late ChatController chat;

  setUp(() {
    ai = FakeAi();
    final kv = MemoryStore();
    store = ConversationStore(kv);
    tools = ToolBox(
      reminders: ReminderService(kv, FakeScheduler()),
      links: FakeLinks(),
      confirmer: FakeConfirmer(),
    );
    chat = ChatController(ai: ai, store: store, systemPrompt: () => 'sys');
  });

  test('send streams the reply and saves the conversation', () async {
    await chat.send('  Hi Viora  ');
    expect(chat.messages.map((m) => m.text), ['Hi Viora', 'Hello there!']);
    expect(chat.messages.last.isStreaming, isFalse);
    expect(chat.sending, isFalse);
    expect(store.conversations.single.displayTitle, 'Hi Viora');
  });

  test('keeps memory: one session per conversation, history passed when reopened', () async {
    await chat.send('first');
    await chat.send('second');
    expect(ai.histories, hasLength(1), reason: 'same session reused for follow-ups');

    final saved = store.conversations.single;
    chat.newChat();
    chat.open(saved);
    await chat.send('third');
    expect(ai.histories, hasLength(2));
    expect(ai.histories.last.map((m) => m.text), ['first', 'Hello there!', 'second', 'Hello there!']);
  });

  test('tool activity during a reply is shown on that reply', () async {
    ai.onSend = (_) => tools.run('set_reminder', {'message': 'Stretch', 'in_minutes': 5});
    await chat.send('remind me to stretch in 5 minutes');
    expect(chat.messages.last.toolNotes.single, startsWith('Reminder'));
  });

  test('an AI error becomes a friendly error bubble and retry recovers', () async {
    ai.error = Exception('RESOURCE_EXHAUSTED quota');
    await chat.send('hello');
    expect(chat.messages.last.isError, isTrue);
    expect(chat.messages.last.text, contains('usage limit'));

    ai.error = null;
    await chat.retry();
    expect(chat.messages, hasLength(2));
    expect(chat.messages.last.isError, isFalse);
    expect(chat.messages.last.text, 'Hello there!');
    expect(ai.histories.last, isEmpty, reason: 'failed turn is not replayed as history');
  });

  test('empty text is ignored; a photo alone gets a default question', () async {
    await chat.send('   ');
    expect(chat.messages, isEmpty);
    expect(ai.sent, isEmpty);

    final photo = Uint8List.fromList(tinyPng);
    await chat.send('', image: photo);
    expect(ai.sent.single, 'What is in this photo?');
    expect(ai.sentImages.single, photo);
    expect(chat.messages.first.hadImage, isTrue);
  });

  test('ignores a second send while a reply is streaming', () async {
    final first = chat.send('one');
    await chat.send('two');
    await first;
    expect(ai.sent, ['one']);
    expect(chat.messages.where((m) => m.sender == Sender.user), hasLength(1));
  });

  test('opening another chat mid-reply shows that chat and keeps the first', () async {
    final gate = Completer<void>();
    ai.onSend = (_) => gate.future;
    final first = chat.send('slow question');
    await Future<void>.delayed(Duration.zero);
    expect(chat.sending, isTrue);

    final other = Conversation(messages: [ChatMessage(sender: Sender.user, text: 'other chat')]);
    chat.open(other);
    expect(chat.conversation, same(other));
    expect(chat.sending, isFalse, reason: 'the new chat can be used right away');

    gate.complete();
    await first;
    expect(chat.conversation, same(other));
    expect(other.messages, hasLength(1), reason: 'the old reply does not leak into the new chat');
    expect(store.conversations.map((c) => c.displayTitle), contains('slow question'));
  });

  test('clearing or deleting history mid-reply does not bring the chat back', () async {
    var gate = Completer<void>();
    ai.onSend = (_) => gate.future;
    var pending = chat.send('secret plans');
    await Future<void>.delayed(Duration.zero);
    await store.clear();
    chat.newChat();
    gate.complete();
    await pending;
    expect(store.conversations, isEmpty);

    await chat.send('keep me');
    final id = chat.conversation.id;
    gate = Completer<void>();
    pending = chat.send('follow up');
    await Future<void>.delayed(Duration.zero);
    await store.delete(id);
    gate.complete();
    await pending;
    expect(store.conversations, isEmpty);
  });

  test('a tool result only shows on the reply that asked for it', () async {
    final slow = Completer<void>();
    ai.onSend = (text) async {
      if (text == 'first') await slow.future;
      await tools.run('set_reminder', {'message': 'From $text', 'in_minutes': text == 'first' ? 5 : 10});
    };
    final first = chat.send('first');
    await Future<void>.delayed(Duration.zero);
    final firstReply = chat.messages.last;

    chat.newChat();
    await chat.send('second');
    final secondReply = chat.messages.last;
    slow.complete(); // the first chat's tool finishes after the user moved on
    await first;

    expect(secondReply.toolNotes, hasLength(1));
    expect(firstReply.toolNotes, hasLength(1));
    expect(firstReply.toolNotes.single, isNot(secondReply.toolNotes.single));
  });
}
