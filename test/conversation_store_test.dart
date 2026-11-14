import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:viora/data/conversation_store.dart';
import 'package:viora/data/key_value_store.dart';
import 'package:viora/data/models.dart';

Conversation convo(String text, {DateTime? at, Uint8List? image}) => Conversation(
      updatedAt: at,
      messages: [
        ChatMessage(sender: Sender.user, text: text, image: image),
        ChatMessage(sender: Sender.assistant, text: 'reply to $text'),
      ],
    );

void main() {
  test('save and load round-trip, newest first', () async {
    final kv = MemoryStore();
    final store = ConversationStore(kv);
    await store.save(convo('old', at: DateTime(2026, 1, 1)));
    await store.save(convo('new', at: DateTime(2026, 6, 1)));

    final reloaded = ConversationStore(kv);
    await reloaded.load();
    expect(reloaded.conversations.map((c) => c.displayTitle), ['new', 'old']);
    expect(reloaded.conversations.first.messages.last.text, 'reply to new');
  });

  test('delete and clear remove conversations', () async {
    final store = ConversationStore(MemoryStore());
    final a = convo('a');
    await store.save(a);
    await store.save(convo('b'));
    await store.delete(a.id);
    expect(store.conversations.map((c) => c.displayTitle), ['b']);
    await store.clear();
    expect(store.conversations, isEmpty);
  });

  test('image bytes are never written to storage', () async {
    final kv = MemoryStore();
    final store = ConversationStore(kv);
    await store.save(convo('photo', image: Uint8List(200000)));
    final raw = kv.data[ConversationStore.storageKey]!;
    expect(raw.length, lessThan(2000));
    expect(raw, contains('"hadImage":true'));

    final reloaded = ConversationStore(kv);
    await reloaded.load();
    final msg = reloaded.conversations.single.messages.first;
    expect(msg.hadImage, isTrue);
    expect(msg.image, isNull);
  });

  test('large histories are capped to keep storage small', () async {
    final store = ConversationStore(MemoryStore(), maxConversations: 50);
    for (var i = 0; i < 80; i++) {
      await store.save(convo('message $i', at: DateTime(2026, 1, 1).add(Duration(minutes: i))));
    }
    expect(store.conversations, hasLength(50));
    expect(store.conversations.first.displayTitle, 'message 79');
  });

  test('corrupt storage is ignored instead of crashing', () async {
    final store = ConversationStore(MemoryStore({ConversationStore.storageKey: '{not json'}));
    await store.load();
    expect(store.conversations, isEmpty);
  });

  test('empty conversations are not saved', () async {
    final store = ConversationStore(MemoryStore());
    await store.save(Conversation());
    expect(store.conversations, isEmpty);
  });

  test('titles and previews strip markdown and get shortened', () {
    final c = Conversation(messages: [
      ChatMessage(sender: Sender.user, text: 'Plan a **3 day** trip to the mountains with my college friends'),
      ChatMessage(sender: Sender.assistant, text: "Hi! I'm **Viora**.\n- `Day 1`: hike"),
    ]);
    expect(c.displayTitle, 'Plan a 3 day trip to the mountains with…');
    expect(c.preview, "Hi! I'm Viora. Day 1: hike");
  });
}
