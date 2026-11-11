import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:viora/app_services.dart';
import 'package:viora/data/conversation_store.dart';
import 'package:viora/data/key_value_store.dart';
import 'package:viora/data/models.dart';
import 'package:viora/services/ai/ai_service.dart';
import 'package:viora/services/platform/device_actions.dart';
import 'package:viora/services/reminders/reminder_scheduler.dart';
import 'package:viora/services/reminders/reminder_service.dart';
import 'package:viora/services/tools/tool_box.dart';
import 'package:viora/services/voice/audio_io.dart';

class FakeChat implements AiChat {
  FakeChat(this.ai);
  final FakeAi ai;

  @override
  Stream<String> send(String text, {Uint8List? image, String imageMime = 'image/jpeg'}) async* {
    ai.sent.add(text);
    ai.sentImages.add(image);
    if (ai.onSend != null) await ai.onSend!(text);
    if (ai.error != null) throw ai.error!;
    for (final chunk in ai.replyChunks) {
      await Future<void>.delayed(Duration.zero);
      yield chunk;
    }
  }
}

class FakeAi implements AiService {
  List<String> replyChunks = ['Hello ', 'there!'];
  Object? error;
  Future<void> Function(String text)? onSend;
  final sent = <String>[];
  final sentImages = <Uint8List?>[];
  final histories = <List<ChatMessage>>[];
  final prompts = <String>[];
  FakeLive? live;
  Object? connectError;
  int connects = 0;

  @override
  bool get isDemo => false;

  @override
  AiChat startChat({required List<ChatMessage> history, required String systemPrompt}) {
    histories.add(List.of(history));
    prompts.add(systemPrompt);
    return FakeChat(this);
  }

  @override
  Future<LiveConnection> connectLive({required String systemPrompt, required String voice}) async {
    connects++;
    prompts.add(systemPrompt);
    if (connectError != null) throw connectError!;
    return live = FakeLive();
  }
}

class FakeLive implements LiveConnection {
  final controller = StreamController<LiveEvent>.broadcast();
  final audioSent = <Uint8List>[];
  bool closed = false;
  Duration closeDelay = Duration.zero;

  void emit(LiveEvent e) => controller.add(e);

  @override
  Stream<LiveEvent> get events => controller.stream;

  @override
  bool get playsAudio => true;

  @override
  Future<void> sendAudio(Uint8List pcm) async => audioSent.add(pcm);

  @override
  Future<void> close() async {
    closed = true;
    await Future<void>.delayed(closeDelay);
    await controller.close();
  }
}

class FakeMic implements MicInput {
  bool permitted = true;
  bool recording = false;
  final _audio = StreamController<Uint8List>.broadcast();
  final _levels = StreamController<double>.broadcast();

  void speak(Uint8List pcm) => _audio.add(pcm);
  void level(double l) => _levels.add(l);

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Future<Stream<Uint8List>> start() async {
    recording = true;
    return _audio.stream;
  }

  @override
  Future<void> stop() async => recording = false;
}

class FakeAudioOut implements AudioOutput {
  final played = <Uint8List>[];
  int interrupts = 0;

  @override
  Future<void> init() async {}

  @override
  void add(Uint8List pcm) => played.add(pcm);

  @override
  Future<void> interrupt() async => interrupts++;
}

class FakeScheduler implements ReminderScheduler {
  final scheduled = <Reminder>[];
  final cancelled = <int>[];

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule(Reminder reminder) async => scheduled.add(reminder);

  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}

class FakeLinks implements LinkOpener {
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }
}

class FakeConfirmer implements ActionConfirmer {
  FakeConfirmer([this.answer = true]);
  bool answer;
  final asked = <String>[];

  @override
  Future<bool> confirm(String title, String message, {String action = 'Continue'}) async {
    asked.add(title);
    return answer;
  }
}

class FakePhotos implements PhotoPicker {
  PickedPhoto? next = PickedPhoto(Uint8List.fromList(tinyPng), 'image/png');

  @override
  Future<PickedPhoto?> pick({required bool fromCamera}) async => next;
}

/// A valid 1x1 PNG so Image.memory can decode it.
const tinyPng = [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, //
  21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 94, 99, 168, 78, 252, 255, 31, 0, 6, 17, 2, 219, 193, 105, //
  14, 182, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
];

/// Builds AppServices entirely from fakes.
AppServices fakeServices({FakeAi? ai, MemoryStore? kv, DateTime Function()? clock}) {
  final store = kv ?? MemoryStore();
  final reminders = ReminderService(store, FakeScheduler(), clock: clock);
  final tools = ToolBox(reminders: reminders, links: FakeLinks(), confirmer: FakeConfirmer(), clock: clock);
  return AppServices(
    kv: store,
    ai: ai ?? FakeAi(),
    tools: tools,
    reminders: reminders,
    conversations: ConversationStore(store),
    mic: FakeMic(),
    audioOut: FakeAudioOut(),
    photos: FakePhotos(),
    navigatorKey: GlobalKey<NavigatorState>(),
    messengerKey: GlobalKey<ScaffoldMessengerState>(),
  );
}
