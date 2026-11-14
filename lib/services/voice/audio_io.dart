import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:record/record.dart';

/// Gemini Live speaks and listens in 16-bit mono PCM at 24 kHz.
const liveSampleRate = 24000;

abstract interface class MicInput {
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> start();

  /// Input loudness from 0 to 1, while recording.
  Stream<double> get levels;
  Future<void> stop();
}

abstract interface class AudioOutput {
  Future<void> init();
  void add(Uint8List pcm);

  /// Drops whatever is still queued (the user interrupted).
  Future<void> interrupt();
}

class RecordMicInput implements MicInput {
  AudioRecorder? _recorder;
  StreamSubscription<Amplitude>? _amp;
  final _levels = StreamController<double>.broadcast();

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Future<bool> hasPermission() => (_recorder ??= AudioRecorder()).hasPermission();

  @override
  Future<Stream<Uint8List>> start() async {
    await stop();
    final recorder = _recorder = AudioRecorder();
    final stream = await recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: liveSampleRate,
      numChannels: 1,
      echoCancel: true,
      noiseSuppress: true,
      autoGain: true,
      androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.voiceCommunication),
    ));
    _amp = recorder
        .onAmplitudeChanged(const Duration(milliseconds: 90))
        .listen((a) => _levels.add(((a.current + 50) / 50).clamp(0.0, 1.0)));
    return stream;
  }

  @override
  Future<void> stop() async {
    await _amp?.cancel();
    _amp = null;
    final recorder = _recorder;
    if (recorder != null && await recorder.isRecording()) await recorder.stop();
  }
}

class SoloudAudioOutput implements AudioOutput {
  AudioSource? _stream;
  SoundHandle? _handle;

  @override
  Future<void> init() async {
    if (!SoLoud.instance.isInitialized) {
      await SoLoud.instance.init(sampleRate: liveSampleRate, channels: Channels.mono);
    }
  }

  @override
  void add(Uint8List pcm) {
    if (!SoLoud.instance.isInitialized) return;
    final stream = _stream ??= _open();
    SoLoud.instance.addAudioDataStream(stream, pcm);
  }

  AudioSource _open() {
    final s = SoLoud.instance.setBufferStream(
      bufferingType: BufferingType.released,
      bufferingTimeNeeds: 0,
      sampleRate: liveSampleRate,
      channels: Channels.mono,
      format: BufferType.s16le,
    );
    _handle = SoLoud.instance.play(s);
    return s;
  }

  @override
  Future<void> interrupt() async {
    final stream = _stream;
    final handle = _handle;
    _stream = null;
    _handle = null;
    if (stream == null) return;
    try {
      SoLoud.instance.setDataIsEnded(stream);
      if (handle != null && SoLoud.instance.getIsValidVoiceHandle(handle)) {
        await SoLoud.instance.stop(handle);
      }
    } catch (e) {
      debugPrint('Audio interrupt failed: $e');
    }
  }
}

/// Rough loudness (0..1) of a 16-bit little-endian PCM chunk, for the orb.
double pcmLevel(Uint8List pcm) {
  if (pcm.length < 2) return 0;
  final data = ByteData.sublistView(pcm);
  var sum = 0.0;
  final n = pcm.length ~/ 2;
  for (var i = 0; i < n; i++) {
    final s = data.getInt16(i * 2, Endian.little) / 32768;
    sum += s * s;
  }
  return (math.sqrt(sum / n) * 4).clamp(0.0, 1.0);
}

/// Playback length of a PCM chunk.
Duration pcmDuration(Uint8List pcm) =>
    Duration(microseconds: pcm.length * 1000000 ~/ (liveSampleRate * 2));
