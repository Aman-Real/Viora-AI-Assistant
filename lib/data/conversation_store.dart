import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'key_value_store.dart';
import 'models.dart';

/// Saved chat and voice conversations, newest first.
class ConversationStore extends ChangeNotifier {
  ConversationStore(this._kv, {this.maxConversations = 50});

  static const storageKey = 'viora.conversations.v1';
  final KeyValueStore _kv;
  final int maxConversations;
  final List<Conversation> _items = [];
  final Set<String> _deleted = {};

  /// Changes every time all history is cleared.
  int epoch = 0;

  bool wasDeleted(String id) => _deleted.contains(id);

  List<Conversation> get conversations => List.unmodifiable(_items);

  Conversation? byId(String id) => _items.where((c) => c.id == id).firstOrNull;

  Future<void> load() async {
    final raw = await _kv.read(storageKey);
    _items.clear();
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List<Object?>).cast<Map<String, Object?>>();
        _items.addAll(list.map(Conversation.fromJson));
      } catch (e) {
        debugPrint('Corrupt history ignored: $e');
      }
    }
    _sort();
    notifyListeners();
  }

  Future<void> save(Conversation conversation) async {
    if (conversation.messages.isEmpty) return;
    _deleted.remove(conversation.id);
    _items.removeWhere((c) => c.id == conversation.id);
    _items.add(conversation);
    _sort();
    if (_items.length > maxConversations) _items.removeRange(maxConversations, _items.length);
    await _persist();
  }

  Future<void> delete(String id) async {
    _deleted.add(id);
    _items.removeWhere((c) => c.id == id);
    await _persist();
  }

  Future<void> clear() async {
    epoch++;
    _items.clear();
    await _kv.remove(storageKey);
    notifyListeners();
  }

  void _sort() => _items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<void> _persist() async {
    notifyListeners();
    await _kv.write(storageKey, jsonEncode(_items.map((c) => c.toJson()).toList()));
  }
}
