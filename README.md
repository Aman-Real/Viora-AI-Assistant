# Viora

A Flutter voice assistant. Tap the mic, speak, and Viora transcribes your speech, sends it to Google's Gemini API, and reads the answer back out loud.

## Features

- **Speech to text** — on-device speech recognition via `speech_to_text`
- **Gemini-powered replies** — prompts are sent to `gemini-flash-latest` through the Generative Language REST API
- **Text to speech** — responses are spoken back using `flutter_tts`
- **Animated UI** — staggered entry animations (`animate_do`) over a light, single-screen Material 3 layout

## Screens

One screen. An assistant avatar, a chat bubble that shows either the greeting or Gemini's last reply, three feature cards that hide once a response arrives, and a floating mic button that toggles between listen and stop.

## Project structure

```
lib/
├── main.dart               # App entry point, MaterialApp + light theme
├── home_page.dart          # Main screen: STT, TTS, Gemini call, UI
├── gemini_services.dart    # HTTP client for the Gemini generateContent endpoint
├── features_box.dart       # Reusable feature card widget
├── pallete.dart            # Color constants
└── secrets_gemini.dart     # API key (gitignored)
```

## Getting started

### Prerequisites

- Flutter SDK 3.x with Dart 3 (the code uses `super.key`)
- A Gemini API key from [Google AI Studio](https://aistudio.google.com/app/apikey)
- A physical device or emulator with a working microphone — speech recognition does not work reliably on some emulators

### Install

```bash
git clone <your-repo-url>
cd viora
flutter pub get
```

### Dependencies

Make sure `pubspec.yaml` includes:

```yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.2.0
  speech_to_text: ^7.0.0
  flutter_tts: ^4.0.2
  animate_do: ^3.3.4
```

And the assets and font used by the UI:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/images/virtualAssistant.png
  fonts:
    - family: Cera Pro
      fonts:
        - asset: assets/fonts/CeraPro-Regular.otf
        - asset: assets/fonts/CeraPro-Bold.otf
          weight: 700
```

### API key

Put your key in `lib/secrets_gemini.dart`:

```dart
const GEMINIAPIKey = 'your-key-here';
```

Then add it to `.gitignore`:

```
lib/secrets_gemini.dart
```

> **Note:** `gemini_services.dart` currently has the key pasted directly into the request URL and never imports `secrets_gemini.dart`. Wire it up before shipping — see [Known issues](#known-issues).

### Permissions

**Android** — `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>
<queries>
    <intent>
        <action android:name="android.speech.RecognitionService" />
    </intent>
    <intent>
        <action android:name="android.intent.action.TTS_SERVICE" />
    </intent>
</queries>
```

Minimum SDK 21 in `android/app/build.gradle`.

**iOS** — `ios/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Viora needs the microphone to hear your questions.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Viora needs speech recognition to understand you.</string>
```

### Run

```bash
flutter run
```

## How it works

1. `initState` initializes both the speech recognizer and the TTS engine.
2. First mic tap calls `startListening()`; recognized words stream into `lastWords`.
3. Second tap sends `lastWords` to `GeminiService.getResponse()`, which POSTs a `contents.parts.text` payload to the `generateContent` endpoint.
4. The reply is pulled from `candidates[0].content.parts[0].text`, rendered in the bubble, and spoken with `flutterTts.speak()`.

## Known issues

- **Hardcoded API key.** The key lives in the URL string inside `gemini_services.dart` while `secrets_gemini.dart` sits unused. Import the constant and interpolate it instead — or, better, load it from `--dart-define` so it never touches source control. Note that any key bundled into a client app is extractable; a thin backend proxy is the real fix.
- **No loading state.** There is no spinner between the tap and the response, so the UI looks frozen on slow networks.
- **Unused image path.** `generatedImageUrl` is declared and checked throughout the widget tree but nothing ever assigns it — leftover from an image-generation feature.
- **Stale transcript.** `lastWords` isn't cleared after a query, so a tap that picks up no speech can re-send the previous prompt.
- **`dispose()` ordering.** `super.dispose()` is called before `speechToText.stop()` and `flutterTts.stop()`; it should come last.
- **Brittle JSON parsing.** The response is indexed without null checks — a blocked or empty candidate throws.

## License

MIT — see `LICENSE`.
