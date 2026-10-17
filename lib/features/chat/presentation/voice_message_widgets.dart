import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/widgets/glass_container.dart';
import '../data/chat_message_model.dart';
import '../data/chat_repository.dart';
import '../data/voice_cache.dart';

/// أقصى مدة للرسالة الصوتية — تطابق VOICE_NOTE_MAX_SECONDS في الخادم.
const voiceNoteMaxDuration = Duration(minutes: 2);

/// أقصر تسجيل يُرسل؛ الأقصر منه غالباً ضغطة بالخطأ.
const _voiceNoteMinDuration = Duration(seconds: 1);

String formatVoiceDuration(Duration d) {
  final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '${d.inMinutes}:$seconds';
}

enum VoiceRecorderStatus { idle, recording, recorded }

enum VoiceStartResult { started, permissionDenied, failed }

/// تسجيل رسالة صوتية بالضغط للبدء/الإيقاف (أوثق من الضغط المطوّل مع
/// التمرير ولوحة المفاتيح). AAC أحادي بـ 64kbps في ملف m4a: دقيقتان ≈ 1MB.
/// يتوقف تلقائياً عند [voiceNoteMaxDuration] ويبقى الملف جاهزاً للإرسال.
class VoiceRecorderController extends ChangeNotifier {
  final _recorder = AudioRecorder();
  final _stopwatch = Stopwatch();
  Timer? _ticker;
  VoiceRecorderStatus _status = VoiceRecorderStatus.idle;
  String? _path;
  bool _starting = false;
  Future<void>? _stopping;
  bool _disposed = false;

  VoiceRecorderStatus get status => _status;
  bool get isActive => _status != VoiceRecorderStatus.idle;
  bool get isRecording => _status == VoiceRecorderStatus.recording;
  bool get reachedLimit => _stopwatch.elapsed >= voiceNoteMaxDuration;
  bool get isTooShort => _stopwatch.elapsed < _voiceNoteMinDuration;
  String? get path => _path;
  Duration get elapsed => reachedLimit ? voiceNoteMaxDuration : _stopwatch.elapsed;

  Future<VoiceStartResult> start() async {
    if (_status != VoiceRecorderStatus.idle || _starting) return VoiceStartResult.failed;
    _starting = true;
    try {
      // أول تسجيل: نظام التشغيل يطلب إذن الميكروفون هنا (لا عند فتح التطبيق)
      if (!await _recorder.hasPermission()) return VoiceStartResult.permissionDenied;
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, numChannels: 1),
        path: path,
      );
      if (_disposed) {
        await _recorder.cancel();
        return VoiceStartResult.failed;
      }
      _path = path;
      _stopwatch
        ..reset()
        ..start();
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (reachedLimit) {
          stop();
        } else if (!_disposed) {
          notifyListeners();
        }
      });
      _status = VoiceRecorderStatus.recording;
      notifyListeners();
      return VoiceStartResult.started;
    } catch (_) {
      return VoiceStartResult.failed;
    } finally {
      _starting = false;
    }
  }

  /// يوقف التسجيل ويبقي الملف للإرسال (من زر الإرسال أو عند بلوغ الحد).
  Future<void> stop() {
    if (_status != VoiceRecorderStatus.recording) return Future.value();
    return _stopping ??= _doStop().whenComplete(() => _stopping = null);
  }

  Future<void> _doStop() async {
    _ticker?.cancel();
    _stopwatch.stop();
    try {
      _path = await _recorder.stop() ?? _path;
    } catch (_) {
      // يبقى المسار الأصلي؛ إن كان الملف تالفاً يرفضه الخادم برسالة واضحة
    }
    _status = VoiceRecorderStatus.recorded;
    if (!_disposed) notifyListeners();
  }

  /// يلغي التسجيل (أو يتخلص منه بعد نجاح إرساله) ويحذف الملف المحلي.
  Future<void> discard() async {
    await _stopping;
    _ticker?.cancel();
    _stopwatch
      ..stop()
      ..reset();
    if (_status == VoiceRecorderStatus.recording) {
      try {
        await _recorder.cancel();
      } catch (_) {}
    }
    _deleteFile(_path);
    _path = null;
    _status = VoiceRecorderStatus.idle;
    if (!_disposed) notifyListeners();
  }

  static void _deleteFile(String? path) {
    if (path == null) return;
    final file = File(path);
    file.exists().then((exists) {
      if (exists) file.delete().ignore();
    }).ignore();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    if (_status == VoiceRecorderStatus.recording) _recorder.cancel().ignore();
    _deleteFile(_path);
    _recorder.dispose().ignore();
    super.dispose();
  }
}

/// مشغّل واحد لكل شاشة المحادثة: تشغيل رسالة يوقف أي رسالة أخرى.
/// الملف يُحمَّل عبر endpoint مصادَق (ChatRepository.downloadVoice) ويُحفظ
/// في VoiceCache، ثم يُشغَّل محلياً.
class VoicePlaybackController extends ChangeNotifier {
  VoicePlaybackController(this._repo) {
    _subscriptions
      ..add(_player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          // انتهت الرسالة: ترجع للبداية متوقفة
          _player.pause();
          _player.seek(Duration.zero);
        }
        _notify();
      }))
      ..add(_player.positionStream.listen((_) => _notify()));
  }

  final ChatRepository _repo;
  final _player = AudioPlayer();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  int? _currentId;
  int? _loadingId;
  bool _disposed = false;

  int? get loadingId => _loadingId;
  bool isCurrent(int messageId) => _currentId == messageId;
  bool isPlaying(int messageId) =>
      _currentId == messageId &&
      _player.playing &&
      _player.processingState != ProcessingState.completed;
  Duration positionOf(int messageId) => _currentId == messageId ? _player.position : Duration.zero;
  Duration? durationOf(int messageId) => _currentId == messageId ? _player.duration : null;

  /// تشغيل/إيقاف مؤقت. يرمي الاستثناء عند فشل التحميل أو التشغيل.
  Future<void> toggle(ChatMessageModel message) async {
    if (_currentId == message.id) {
      // play() لا يكتمل إلا عند التوقف، فلا ننتظره
      _player.playing ? await _player.pause() : unawaited(_player.play());
      return;
    }
    _loadingId = message.id;
    _notify();
    try {
      await _player.stop();
      _currentId = null;
      final file = await VoiceCache.fileFor(message.id);
      if (!await file.exists()) await _repo.downloadVoice(message.audioUrl!, file.path);
      // ضغط المستخدم رسالة أخرى أثناء التحميل، أو أُغلقت الشاشة
      if (_loadingId != message.id || _disposed) return;
      await _player.setFilePath(file.path);
      _currentId = message.id;
      unawaited(_player.play());
    } finally {
      if (_loadingId == message.id) _loadingId = null;
      _notify();
    }
  }

  Future<void> seek(int messageId, Duration position) async {
    if (_currentId == messageId) await _player.seek(position);
  }

  Future<void> stopAll() async {
    _loadingId = null;
    _currentId = null;
    await _player.stop();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}

/// محتوى فقاعة الرسالة الصوتية: تشغيل/إيقاف، شريط التقدّم، والمدة.
class VoiceMessageContent extends StatelessWidget {
  const VoiceMessageContent({
    super.key,
    required this.message,
    required this.playback,
    required this.onError,
  });

  final ChatMessageModel message;
  final VoicePlaybackController playback;
  final ValueChanged<Object> onError;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        final id = message.id;
        final isLoading = playback.loadingId == id;
        final isPlaying = playback.isPlaying(id);
        final total = playback.durationOf(id) ?? Duration(seconds: message.durationSeconds ?? 0);
        final position = playback.positionOf(id);
        final progress = total.inMilliseconds == 0
            ? 0.0
            : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                        color: Colors.white,
                        size: 34,
                      ),
                      onPressed: () => playback.toggle(message).catchError(onError),
                    ),
            ),
            SizedBox(
              width: 150,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: SliderComponentShape.noOverlay,
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white30,
                      thumbColor: Colors.white,
                      disabledActiveTrackColor: Colors.white,
                      disabledInactiveTrackColor: Colors.white30,
                      disabledThumbColor: Colors.white70,
                    ),
                    child: Slider(
                      value: progress,
                      onChanged: playback.isCurrent(id) ? (v) => playback.seek(id, total * v) : null,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      position > Duration.zero
                          ? '${formatVoiceDuration(position)} / ${formatVoiceDuration(total)}'
                          : formatVoiceDuration(total),
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// يحل محل حقل الكتابة أثناء التسجيل وبعده: المؤقّت، الإلغاء، والإرسال.
class VoiceRecordingBar extends StatelessWidget {
  const VoiceRecordingBar({
    super.key,
    required this.recorder,
    required this.isStaff,
    required this.isSending,
    required this.onCancel,
    required this.onSend,
  });

  final VoiceRecorderController recorder;
  final bool isStaff;
  final bool isSending;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final String label;
    if (recorder.isRecording) {
      label = isStaff ? 'Recording…' : 'جارٍ التسجيل…';
    } else if (recorder.reachedLimit) {
      label = isStaff ? 'Maximum length reached' : 'وصلت للحد الأقصى';
    } else {
      label = isStaff ? 'Ready to send' : 'جاهز للإرسال';
    }

    return GlassContainer(
      borderRadius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white),
            tooltip: isStaff ? 'Cancel' : 'إلغاء',
            onPressed: isSending ? null : onCancel,
          ),
          Icon(
            recorder.isRecording ? Icons.fiber_manual_record : Icons.mic_none,
            color: recorder.isRecording ? Colors.redAccent : Colors.white70,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            '${formatVoiceDuration(recorder.elapsed)} / ${formatVoiceDuration(voiceNoteMaxDuration)}',
            style: const TextStyle(color: Colors.white, fontSize: 14, fontFeatures: [FontFeature.tabularFigures()]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          isSending
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  tooltip: isStaff ? 'Send' : 'إرسال',
                  onPressed: onSend,
                ),
        ],
      ),
    );
  }
}
