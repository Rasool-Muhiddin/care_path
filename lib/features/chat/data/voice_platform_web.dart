import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:record/record.dart';
import 'package:web/web.dart' as web;

import 'chat_repository.dart';
import 'voice_player.dart';

/// Safari (iPhone) يسجّل AAC داخل MP4؛ متصفحات بلا AAC (بعض نسخ Chrome)
/// تسجّل Opus داخل WebM. الخادم يحوّل الاثنين إلى AAC m4a موحّد.
Future<RecordConfig> voiceRecordConfig(AudioRecorder recorder) async {
  final aac = await recorder.isEncoderSupported(AudioEncoder.aacLc);
  return RecordConfig(
    encoder: aac ? AudioEncoder.aacLc : AudioEncoder.opus,
    bitRate: 64000,
    numChannels: 1,
  );
}

/// المسجّل على الويب يتجاهل المسار ويرجع blob URL عند الإيقاف
Future<String> newVoiceRecordingPath() async => 'voice';

/// [recording]: الـ blob URL الذي أرجعه المسجّل. الاسم والنوع حسب ما سجّله
/// المتصفح فعلاً (الخادم يتحقق من محتوى الملف نفسه على أي حال).
Future<MultipartFile> voiceUploadFile(String recording) async {
  final response = await web.window.fetch(recording.toJS).toDart;
  final blob = await response.blob().toDart;
  final bytes = (await blob.arrayBuffer().toDart).toDart.asUint8List();
  final webm = blob.type.contains('webm');
  return MultipartFile.fromBytes(
    bytes,
    filename: webm ? 'voice.webm' : 'voice.m4a',
    contentType: DioMediaType('audio', webm ? 'webm' : 'mp4'),
  );
}

void deleteVoiceRecording(String recording) {
  if (recording.startsWith('blob:')) web.URL.revokeObjectURL(recording);
}

/// الرسائل الصوتية المحمّلة: blob URLs بالذاكرة فقط (لا قرص ولا Cache
/// Storage — مراسلات طبية). تُلغى كلها عند تسجيل الخروج (AuthNotifier).
class VoiceCache {
  VoiceCache._();

  static final _urls = <int, String>{};

  static Future<String> sourceFor(int messageId, String audioUrl, ChatRepository repo) async {
    final cached = _urls[messageId];
    if (cached != null) return cached;
    final bytes = Uint8List.fromList(await repo.downloadVoice(audioUrl));
    final blob = web.Blob(<JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: 'audio/mp4'));
    return _urls[messageId] = web.URL.createObjectURL(blob);
  }

  static Future<void> clear() async {
    for (final url in _urls.values) {
      web.URL.revokeObjectURL(url);
    }
    _urls.clear();
  }
}

VoicePlayer createVoicePlayer() => _HtmlVoicePlayer();

/// ملف WAV صامت قصير جداً (10ms): يُشغَّل مرة داخل أول لمسة لفتح العنصر.
const _silence = 'data:audio/wav;base64,'
    'UklGRsQAAABXQVZFZm10IBAAAAABAAEAQB8AAIA+AAACABAAZGF0YaAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

/// عنصر <audio> واحد لكل شاشة محادثة. just_audio على الويب لا يسمح بفتح
/// العنصر داخل اللمسة، و iOS يمنع play() بعد انتظار التحميل (اللمسة "انتهت").
/// الحل: [unlock] يشغّل صمتاً متزامناً داخل أول لمسة، فيصير العنصر مسموحاً
/// له بالتشغيل لاحقاً بعد اكتمال التحميل.
class _HtmlVoicePlayer implements VoicePlayer {
  _HtmlVoicePlayer() {
    for (final type in const ['play', 'pause', 'timeupdate', 'durationchange', 'loadedmetadata', 'seeked']) {
      _listen(type, () => _emit());
    }
    _listen('ended', () {
      // انتهت الرسالة: ترجع للبداية متوقفة
      _audio.currentTime = 0;
      _emit();
    });
  }

  final _audio = web.HTMLAudioElement()..preload = 'auto';
  final _changes = StreamController<void>.broadcast();
  final _listeners = <(String, JSFunction)>[];
  bool _unlocked = false;

  void _listen(String type, void Function() handler) {
    final listener = ((web.Event _) => handler()).toJS;
    _listeners.add((type, listener));
    _audio.addEventListener(type, listener);
  }

  @override
  Stream<void> get changes => _changes.stream;
  @override
  bool get playing => !_audio.paused;
  @override
  bool get completed => _audio.ended;
  @override
  Duration get position => Duration(milliseconds: (_audio.currentTime * 1000).round());
  @override
  Duration? get duration {
    final seconds = _audio.duration;
    return seconds.isFinite && seconds > 0 ? Duration(milliseconds: (seconds * 1000).round()) : null;
  }

  @override
  void unlock() {
    if (_unlocked) return;
    _unlocked = true;
    _audio.src = _silence;
    _ignore(_audio.play());
  }

  @override
  Future<void> setSource(String source) async {
    _audio.src = source;
  }

  /// إن رفض المتصفح (NotAllowedError) يبقى الزر "تشغيل"، واللمسة التالية —
  /// وهي داخل لمسة فعلاً — تشغّله.
  @override
  void play() => _ignore(_audio.play());

  @override
  Future<void> pause() async => _audio.pause();

  @override
  Future<void> seek(Duration position) async {
    _audio.currentTime = position.inMilliseconds / 1000;
  }

  @override
  Future<void> stop() async {
    _audio.pause();
    try {
      _audio.currentTime = 0;
    } catch (_) {
      // بلا مصدر بعد
    }
  }

  @override
  Future<void> dispose() async {
    _audio.pause();
    for (final (type, listener) in _listeners) {
      _audio.removeEventListener(type, listener);
    }
    _audio.removeAttribute('src');
    await _changes.close();
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void _ignore(JSPromise<JSAny?> promise) {
    promise.toDart.then((_) {}, onError: (Object _) => _emit());
  }
}
