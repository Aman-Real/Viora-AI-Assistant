import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/key_value_store.dart';
import '../../data/models.dart';
import 'reminder_scheduler.dart';

class ReminderException implements Exception {
  ReminderException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Stores reminders and hands them to the platform scheduler.
class ReminderService extends ChangeNotifier {
  ReminderService(this._kv, this.scheduler, {DateTime Function()? clock})
      : clock = clock ?? DateTime.now;

  static const storageKey = 'viora.reminders.v1';
  final KeyValueStore _kv;
  final ReminderScheduler scheduler;
  final DateTime Function() clock;
  final List<Reminder> _items = [];

  List<Reminder> get all => List.unmodifiable(_items);
  List<Reminder> get upcoming => _items.where((r) => !r.isPast(clock())).toList();
  List<Reminder> get past => _items.where((r) => r.isPast(clock())).toList().reversed.toList();

  Future<void> load() async {
    final raw = await _kv.read(storageKey);
    _items.clear();
    if (raw != null) {
      try {
        _items.addAll((jsonDecode(raw) as List<Object?>)
            .cast<Map<String, Object?>>()
            .map(Reminder.fromJson));
      } catch (e) {
        debugPrint('Corrupt reminders ignored: $e');
      }
    }
    _items.sort((a, b) => a.when.compareTo(b.when));
    for (final r in upcoming) {
      await _safely(() => scheduler.schedule(r));
    }
    notifyListeners();
  }

  Future<Reminder> add(String message, DateTime when) async {
    final text = message.trim();
    final now = clock();
    if (text.isEmpty) throw ReminderException('The reminder needs a message.');
    if (!when.isAfter(now.add(const Duration(seconds: 5)))) {
      throw ReminderException('That time has already passed.');
    }
    if (when.isAfter(now.add(const Duration(days: 366)))) {
      throw ReminderException('Reminders can be at most a year ahead.');
    }
    final id = _items.fold(0, (top, r) => r.id > top ? r.id : top) + 1;
    final reminder = Reminder(id: id, message: text, when: when, createdAt: now);
    _items
      ..add(reminder)
      ..sort((a, b) => a.when.compareTo(b.when));
    await _safely(() => scheduler.schedule(reminder));
    await _persist();
    return reminder;
  }

  Future<void> remove(int id) async {
    _items.removeWhere((r) => r.id == id);
    await _safely(() => scheduler.cancel(id));
    await _persist();
  }

  Future<void> _persist() async {
    notifyListeners();
    await _kv.write(storageKey, jsonEncode(_items.map((r) => r.toJson()).toList()));
  }

  Future<void> _safely(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('Reminder scheduler error: $e');
    }
  }
}
