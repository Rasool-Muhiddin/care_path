/// يطابق استجابة /api/app-version/latest/ من الـ backend
class AppVersionInfo {
  const AppVersionInfo({
    required this.platform,
    required this.versionName,
    required this.versionCode,
    required this.releaseNotes,
    required this.isMandatory,
    required this.downloadLink,
  });

  final String platform;
  final String versionName;
  final int versionCode;
  final String releaseNotes;
  final bool isMandatory;
  final String downloadLink;

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    return AppVersionInfo(
      platform: json['platform'] as String? ?? '',
      versionName: json['version_name'] as String? ?? '',
      versionCode: json['version_code'] as int? ?? 0,
      releaseNotes: json['release_notes'] as String? ?? '',
      isMandatory: json['is_mandatory'] as bool? ?? false,
      downloadLink: json['download_link'] as String? ?? '',
    );
  }
}
