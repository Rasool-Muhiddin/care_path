/// كل النصوص الثابتة لشاشة الإعدادات (سياسة الخصوصية، من نحن، التواصل،
/// إخلاء المسؤولية الطبية) في مكان واحد حتى يسهل استبدالها لاحقاً.
///
/// سياسة الخصوصية و"من نحن" وبيانات التواصل نصوص مؤقتة (PLACEHOLDER):
/// الجهة الناشرة للتطبيق لم تُعتمد بعد، والنصوص النهائية ستُرسَل لاحقاً.
class AppInfoTexts {
  AppInfoTexts._();

  static const appName = 'Axon';

  /// الرابط العام لسياسة الخصوصية (مطلوب في متجري Google Play وApp Store)،
  /// يقدّمه Django من accounts/templates/accounts/privacy_policy.html
  static const privacyPolicyUrl = 'https://axon.tera-software1.com/privacy/';

  static const developerName = 'Tera';
  static const developerUrl = 'https://tera-software1.com';

  // TODO(publisher): استبدل نص سياسة الخصوصية بالنص النهائي المعتمد من الجهة الناشرة.
  static const privacyPolicyAr = '''[نص مؤقت — PLACEHOLDER]

سياسة الخصوصية النهائية لتطبيق Axon قيد الإعداد، وسيُستبدل هذا النص بها قبل النشر.

بشكل عام:
• يجمع التطبيق فقط البيانات اللازمة لمتابعة العلاج: بيانات الحساب، الحالة المرضية، الجلسات، النوبات المسجّلة، والمحادثات بين المريض والطبيب وفريق المهندسين.
• لا تُباع البيانات ولا تُشارك مع جهات إعلانية.
• يمكنك حذف حسابك وبياناتك في أي وقت من الإعدادات ← حذف الحساب.

الجهة الناشرة: [يُحدَّد لاحقاً]''';

  // TODO(publisher): استبدل وصف التطبيق واسم الجهة الناشرة بالنص النهائي.
  static const aboutDescriptionAr = '''[نص مؤقت — PLACEHOLDER]

Axon تطبيق يربط المريض والطبيب وفريق المهندسين حول الأجهزة العلاجية: متابعة الجلسات، تسجيل النوبات، والتواصل حول الحالة.''';

  // TODO(publisher): اسم الجهة الناشرة غير معتمد بعد.
  static const publisherAr = '[الجهة الناشرة — يُحدَّد لاحقاً]';

  // TODO(publisher): استبدل بيانات التواصل والدعم ببيانات الجهة الناشرة الفعلية.
  static const contactAr = '''[نص مؤقت — PLACEHOLDER]

للدعم والاستفسارات:
• البريد الإلكتروني: [يُحدَّد لاحقاً]
• الهاتف / واتساب: [يُحدَّد لاحقاً]
• ساعات العمل: [يُحدَّد لاحقاً]

للأسئلة الطبية تواصل مع طبيبك المعالج مباشرة.''';

  static const medicalDisclaimerEn =
      'Axon is for treatment management and communication only. It is not a diagnostic tool '
      'and does not replace your doctor. Always follow your doctor\'s advice for any medical decision.';

  static const medicalDisclaimerAr =
      'تطبيق Axon مخصّص لإدارة العلاج والتواصل فقط، وليس أداة للتشخيص ولا يغني عن الطبيب. '
      'ارجع دائماً إلى طبيبك المعالج في أي قرار طبي.';
}
