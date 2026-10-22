import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'chat_repository.dart';
import 'voice_player.dart';

/// AAC أحادي بـ 64kbps في ملف m4a: دقيقتان ≈ 1MB.
Future<RecordConfig> voiceRecordConfig(AudioRecorder recorder) async =>
    const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, numChannels: 1);

/// ملف التسجيل في المجلد المؤقت
Future<String> newVoiceRecordingPath() async {
  final dir = await getTemporaryDirectory();
  return '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
}

/// [recording]: مسار الملف الذي أرجعه المسجّل
Future<MultipartFile> voiceUploadFile(String recording) => MultipartFile.fromFile(
      recording,
      filename: 'voice.m4a',
      contentType: DioMediaType('audio', 'mp4'),
    );

void deleteVoiceRecording(String recording) {
  final file = File(recording);
  file.exists().then((exists) {
    if (exists) file.delete().ignore();
  }).ignore();
}

/// ملفات الرسائل الصوتية المحمّلة من الخادم، في مجلد مؤقت خاص بالتطبيق.
/// مراسلات طبية: تُمسح عند تسجيل الخروج (AuthNotifier).
class VoiceCache {
  VoiceCache._();

  static Future<Directory> _dir() async =>
      Directory('${(await getTemporaryDirectory()).path}/voice_cache');

  /// مسار ملف الرسالة محلياً، يُحمَّل أولاً إن لم يكن موجوداً
  static Future<String> sourceFor(int messageId, String audioUrl, ChatRepository repo) async {
    final dir = await _dir();
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/$messageId.m4a');
    if (!await file.exists()) {
      final bytes = await repo.downloadVoice(audioUrl);
      // ملف مؤقت ثم إعادة تسمية: لا يبقى ملف ناقص في الـ cache إن انقطع التحميل
      final partial = File('${file.path}.part');
      await partial.writeAsBytes(bytes, flush: true);
      await partial.rename(file.path);
    }
    return file.path;
  }

  static Future<void> clear() async {
    try {
      final dir = await _dir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // تنظيف فقط؛ لا يمنع الخروج
    }
  }
}

VoicePlayer createVoicePlayer() => _JustAudioVoicePlayer();

class _JustAudioVoicePlayer implements VoicePlayer {
  _JustAudioVoicePlayer() {
    _subscriptions
      ..add(_player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          // انتهت الرسالة: ترجع للبداية متوقفة
          _player.pause();
          _player.seek(Duration.zero);
        }
        _changes.add(null);
      }))
      ..add(_player.positionStream.listen((_) => _changes.add(null)));
  }

  final _player = AudioPlayer();
  final _changes = StreamController<void>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];

  @override
  Stream<void> get changes => _changes.stream;
  @override
  bool get playing => _player.playing;
  @override
  bool get completed => _player.processingState == ProcessingState.completed;
  @override
  Duration get position => _player.position;
  @override
  Duration? get duration => _player.duration;

  @override
  void unlock() {}

  @override
  Future<void> setSource(String source) => _player.setFilePath(source);

  // play() لا يكتمل إلا عند التوقف، فلا ننتظره
  @override
  void play() => unawaited(_player.play());
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    await _changes.close();
    await _player.dispose();
  }
}
