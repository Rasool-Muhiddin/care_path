/// كل روابط الـ API — تطابق config/urls_main.py في الـ backend
/// عدّل [baseUrl] حسب بيئة التشغيل (محلي/سيرفر)
class ApiEndpoints {
  ApiEndpoints._();

  // TODO: غيّر هذا حسب مكان تشغيل الـ backend
  // مثال محلي (محاكي Android): http://10.0.2.2:8000
  // مثال محلي (iOS Simulator / Desktop): http://127.0.0.1:8000
  static const String baseUrl = 'http://127.0.0.1:8000';

  static const String api = '$baseUrl/api';

  // accounts
  static const String register = '$api/auth/register/';
  static const String login = '$api/auth/login/';
  static const String refresh = '$api/auth/refresh/';
  static const String me = '$api/auth/me/';
  static const String patients = '$api/patients/';
  static const String engineers = '$api/engineers/';

  // devices
  static const String clinics = '$api/clinics/';
  static const String deviceTypes = '$api/device-types/';
  static const String devices = '$api/devices/';

  // cases
  static const String cases = '$api/cases/';
  static const String caseProgressNotes = '$api/case-progress-notes/';
  static const String weeklyEpisodeLogs = '$api/weekly-episode-logs/';

  // treatments
  static const String sessions = '$api/sessions/';

  // feedback
  static const String feedback = '$api/feedback/';

    // chat
  static String caseMessages(int caseId) => '$api/chat/cases/$caseId/messages/';
  static const String chatUnreadCount = '$api/chat/unread-count/';
}