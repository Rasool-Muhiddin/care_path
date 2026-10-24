/// قسم واحد من سياسة الخصوصية: عنوان ونص (الأسطر التي تبدأ بـ • نقاط).
class PolicySection {
  const PolicySection(this.title, this.body);
  final String title;
  final String body;
}

/// كل النصوص الثابتة لشاشة الإعدادات (سياسة الخصوصية، من نحن، التواصل،
/// إخلاء المسؤولية الطبية) في مكان واحد حتى يسهل استبدالها لاحقاً.
///
/// "من نحن" وبيانات التواصل نصوص مؤقتة (PLACEHOLDER): الجهة الناشرة للتطبيق
/// لم تُعتمد بعد. سياسة الخصوصية نهائية ولا تذكر اسم أي جهة ناشرة أو مطوّرة
/// عمداً — نفس النص في accounts/templates/accounts/privacy_policy.html.
class AppInfoTexts {
  AppInfoTexts._();

  static const appName = 'Axon';

  /// الرابط العام لسياسة الخصوصية (مطلوب في متجري Google Play وApp Store)،
  /// يقدّمه Django من accounts/templates/accounts/privacy_policy.html
  static const privacyPolicyUrl = 'https://axon.tera-software1.com/privacy/';

  static const developerName = 'Tera';
  static const developerUrl = 'https://tera-software1.com';

  /// غيّره مع أي تعديل على نص السياسة (هنا وفي صفحة الويب)
  static const privacyLastUpdatedAr = 'آخر تحديث: 24 تشرين الأول 2026';
  static const privacyLastUpdatedEn = 'Last updated: 24 October 2026';

  static const privacyIntroAr =
      'توضّح هذه السياسة ما هي البيانات التي يجمعها تطبيق Axon، ولماذا، ومن يستطيع رؤيتها، '
      'وكيف تُحمى، وكيف يمكنك حذفها. باستخدامك التطبيق فإنك توافق على ما ورد فيها.';

  static const privacyPolicyAr = [
    PolicySection('1. البيانات التي نجمعها', '''• بيانات الحساب: الاسم الكامل، اسم المستخدم، رقم الهاتف، نوع الحساب (مريض، طبيب، مهندس)، والتخصص للأطباء. كلمة المرور تُحفظ مشفّرة (hash) ولا يمكن لأحد قراءتها.
• البيانات الصحية: الحالة المرضية (مثل الصرع أو الشقيقة ونوعها)، عدد النوبات الشهري ومدتها قبل العلاج، الأعراض، الأدوية الحالية، التقييم الأولي وخطة العلاج، إعدادات الجهاز العلاجي، الجلسات العلاجية، وسجلات النوبات (الوقت، المدة، الشدة، وهل أُخذ دواء) وتأكيداتك بعدم وجود نوبات غير مسجّلة.
• المحادثات: الرسائل النصية والصوتية بينك وبين طبيبك والفريق الفني. لا يُستخدم الميكروفون إلا أثناء تسجيلك رسالة صوتية بنفسك.
• بيانات الجهاز: رمز الإشعارات الخاص بجهازك ونوع المنصّة (أندرويد، iPhone، متصفح)، ورقم إصدار التطبيق لفحص التحديثات، إضافةً إلى سجلات تقنية عادية لدى الخادم (مثل عنوان IP ووقت الطلب) لأغراض الأمان وحل المشكلات.
• لا نجمع موقعك الجغرافي، ولا جهات الاتصال، ولا الصور، ولا معرّفات إعلانية، ولا نستخدم أدوات تتبّع أو تحليلات إعلانية.'''),
    PolicySection('2. لماذا نجمعها وكيف نستخدمها', '''• لمتابعة علاجك: عرض الجلسات والنوبات ومقارنتها بالوضع قبل العلاج ليتمكن طبيبك من تقييم التقدّم.
• للتواصل: إيصال الرسائل بينك وبين طبيبك والفريق الفني، وإرسال إشعار عند وصول رسالة جديدة أو للتذكير بتسجيل النوبات.
• لتشغيل الجهاز العلاجي ودعمه فنياً.
• لحماية حسابك والخدمة ومنع إساءة الاستخدام.
لا نستخدم بياناتك لأي غرض آخر.'''),
    PolicySection('3. من يستطيع رؤية بياناتك', '''• أنت (المريض): ترى بيانات حالتك وجلساتك ونوباتك ومحادثاتك.
• طبيبك المعالج المرتبط بحالتك: يرى بيانات الحالة والجلسات والنوبات ومحادثات الحالة.
• فريق الدعم الفني: يرى ما يلزم لإعداد الجهاز العلاجي ومتابعته والرد على استفساراتك، وبالقدر اللازم لذلك فقط.
• مزوّدو الخدمة التقنية: نعتمد على خدمة استضافة لتشغيل الخادم، وعلى خدمة Firebase Cloud Messaging لإيصال الإشعارات. نص الإشعار عام (مثل "لديك رسالة جديدة") ولا يحتوي على أي معلومة طبية.
• لا يرى المرضى الآخرون بياناتك إطلاقاً. وقد نكشف البيانات فقط إذا ألزمنا القانون بذلك.'''),
    PolicySection('4. كيف تُخزَّن بياناتك وتُحمى', '''• تُحفظ البيانات على خادم مؤمَّن، وكل الاتصال بين التطبيق والخادم مشفّر (HTTPS).
• الوصول إلى البيانات محدود حسب نوع الحساب: كل مستخدم يرى فقط ما يخصّه.
• رموز تسجيل الدخول تُحفظ في التخزين الآمن لجهازك، وفي نسخة الويب تُحفظ في كوكي محمي لا تستطيع الصفحة قراءته.
• الرسائل الصوتية التي تُحمَّل على جهازك تُحذف منه عند تسجيل الخروج.
• تُؤخذ نسخة احتياطية يومية من قاعدة البيانات لحمايتها من الفقدان.'''),
    PolicySection('5. مدة الاحتفاظ وحذف الحساب', '''• نحتفظ ببياناتك طوال فترة وجود حسابك.
• يمكنك حذف حسابك وبياناتك في أي وقت من داخل التطبيق: الإعدادات ← حذف الحساب.
• عند حذف حساب المريض تُحذف نهائياً كل بياناته: الحساب، الحالة، الجلسات، النوبات، التأكيدات، والرسائل التي أرسلها، وتُلغى جلسات الدخول ورموز الإشعارات.
• عند حذف حساب طبيب أو مهندس يُحذف الحساب، وتبقى سجلات الحالات الطبية ورسائل المحادثة الخاصة بالمرضى (دون اسم صاحب الحساب المحذوف) لأنها جزء من ملفاتهم العلاجية.
• تبقى نسخ من البيانات المحذوفة في النسخ الاحتياطية مدة أقصاها 14 يوماً، ثم تُحذف تلقائياً.
• يمكنك أيضاً طلب حذف حسابك أو الاطلاع على بياناتك أو تصحيحها عبر صفحة "التواصل والدعم" في التطبيق أو بسؤال طبيبك المعالج.'''),
    PolicySection('6. لا بيع ولا إعلانات', '''لا نبيع بياناتك، ولا نؤجّرها، ولا نشاركها مع أي جهة لأغراض إعلانية أو تسويقية، ولا يعرض التطبيق إعلانات.'''),
    PolicySection('7. التعديلات على هذه السياسة', '''قد نحدّث هذه السياسة عند تغيّر التطبيق أو المتطلبات القانونية. يُعرض تاريخ آخر تحديث في أعلى الصفحة، وعند وجود تغيير جوهري سنُعلمك داخل التطبيق. استمرارك في استخدام التطبيق بعد التحديث يعني موافقتك على السياسة المحدَّثة.'''),
  ];

  static const privacyIntroEn =
      'This policy explains what data the Axon app collects, why, who can see it, how it is '
      'protected and how you can delete it. By using the app you agree to this policy.';

  static const privacyPolicyEn = [
    PolicySection('1. Data we collect', '''• Account data: full name, username, phone number, account type (patient, doctor, engineer) and, for doctors, specialty. Passwords are stored hashed and cannot be read by anyone.
• Health data: the medical case (e.g. epilepsy or migraine and its type), the monthly number and duration of attacks before treatment, symptoms, current medications, initial evaluation and treatment plan, treatment device settings, treatment sessions, and attack records (time, duration, severity, whether medication was taken) together with the patient's confirmations that no attacks went unlogged.
• Chat: text and voice messages between the patient, the doctor and the technical team. The microphone is used only while you record a voice message yourself.
• Device data: your device's notification token and platform (Android, iPhone, browser), the app version for update checks, and standard server logs (such as IP address and request time) for security and troubleshooting.
• We do not collect your location, contacts, photos or advertising identifiers, and we use no advertising trackers or analytics.'''),
    PolicySection('2. Why we collect it and how we use it', '''• To manage treatment: showing sessions and attacks and comparing them with the situation before treatment so the doctor can assess progress.
• To communicate: delivering messages between the patient, the doctor and the technical team, and sending a notification for a new message or a reminder to log attacks.
• To set up and support the treatment device.
• To protect accounts and the service and prevent misuse.
Your data is not used for any other purpose.'''),
    PolicySection('3. Who can see your data', '''• The patient sees their own case, sessions, attacks and chats.
• The treating doctor linked to the case sees the case data, sessions, attacks and case chats.
• The technical support team sees what is needed to set up and maintain the treatment device and answer questions, and only to that extent.
• Technical service providers: a hosting service runs the server, and Firebase Cloud Messaging delivers notifications. Notification text is generic (e.g. "You have a new message") and contains no medical information.
• Other patients never see your data. Data is disclosed only when required by law.'''),
    PolicySection('4. How data is stored and protected', '''• Data is kept on a secured server, and all traffic between the app and the server is encrypted (HTTPS).
• Access is limited by account type: each user sees only what concerns them.
• Sign-in tokens are kept in the device's secure storage; in the web version they are kept in a protected cookie the page cannot read.
• Voice messages downloaded to the device are deleted from it on log out.
• The database is backed up daily to protect it from loss.'''),
    PolicySection('5. Data retention and account deletion', '''• Data is kept for as long as the account exists.
• You can delete your account at any time in the app: Settings → Delete account.
• Deleting a patient account permanently deletes all of that patient's data: the account, case, sessions, attacks, confirmations and the messages they sent, and signs out all sessions and removes notification tokens.
• Deleting a doctor or engineer account deletes the account; patients' medical case records and case chats remain (without the deleted user's name) because they are part of the patients' treatment files.
• Copies of deleted data remain in backups for at most 14 days and are then deleted automatically.
• You can also request deletion of your account, or access to or correction of your data, through "Contact & support" in the app.'''),
    PolicySection('6. No selling, no advertising', '''We do not sell or rent your data or share it with anyone for advertising or marketing, and the app shows no ads.'''),
    PolicySection('7. Changes to this policy', '''We may update this policy when the app or legal requirements change. The date of the last update is shown at the top of this page, and we will tell you in the app about any significant change. Continuing to use the app after an update means you accept the updated policy.'''),
  ];

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
