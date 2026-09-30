/// عدّل [baseUrl]  
class ApiEndpoints {
  ApiEndpoints._();

  static const String baseUrl = 'https://axon.tera-software1.com';
  static const String api = '$baseUrl/api';

  // accounts
  static const String register = '$api/auth/register/';
  static const String login = '$api/auth/login/';
  static const String refresh = '$api/auth/refresh/';
  static const String me = '$api/auth/me/';
  static const String patients = '$api/patients/';
  static const String doctors = '$api/doctors/';
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

  // app updates
  static const String appVersionLatest = '$api/app-version/latest/';

  // notifications
  static const String fcmToken = '$api/fcm-token/';

    // chat
  static String caseMessages(int caseId) => '$api/chat/cases/$caseId/messages/';
  static const String chatUnreadCount = '$api/chat/unread-count/';
}