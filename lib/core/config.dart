import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Build-time settings, passed with `--dart-define-from-file=firebase.env.json`.
/// Without Firebase values (or with VIORA_DEMO=true) the app runs in demo mode.
abstract final class AppConfig {
  static const forceDemo = bool.fromEnvironment('VIORA_DEMO');

  static const chatModel = String.fromEnvironment(
    'VIORA_CHAT_MODEL',
    defaultValue: 'gemini-3.5-flash-lite',
  );
  static const liveModel = String.fromEnvironment(
    'VIORA_LIVE_MODEL',
    defaultValue: 'gemini-2.5-flash-native-audio-preview-09-2025',
  );

  /// Firebase AI Logic only answers apps that pass App Check. A debug token
  /// registered in the Firebase console authorises personal and test builds;
  /// without one, Android uses Play Integrity and web uses reCAPTCHA Enterprise.
  static const appCheckDebugToken = String.fromEnvironment('APP_CHECK_DEBUG_TOKEN');
  static const recaptchaSiteKey = String.fromEnvironment('RECAPTCHA_ENTERPRISE_SITE_KEY');

  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const _androidApiKey = String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
  static const _androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const _webApiKey = String.fromEnvironment('FIREBASE_WEB_API_KEY');
  static const _webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const _authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');

  static FirebaseOptions? get firebaseOptions {
    final apiKey = kIsWeb ? _webApiKey : _androidApiKey;
    final appId = kIsWeb ? _webAppId : _androidAppId;
    if (apiKey.isEmpty || appId.isEmpty || _projectId.isEmpty) return null;
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: _senderId,
      projectId: _projectId,
      authDomain: _authDomain.isEmpty ? null : _authDomain,
    );
  }

  static bool get demoRequested => forceDemo || firebaseOptions == null;
}
