import 'dart:async';

import 'package:axon/core/network/api_client.dart';
import 'package:axon/features/chat/data/chat_message_model.dart';
import 'package:axon/features/chat/data/chat_repository.dart';
import 'package:axon/features/chat/data/voice_player.dart';
import 'package:axon/features/chat/presentation/voice_message_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// يسجّل ترتيب الاستدعاءات. "sync" = هل جاء قبل أول انتظار في toggle (أي
/// داخل لمسة المستخدم نفسها) — شرط Safari على iPhone للتشغيل.
class _FakePlayer implements VoicePlayer {
  final calls = <String>[];
  final _changes = StreamController<void>.broadcast();
  @override
  bool playing = false;
  @override
  bool completed = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration? duration;

  @override
  Stream<void> get changes => _changes.stream;
  @override
  void unlock() => calls.add('unlock');
  @override
  Future<void> setSource(String source) async => calls.add('source:$source');
  @override
  void play() {
    calls.add('play');
    playing = true;
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    playing = false;
  }

  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> dispose() => _changes.close();
}

ChatMessageModel _voice(int id) => ChatMessageModel.fromJson({
      'id': id,
      'case': 1,
      'sender': 2,
      'sender_name': 'Patient',
      'sender_role': 'patient',
      'inquiry_type': 'medical',
      'kind': 'voice',
      'text': '',
      'audio_url': '/api/chat/messages/$id/audio/',
      'duration_seconds': 5,
      'created_at': '2026-10-17T10:00:00Z',
      'is_read': false,
      'is_mine': false,
    });

void main() {
  late _FakePlayer player;
  late Completer<String> download;
  late VoicePlaybackController controller;

  setUp(() {
    player = _FakePlayer();
    download = Completer<String>();
    controller = VoicePlaybackController(
      ChatRepository(ApiClient(onSessionExpired: () {})),
      player: player,
      sourceFor: (_) => download.future,
    );
  });
  tearDown(() => controller.dispose());

  test('first tap unlocks the player synchronously, then plays after the download', () async {
    final tap = controller.toggle(_voice(7));
    // قبل أي انتظار: فتح العنصر داخل اللمسة نفسها، ولا تشغيل قبل التحميل
    expect(player.calls, ['unlock', 'stop']);
    expect(controller.loadingId, 7);

    download.complete('blob:voice-7');
    await tap;
    expect(player.calls, ['unlock', 'stop', 'source:blob:voice-7', 'play']);
    expect(controller.isPlaying(7), isTrue);
    expect(controller.loadingId, isNull);
  });

  test('tap on the current message pauses, and the next tap plays synchronously', () async {
    download.complete('blob:voice-7');
    await controller.toggle(_voice(7));

    await controller.toggle(_voice(7));
    expect(player.calls.last, 'pause');
    expect(controller.isPlaying(7), isFalse);

    // إن رفض iOS التشغيل الأول، هذه اللمسة تشغّل مباشرة (بلا انتظار قبلها)
    player.calls.clear();
    unawaited(controller.toggle(_voice(7)));
    expect(player.calls, ['unlock', 'play']);
  });

  test('switching messages during a download does not play the old one', () async {
    final downloads = {7: download, 8: Completer<String>()};
    controller.dispose();
    controller = VoicePlaybackController(
      ChatRepository(ApiClient(onSessionExpired: () {})),
      player: player = _FakePlayer(),
      sourceFor: (m) => downloads[m.id]!.future,
    );
    final a = controller.toggle(_voice(7));
    final b = controller.toggle(_voice(8));
    downloads[7]!.complete('blob:7');
    downloads[8]!.complete('blob:8');
    await Future.wait([a, b]);
    expect(player.calls.where((c) => c.startsWith('source')), ['source:blob:8']);
    expect(controller.isPlaying(8), isTrue);
  });
}
