import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/key_value_store.dart';
import '../../data/models.dart';

enum ReplyLanguage { auto, english, hindi }

class SettingsController extends ChangeNotifier {
  SettingsController(this._kv, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const storageKey = 'viora.settings.v1';
  static const voices = ['Kore', 'Puck', 'Charon', 'Aoede', 'Fenrir'];

  final KeyValueStore _kv;
  final DateTime Function() _clock;

  ThemeMode themeMode = ThemeMode.dark;
  ReplyLanguage language = ReplyLanguage.auto;
  String voice = voices.first;
  bool reduceMotion = false;
  bool onboarded = false;

  Future<void> load() async {
    final raw = await _kv.read(storageKey);
    if (raw == null) return;
    try {
      final j = (jsonDecode(raw) as Map).cast<String, Object?>();
      themeMode = ThemeMode.values.asNameMap()[j['theme']] ?? themeMode;
      language = ReplyLanguage.values.asNameMap()[j['language']] ?? language;
      voice = voices.contains(j['voice']) ? j['voice']! as String : voice;
      reduceMotion = j['reduceMotion'] == true;
      onboarded = j['onboarded'] == true;
    } catch (e) {
      debugPrint('Settings reset: $e');
    }
    notifyListeners();
  }

  void setThemeMode(ThemeMode v) => _update(() => themeMode = v);
  void setLanguage(ReplyLanguage v) => _update(() => language = v);
  void setVoice(String v) => _update(() => voice = v);
  void setReduceMotion(bool v) => _update(() => reduceMotion = v);
  void completeOnboarding() => _update(() => onboarded = true);

  void _update(VoidCallback change) {
    change();
    notifyListeners();
    unawaited(_kv.write(
      storageKey,
      jsonEncode({
        'theme': themeMode.name,
        'language': language.name,
        'voice': voice,
        'reduceMotion': reduceMotion,
        'onboarded': onboarded,
      }),
    ));
  }

  /// Instructions sent to Gemini with every chat and voice session.
  String systemPrompt({bool voiceMode = false, List<ChatMessage> recent = const []}) {
    final now = _clock();
    final lang = switch (language) {
      ReplyLanguage.auto => "Reply in the user's language (English, Hindi or Hinglish).",
      ReplyLanguage.english => 'Always reply in English.',
      ReplyLanguage.hindi => 'Always reply in Hindi (Devanagari script) unless asked otherwise.',
    };
    final style = voiceMode
        ? 'You are speaking out loud: keep answers to one to three short sentences, no markdown or lists.'
        : 'Use short paragraphs and light markdown (bold, bullet lists) when it helps.';
    final memory = recent.isEmpty
        ? ''
        : '\nRecent conversation for context:\n${recent.map((m) => '${m.fromUser ? 'User' : 'Viora'}: ${m.text}').join('\n')}';
    return '''
You are Viora, a friendly, sharp AI assistant in a mobile app.
Current local time: ${DateFormat('EEEE d MMMM y, h:mm a').format(now)} (${now.timeZoneName}).
$lang
$style
Use your tools for reminders, the time, weather, opening links, web searches, calls and SMS. Never pretend a tool ran. For calls and SMS the user confirms on screen.
If the user shares a photo, describe what matters and answer their question about it.$memory''';
  }
}
