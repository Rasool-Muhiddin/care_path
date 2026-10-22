import 'dart:async';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../../../core/widgets/glass_container.dart';
import '../data/chat_message_model.dart';
import '../data/chat_repository.dart';
import '../data/voice_platform.dart';
import '../data/voice_player.dart';

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
/// التمرير ولوحة المفاتيح). الصيغة والملف حسب المنصة (voice_platform):
/// AAC m4a على أندرويد/iOS، و blob بالذاكرة على الويب.
/// يتوقف تلقائياً عند [voiceNoteMaxDuration] ويبقى الملف جاهزاً للإرسال.
class VoiceRecorderController extends ChangeNotifier {
  // يُنشأ عند أول تسجيل فقط: AudioRecorder يحجز مسجّلاً في المنصة فور إنشائه،
  // ومعظم من يفتح المحادثة لا يسجّل.
  AudioRecorder? _recorderInstance;
  AudioRecorder get _recorder => _recorderInstance ??= AudioRecorder();
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
      final path = await newVoiceRecordingPath();
      await _recorder.start(await voiceRecordConfig(_recorder), path: path);
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

  /// يوقف التسجيل ويبقي الملف للإرسال (على الويب: [path] يصبح blob URL) (من زر الإرسال أو عند بلوغ الحد).
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
    if (path != null) deleteVoiceRecording(path);
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    final recorder = _recorderInstance;
    if (recorder != null) {
      if (_status == VoiceRecorderStatus.recording) recorder.cancel().ignore();
      recorder.dispose().ignore();
    }
    _deleteFile(_path);
    super.dispose();
  }
}

/// مشغّل واحد لكل شاشة المحادثة: تشغيل رسالة يوقف أي رسالة أخرى.
/// الملف يُحمَّل عبر endpoint مصادَق (ChatRepository.downloadVoice) ويُحفظ
/// في VoiceCache (ملف أو blob حسب المنصة)، ثم يُشغَّل محلياً.
class VoicePlaybackController extends ChangeNotifier {
  VoicePlaybackController(
    ChatRepository repo, {
    @visibleForTesting VoicePlayer? player,
    @visibleForTesting Future<String> Function(ChatMessageModel message)? sourceFor,
  })  : _player = player ?? createVoicePlayer(),
        _sourceFor = sourceFor ?? ((m) => VoiceCache.sourceFor(m.id, m.audioUrl!, repo)) {
    _subscription = _player.changes.listen((_) => _notify());
  }

  final VoicePlayer _player;
  final Future<String> Function(ChatMessageModel message) _sourceFor;
  late final StreamSubscription<void> _subscription;
  int? _currentId;
  int? _loadingId;
  bool _disposed = false;

  int? get loadingId => _loadingId;
  bool isCurrent(int messageId) => _currentId == messageId;
  bool isPlaying(int messageId) => _currentId == messageId && _player.playing && !_player.completed;
  Duration positionOf(int messageId) => _currentId == messageId ? _player.position : Duration.zero;
  Duration? durationOf(int messageId) => _currentId == messageId ? _player.duration : null;

  /// تشغيل/إيقاف مؤقت. يرمي الاستثناء عند فشل التحميل أو التشغيل.
  ///
  /// يُستدعى من لمسة المستخدم: ما قبل أول await يجري داخل اللمسة نفسها، وهذا
  /// ما يحتاجه Safari على iPhone ليسمح بالتشغيل (unlock و play المتزامنان).
  Future<void> toggle(ChatMessageModel message) async {
    _player.unlock();
    if (_currentId == message.id) {
      _player.playing ? await _player.pause() : _player.play();
      return;
    }
    _loadingId = message.id;
    _notify();
    try {
      await _player.stop();
      _currentId = null;
      final source = await _sourceFor(message);
      // ضغط المستخدم رسالة أخرى أثناء التحميل، أو أُغلقت الشاشة
      if (_loadingId != message.id || _disposed) return;
      await _player.setSource(source);
      _currentId = message.id;
      _player.play();
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
    _subscription.cancel();
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
