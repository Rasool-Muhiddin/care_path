/// مشغّل الرسائل الصوتية كما يحتاجه VoicePlaybackController. له تنفيذان
/// (voice_platform.dart): just_audio بملفات محلية على أندرويد/iOS، وعنصر
/// <audio> مباشرة على الويب حتى يُفتح بلمسة المستخدم نفسها (قيد Safari).
abstract class VoicePlayer {
  /// أي تغيّر في التشغيل أو الموضع أو المدة
  Stream<void> get changes;

  bool get playing;

  /// وصل التشغيل لنهاية الملف (قبل أن يُعاد للبداية)
  bool get completed;

  Duration get position;
  Duration? get duration;

  /// يُستدعى متزامناً داخل لمسة المستخدم وقبل أي انتظار. على iOS (Safari)
  /// لا يُسمح بالتشغيل من خارج اللمسة إلا لعنصر صوت شُغّل منها مرة.
  /// لا شيء على أندرويد/iOS الأصلي.
  void unlock();

  /// مصدر من VoiceCache.sourceFor: مسار ملف (أصلي) أو blob URL (ويب)
  Future<void> setSource(String source);

  /// لا ينتظر انتهاء التشغيل
  void play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> dispose();
}
