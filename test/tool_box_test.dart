import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:viora/data/key_value_store.dart';
import 'package:viora/services/reminders/reminder_service.dart';
import 'package:viora/services/tools/tool_box.dart';

import 'helpers/fakes.dart';

void main() {
  final now = DateTime(2026, 11, 11, 10, 0);
  late FakeScheduler scheduler;
  late FakeLinks links;
  late FakeConfirmer confirmer;
  late ReminderService reminders;

  ToolBox build({http.Client? client}) => ToolBox(
        reminders: reminders,
        links: links,
        confirmer: confirmer,
        httpClient: client,
        clock: () => now,
      );

  setUp(() {
    scheduler = FakeScheduler();
    links = FakeLinks();
    confirmer = FakeConfirmer();
    reminders = ReminderService(MemoryStore(), scheduler, clock: () => now);
  });

  test('set_reminder with in_minutes schedules a notification', () async {
    final result = await build().run('set_reminder', {'message': 'Drink water', 'in_minutes': 10});
    expect(result['ok'], isTrue);
    expect(scheduler.scheduled.single.when, now.add(const Duration(minutes: 10)));
    expect(reminders.upcoming.single.message, 'Drink water');
  });

  test('set_reminder with a clock time, and past times are rejected', () async {
    final tools = build();
    final ok = await tools.run('set_reminder', {'message': 'Call Mom', 'at_time': '2026-11-11T18:30:00'});
    expect(ok['ok'], isTrue);
    expect(reminders.upcoming.single.when, DateTime(2026, 11, 11, 18, 30));

    final past = await tools.run('set_reminder', {'message': 'Too late', 'at_time': '2026-11-11T09:00:00'});
    expect(past['error'], contains('passed'));
    final none = await tools.run('set_reminder', {'message': 'When?'});
    expect(none['error'], isNotNull);
    expect(reminders.upcoming, hasLength(1));
  });

  test('list_reminders and get_current_datetime', () async {
    final tools = build();
    await tools.run('set_reminder', {'message': 'Stand up', 'in_minutes': 30});
    final list = await tools.run('list_reminders', {});
    expect((list['reminders']! as List).single, containsPair('message', 'Stand up'));
    final time = await tools.run('get_current_datetime', {});
    expect(time['readable'], 'Wednesday, 11 November 2026, 10:00 AM');
  });

  test('get_weather geocodes the city and reads the forecast', () async {
    final client = MockClient((req) async {
      if (req.url.host.startsWith('geocoding')) {
        expect(req.url.queryParameters['name'], 'Dehradun');
        return http.Response(jsonEncode({
          'results': [
            {'name': 'Dehradun', 'country': 'India', 'latitude': 30.3, 'longitude': 78.0},
          ],
        }), 200);
      }
      return http.Response(jsonEncode({
        'current': {
          'temperature_2m': 21.4,
          'apparent_temperature': 20.0,
          'relative_humidity_2m': 40,
          'weather_code': 2,
          'wind_speed_10m': 6.0,
        },
        'daily': {
          'temperature_2m_max': [24.0],
          'temperature_2m_min': [11.0],
        },
      }), 200);
    });
    final tools = build(client: client);
    final notes = <String>[];
    tools.activity.listen((a) => notes.add(a.summary));
    final w = await tools.run('get_weather', {'city': 'Dehradun'});
    expect(w['place'], 'Dehradun, India');
    expect(w['conditions'], 'partly cloudy');
    expect(w['today_high_c'], 24.0);
    await Future<void>.delayed(Duration.zero);
    expect(notes.single, 'Dehradun, India · 21°C, partly cloudy');
  });

  test('weather failures come back as an error, not an exception', () async {
    final tools = build(client: MockClient((_) async => http.Response('down', 503)));
    final w = await tools.run('get_weather', {'city': 'Delhi'});
    expect(w['error'], contains('503'));
    final unknown = await build(client: MockClient((_) async => http.Response('{}', 200)))
        .run('get_weather', {'city': 'Nowhere'});
    expect(unknown['error'], contains('could not find'));
  });

  test('links: only http(s) opens; search builds a Google URL', () async {
    final tools = build();
    expect((await tools.run('open_link', {'url': 'javascript:alert(1)'}))['error'], isNotNull);
    await tools.run('open_link', {'url': 'https://flutter.dev'});
    await tools.run('web_search', {'query': 'gemini live api'});
    expect(links.opened.map((u) => u.toString()),
        ['https://flutter.dev', 'https://www.google.com/search?q=gemini+live+api']);
  });

  test('call and SMS need confirmation and clean the number', () async {
    final tools = build();
    confirmer.answer = false;
    final cancelled = await tools.run('call_phone', {'number': '+91 98765-43210'});
    expect(cancelled['error'], contains('cancelled'));
    expect(links.opened, isEmpty);

    confirmer.answer = true;
    await tools.run('call_phone', {'number': '+91 98765-43210'});
    await tools.run('send_sms', {'number': '98765 43210', 'message': 'On my way'});
    expect(links.opened.first.toString(), 'tel:+919876543210');
    expect(links.opened.last.scheme, 'sms');
    expect(links.opened.last.queryParameters['body'], 'On my way');
    expect(confirmer.asked, hasLength(3));
  });

  test('cleanNumber rejects junk and unknown tools fail softly', () async {
    expect(ToolBox.cleanNumber('call me'), isNull);
    expect(ToolBox.cleanNumber('12+34'), isNull);
    expect(ToolBox.cleanNumber('(011) 2345-6789'), '01123456789');
    expect((await build().run('fly_to_moon', {}))['error'], contains('Unknown'));
  });

  test('reminders persist and are rescheduled after a restart', () async {
    final kv = MemoryStore();
    final first = ReminderService(kv, FakeScheduler(), clock: () => now);
    await first.add('Meeting', now.add(const Duration(hours: 1)));
    final restartScheduler = FakeScheduler();
    final second = ReminderService(kv, restartScheduler, clock: () => now);
    await second.load();
    expect(second.upcoming.single.message, 'Meeting');
    expect(restartScheduler.scheduled, hasLength(1));
    await second.remove(second.upcoming.single.id);
    expect(restartScheduler.cancelled, hasLength(1));
    expect(second.all, isEmpty);
  });
}
