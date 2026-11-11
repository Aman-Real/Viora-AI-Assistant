import 'package:flutter_test/flutter_test.dart';
import 'package:viora/data/models.dart';
import 'package:viora/services/reminders/reminder_scheduler.dart';

void main() {
  test('web reminders far ahead wait in hops instead of firing early', () async {
    final now = DateTime(2026, 11, 11);
    final scheduler = InAppReminderScheduler(clock: () => now, maxTimer: const Duration(milliseconds: 20));
    final fired = <int>[];
    scheduler.onDue = (r) => fired.add(r.id);
    await scheduler.schedule(Reminder(id: 1, message: 'Renew passport', when: now.add(const Duration(days: 40))));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(fired, isEmpty);
    await scheduler.cancel(1);
  });

  test('web reminders fire when due and can be cancelled', () async {
    final scheduler = InAppReminderScheduler();
    final fired = <int>[];
    scheduler.onDue = (r) => fired.add(r.id);
    final soon = DateTime.now().add(const Duration(milliseconds: 30));
    await scheduler.schedule(Reminder(id: 2, message: 'Stretch', when: soon));
    await scheduler.schedule(Reminder(id: 3, message: 'Cancelled', when: soon));
    await scheduler.cancel(3);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(fired, [2]);
  });
}
