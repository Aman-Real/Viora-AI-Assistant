import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import '../../core/config.dart';
import '../../data/models.dart';
import '../tools/tool_box.dart';
import 'ai_service.dart';

/// Gemini through Firebase AI Logic: no API key ships inside the app.
class GeminiAiService implements AiService {
  GeminiAiService(this.tools);

  final ToolBox tools;
  FirebaseAI get _ai => FirebaseAI.googleAI();

  @override
  bool get isDemo => false;

  Map<String, Schema> _params(AssistantTool t) => {
        for (final p in t.params)
          p.name: p.type == ParamType.integer
              ? Schema.integer(description: p.description)
              : Schema.string(description: p.description),
      };

  List<String> _optional(AssistantTool t) => [
        for (final p in t.params)
          if (p.optional) p.name,
      ];

  @override
  AiChat startChat({required List<ChatMessage> history, required String systemPrompt}) {
    final declarations = [
      for (final t in tools.tools)
        AutoFunctionDeclaration(
          name: t.name,
          description: t.description,
          parameters: _params(t),
          optionalParameters: _optional(t),
          callable: (args) => tools.run(t.name, args),
        ),
    ];
    final model = _ai.generativeModel(
      model: AppConfig.chatModel,
      systemInstruction: Content.system(systemPrompt),
      tools: [Tool.functionDeclarations(declarations)],
    );
    final session = model.startChat(
      history: [
        for (final m in cleanHistory(history))
          m.fromUser ? Content.text(m.text) : Content.model([TextPart(m.text)]),
      ],
      maxTurns: 5,
    );
    return _GeminiChat(session);
  }

  @override
  Future<LiveConnection> connectLive({required String systemPrompt, required String voice}) async {
    final model = _ai.liveGenerativeModel(
      model: AppConfig.liveModel,
      systemInstruction: Content.system(systemPrompt),
      tools: [
        Tool.functionDeclarations([
          for (final t in tools.tools)
            FunctionDeclaration(t.name, t.description,
                parameters: _params(t), optionalParameters: _optional(t)),
        ]),
      ],
      liveGenerationConfig: LiveGenerationConfig(
        speechConfig: SpeechConfig(voiceName: voice),
        responseModalities: [ResponseModalities.audio],
        inputAudioTranscription: AudioTranscriptionConfig(),
        outputAudioTranscription: AudioTranscriptionConfig(),
      ),
    );
    return _GeminiLive(await model.connect(), tools);
  }
}

class _GeminiChat implements AiChat {
  _GeminiChat(this._session);
  final ChatSession _session;

  @override
  Stream<String> send(String text, {Uint8List? image, String imageMime = 'image/jpeg'}) {
    final content = image == null
        ? Content.text(text)
        : Content.multi([TextPart(text), InlineDataPart(imageMime, image)]);
    return _session
        .sendMessageStream(content)
        .map((r) => r.text ?? '')
        .where((t) => t.isNotEmpty);
  }
}

class _GeminiLive implements LiveConnection {
  _GeminiLive(this._session, this._tools) {
    _sub = _session.receive().listen(
          _onMessage,
          onError: (Object e) => _emit(LiveEnded(e)),
          onDone: () => _emit(const LiveEnded()),
        );
  }

  final LiveSession _session;
  final ToolBox _tools;
  final _events = StreamController<LiveEvent>.broadcast();
  StreamSubscription<LiveServerResponse>? _sub;

  @override
  Stream<LiveEvent> get events => _events.stream;

  @override
  bool get playsAudio => true;

  void _emit(LiveEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  Future<void> _onMessage(LiveServerResponse response) async {
    try {
      await _handle(response.message);
    } catch (e) {
      debugPrint('Live message failed: $e');
    }
  }

  Future<void> _handle(LiveServerMessage message) async {
    switch (message) {
      case LiveServerContent(
          :final modelTurn,
          :final interrupted,
          :final turnComplete,
          :final inputTranscription,
          :final outputTranscription,
        ):
        for (final part in modelTurn?.parts ?? const <Part>[]) {
          if (part is InlineDataPart && part.mimeType.startsWith('audio')) _emit(LiveAudio(part.bytes));
        }
        if (inputTranscription?.text case final String t) {
          _emit(LiveTranscript(fromUser: true, text: t, finished: inputTranscription?.finished ?? false));
        }
        if (outputTranscription?.text case final String t) {
          _emit(LiveTranscript(fromUser: false, text: t, finished: outputTranscription?.finished ?? false));
        }
        if (interrupted ?? false) _emit(const LiveInterrupted());
        if (turnComplete ?? false) _emit(const LiveTurnComplete());
      case LiveServerToolCall(:final functionCalls?):
        final responses = <FunctionResponse>[];
        for (final call in functionCalls) {
          final result = await _tools.run(call.name, call.args);
          responses.add(FunctionResponse(call.name, result, id: call.id));
        }
        await _session.sendToolResponse(responses);
      default:
        debugPrint('Live message ignored: ${message.runtimeType}');
    }
  }

  @override
  Future<void> sendAudio(Uint8List pcm) => _session.sendAudioRealtime(InlineDataPart('audio/pcm', pcm));

  @override
  Future<void> close() async {
    await _sub?.cancel();
    await _session.close();
    await _events.close();
  }
}
