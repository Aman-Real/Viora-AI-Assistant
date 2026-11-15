import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../platform/device_actions.dart';
import '../reminders/reminder_service.dart';

enum ParamType { string, integer }

class ToolParam {
  const ToolParam(this.name, this.type, this.description, {this.optional = false});
  final String name;
  final ParamType type;
  final String description;
  final bool optional;
}

typedef ToolResult = Map<String, Object?>;

class AssistantTool {
  const AssistantTool(this.name, this.description, this.params, this.handler);
  final String name;
  final String description;
  final List<ToolParam> params;
  final Future<ToolResult> Function(Map<String, Object?> args) handler;
}

/// Something a tool did, shown as a chip in the chat.
class ToolActivity {
  const ToolActivity(this.tool, this.summary, {this.ok = true});
  final String tool;
  final String summary;
  final bool ok;
}

/// The actions Viora can take. Shared by chat (auto function calling) and live voice.
class ToolBox {
  ToolBox({
    required this.reminders,
    required this.links,
    required this.confirmer,
    http.Client? httpClient,
    DateTime Function()? clock,
  })  : _http = httpClient ?? http.Client(),
        _clock = clock ?? DateTime.now;

  final ReminderService reminders;
  final LinkOpener links;
  final ActionConfirmer confirmer;
  final http.Client _http;
  final DateTime Function() _clock;
  final _activity = StreamController<ToolActivity>.broadcast();

  /// Tool activity that no chat reply claimed (for example in voice mode).
  Stream<ToolActivity> get activity => _activity.stream;

  static const _sinkKey = #vioraToolActivitySink;

  /// Runs [body] so that the tools it triggers report to [onActivity] only.
  /// Each chat reply uses this, so a tool's result chip can never land on a
  /// different reply, even when two replies are in flight.
  static R capture<R>(void Function(ToolActivity) onActivity, R Function() body) =>
      runZoned(body, zoneValues: {_sinkKey: onActivity});

  void _emit(ToolActivity a) {
    final sink = Zone.current[_sinkKey];
    if (sink is void Function(ToolActivity)) {
      sink(a);
    } else if (!_activity.isClosed) {
      _activity.add(a);
    }
  }

  static final _readable = DateFormat('EEE d MMM, h:mm a');

  late final List<AssistantTool> tools = [
    AssistantTool(
      'get_current_datetime',
      'Get the current local date, time and weekday.',
      const [],
      (_) async {
        final now = _clock();
        return {
          'iso': now.toIso8601String(),
          'readable': DateFormat('EEEE, d MMMM y, h:mm a').format(now),
          'timezone': now.timeZoneName,
        };
      },
    ),
    AssistantTool(
      'set_reminder',
      'Set a reminder that notifies the user later. Use in_minutes for relative times '
          '("in 20 minutes") or at_time for clock times.',
      const [
        ToolParam('message', ParamType.string, 'What to remind the user about, e.g. "call Mom".'),
        ToolParam('in_minutes', ParamType.integer, 'Minutes from now.', optional: true),
        ToolParam('at_time', ParamType.string,
            'Local date-time in ISO 8601, e.g. 2026-11-11T18:30:00.', optional: true),
      ],
      _setReminder,
    ),
    AssistantTool(
      'list_reminders',
      'List the upcoming reminders.',
      const [],
      (_) async => {
        'reminders': [
          for (final r in reminders.upcoming) {'message': r.message, 'when': _readable.format(r.when)},
        ],
      },
    ),
    AssistantTool(
      'get_weather',
      'Get the current weather and today\'s high/low for a city.',
      const [ToolParam('city', ParamType.string, 'City name, e.g. "Dehradun".')],
      _weather,
    ),
    AssistantTool(
      'open_link',
      'Open a web page (https URL) in the browser.',
      const [ToolParam('url', ParamType.string, 'Full https URL.')],
      (args) async {
        final uri = Uri.tryParse(_string(args, 'url'));
        if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
          return {'error': 'Only http(s) links can be opened.'};
        }
        return _open(uri, 'Opened ${uri.host}');
      },
    ),
    AssistantTool(
      'web_search',
      'Search the web in the browser.',
      const [ToolParam('query', ParamType.string, 'What to search for.')],
      (args) async {
        final q = _string(args, 'query');
        if (q.isEmpty) return {'error': 'Empty search.'};
        return _open(Uri.https('www.google.com', '/search', {'q': q}), 'Searched "$q"');
      },
    ),
    AssistantTool(
      'call_phone',
      'Open the phone dialer with a number filled in (the user taps call).',
      const [ToolParam('number', ParamType.string, 'Phone number with country code if known.')],
      (args) async {
        final number = cleanNumber(_string(args, 'number'));
        if (number == null) return {'error': 'That does not look like a phone number.'};
        if (!await confirmer.confirm('Call $number?', 'Viora will open your dialer.', action: 'Open dialer')) {
          return _cancelled('Call');
        }
        return _open(Uri(scheme: 'tel', path: number), 'Dialer opened for $number');
      },
    ),
    AssistantTool(
      'send_sms',
      'Open the SMS app with a message ready to send (the user taps send).',
      const [
        ToolParam('number', ParamType.string, 'Phone number.'),
        ToolParam('message', ParamType.string, 'Message text.'),
      ],
      (args) async {
        final number = cleanNumber(_string(args, 'number'));
        final body = _string(args, 'message');
        if (number == null) return {'error': 'That does not look like a phone number.'};
        if (!await confirmer.confirm('Text $number?', '"$body"', action: 'Open messages')) {
          return _cancelled('SMS');
        }
        return _open(Uri(scheme: 'sms', path: number, queryParameters: {'body': body}),
            'Message ready for $number');
      },
    ),
  ];

  AssistantTool? find(String name) => tools.where((t) => t.name == name).firstOrNull;

  /// Runs a tool by name; never throws, errors come back as {'error': ...}.
  Future<ToolResult> run(String name, Map<String, Object?> args) async {
    final tool = find(name);
    if (tool == null) return {'error': 'Unknown tool $name'};
    try {
      final result = await tool.handler(args);
      if (result['error'] case final String error) {
        _emit(ToolActivity(name, error, ok: false));
      }
      return result;
    } catch (e) {
      _emit(ToolActivity(name, 'Failed: $e', ok: false));
      return {'error': '$e'};
    }
  }

  Future<ToolResult> _setReminder(Map<String, Object?> args) async {
    final message = _string(args, 'message');
    final minutes = args['in_minutes'];
    final at = _string(args, 'at_time');
    DateTime? when;
    if (minutes is num && minutes > 0) {
      when = _clock().add(Duration(seconds: (minutes * 60).round()));
    } else if (at.isNotEmpty) {
      // No offset = local time; an offset/Z parses as UTC.
      final parsed = DateTime.tryParse(at);
      when = parsed != null && parsed.isUtc ? parsed.toLocal() : parsed;
    }
    if (when == null) return {'error': 'I need a time: minutes from now or a clock time.'};
    try {
      final r = await reminders.add(message, when);
      _emit(ToolActivity('set_reminder', 'Reminder · ${_readable.format(r.when)}'));
      return {'ok': true, 'message': r.message, 'scheduled_for': _readable.format(r.when)};
    } on ReminderException catch (e) {
      return {'error': e.message};
    }
  }

  Future<ToolResult> _weather(Map<String, Object?> args) async {
    final city = _string(args, 'city');
    if (city.isEmpty) return {'error': 'Which city?'};
    final geo = await _getJson(Uri.https('geocoding-api.open-meteo.com', '/v1/search',
        {'name': city, 'count': '1', 'language': 'en', 'format': 'json'}));
    final results = geo['results'] as List<Object?>?;
    if (results == null || results.isEmpty) return {'error': 'I could not find "$city".'};
    final place = (results.first as Map).cast<String, Object?>();
    final data = await _getJson(Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '${place['latitude']}',
      'longitude': '${place['longitude']}',
      'current': 'temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m',
      'daily': 'temperature_2m_max,temperature_2m_min',
      'timezone': 'auto',
      'forecast_days': '1',
    }));
    final current = (data['current'] as Map).cast<String, Object?>();
    final daily = (data['daily'] as Map).cast<String, Object?>();
    final name = '${place['name']}, ${place['country'] ?? ''}'.trim();
    final temp = (current['temperature_2m'] as num).round();
    final sky = describeWeather((current['weather_code'] as num).toInt());
    _emit(ToolActivity('get_weather', '$name · $temp°C, $sky'));
    return {
      'place': name,
      'temperature_c': current['temperature_2m'],
      'feels_like_c': current['apparent_temperature'],
      'humidity_percent': current['relative_humidity_2m'],
      'wind_kmh': current['wind_speed_10m'],
      'conditions': sky,
      'today_high_c': (daily['temperature_2m_max'] as List).first,
      'today_low_c': (daily['temperature_2m_min'] as List).first,
    };
  }

  Future<Map<String, Object?>> _getJson(Uri uri) async {
    final res = await _http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Weather service error ${res.statusCode}');
    return (jsonDecode(res.body) as Map).cast<String, Object?>();
  }

  Future<ToolResult> _open(Uri uri, String summary) async {
    final ok = await links.open(uri);
    if (ok) _emit(ToolActivity('link', summary));
    return ok ? {'ok': true} : {'error': 'No app could open that.'};
  }

  ToolResult _cancelled(String what) {
    _emit(ToolActivity('cancelled', '$what cancelled', ok: false));
    return {'error': 'The user cancelled.'};
  }

  static String _string(Map<String, Object?> args, String key) => '${args[key] ?? ''}'.trim();

  /// Keeps digits and a leading +; returns null if it isn't a plausible number.
  static String? cleanNumber(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^\d+]'), '');
    final digits = cleaned.replaceAll('+', '');
    if (digits.length < 3 || digits.length > 15 || cleaned.lastIndexOf('+') > 0) return null;
    return cleaned;
  }

  static String describeWeather(int code) => switch (code) {
        0 => 'clear sky',
        1 || 2 => 'partly cloudy',
        3 => 'overcast',
        45 || 48 => 'fog',
        >= 51 && <= 57 => 'drizzle',
        >= 61 && <= 67 => 'rain',
        >= 71 && <= 77 => 'snow',
        >= 80 && <= 82 => 'rain showers',
        85 || 86 => 'snow showers',
        >= 95 => 'thunderstorm',
        _ => 'mixed conditions',
      };

  void dispose() => _activity.close();
}
