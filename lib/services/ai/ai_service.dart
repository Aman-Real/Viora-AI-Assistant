import 'dart:typed_data';

import '../../data/models.dart';

/// One ongoing text chat with memory of earlier turns.
abstract interface class AiChat {
  Stream<String> send(String text, {Uint8List? image, String imageMime});
}

/// Events coming back from a live voice session.
sealed class LiveEvent {
  const LiveEvent();
}

class LiveAudio extends LiveEvent {
  const LiveAudio(this.pcm);
  final Uint8List pcm;
}

class LiveTranscript extends LiveEvent {
  const LiveTranscript({required this.fromUser, required this.text, this.finished = false});
  final bool fromUser;
  final String text;
  final bool finished;
}

class LiveTurnComplete extends LiveEvent {
  const LiveTurnComplete();
}

class LiveInterrupted extends LiveEvent {
  const LiveInterrupted();
}

class LiveEnded extends LiveEvent {
  const LiveEnded([this.error]);
  final Object? error;
}

abstract interface class LiveConnection {
  Stream<LiveEvent> get events;

  /// False for demo sessions, which only send transcripts.
  bool get playsAudio;
  Future<void> sendAudio(Uint8List pcm);
  Future<void> close();
}

abstract interface class AiService {
  bool get isDemo;
  AiChat startChat({required List<ChatMessage> history, required String systemPrompt});
  Future<LiveConnection> connectLive({required String systemPrompt, required String voice});
}

/// Turns stored messages into a clean alternating user/model history.
List<ChatMessage> cleanHistory(List<ChatMessage> messages) {
  final out = <ChatMessage>[];
  for (final m in messages) {
    if (m.isError || m.isStreaming || m.text.trim().isEmpty) continue;
    if (out.isEmpty && !m.fromUser) continue;
    if (out.isNotEmpty && out.last.sender == m.sender) {
      out.last = ChatMessage(sender: m.sender, text: '${out.last.text}\n${m.text}');
    } else {
      out.add(m);
    }
  }
  if (out.isNotEmpty && out.last.fromUser) out.removeLast();
  return out;
}
