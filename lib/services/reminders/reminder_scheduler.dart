import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../data/models.dart';

/// Delivers a reminder when it is due.
abstract interface class ReminderScheduler {
  Future<void> init();
  Future<bool> requestPermission();
  Future<void> schedule(Reminder reminder);
  Future<void> cancel(int id);
}

/// Android: real scheduled notifications that fire even when the app is closed.
class NotificationReminderScheduler implements ReminderScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'Reminders you ask Viora to set',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
    ),
  );

  @override
  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (e) {
      debugPrint('Timezone lookup failed, using UTC: $e');
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
    );
  }

  @override
  Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? false;

  @override
  Future<void> schedule(Reminder reminder) async {
    // Android 13+: ask the first time a reminder is set, or it would never show.
    if (await _android?.areNotificationsEnabled() == false) await requestPermission();
    final exact = await _android?.canScheduleExactNotifications() ?? false;
    await _plugin.zonedSchedule(
      id: reminder.id,
      title: 'Viora reminder',
      body: reminder.message,
      scheduledDate: tz.TZDateTime.from(reminder.when, tz.local),
      notificationDetails: _details,
      androidScheduleMode:
          exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);
}

/// Web (browsers can't schedule notifications): fires while the app is open.
class InAppReminderScheduler implements ReminderScheduler {
  InAppReminderScheduler({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final _timers = <int, Timer>{};
  void Function(Reminder reminder)? onDue;

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule(Reminder reminder) async {
    _timers.remove(reminder.id)?.cancel();
    final delay = reminder.when.difference(_clock());
    if (delay.isNegative) return;
    _timers[reminder.id] = Timer(delay, () {
      _timers.remove(reminder.id);
      onDue?.call(reminder);
    });
  }

  @override
  Future<void> cancel(int id) async => _timers.remove(id)?.cancel();
}
