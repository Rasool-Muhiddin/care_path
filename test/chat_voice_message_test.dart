import 'package:axon/features/chat/data/chat_message_model.dart';
import 'package:axon/features/chat/presentation/voice_message_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json({required String kind, String text = '', String? audioUrl, int? duration}) => {
      'id': 7,
      'case': 1,
      'sender': 2,
      'sender_name': 'Patient',
      'sender_role': 'patient',
      'inquiry_type': 'medical',
      'kind': kind,
      'text': text,
      'audio_url': audioUrl,
      'duration_seconds': duration,
      'created_at': '2026-10-17T10:00:00Z',
      'is_read': false,
      'is_mine': true,
    };

void main() {
  test('voice message parses audio url and duration', () {
    final message = ChatMessageModel.fromJson(
      _json(kind: 'voice', audioUrl: '/api/chat/messages/7/audio/', duration: 42),
    );
    expect(message.isVoice, isTrue);
    expect(message.audioUrl, '/api/chat/messages/7/audio/');
    expect(message.durationSeconds, 42);
    expect(message.text, '');
  });

  test('text message is not voice', () {
    final message = ChatMessageModel.fromJson(_json(kind: 'text', text: 'hello'));
    expect(message.isVoice, isFalse);
    expect(message.audioUrl, isNull);
    expect(message.text, 'hello');
  });

  test('duration format and limit match the server', () {
    expect(formatVoiceDuration(const Duration(seconds: 5)), '0:05');
    expect(formatVoiceDuration(const Duration(seconds: 75)), '1:15');
    expect(voiceNoteMaxDuration, const Duration(seconds: 120));
  });
}
