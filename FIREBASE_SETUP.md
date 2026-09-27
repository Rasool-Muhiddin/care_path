# إعداد Firebase (خطوات يدوية فقط — لا تعديل كود مطلوب)

كل الكود جاهز ولا يحتاج أي تعديل. تبقّى فقط وضع ملفين واثنين من الإعدادات
بعد أن تُنشئ مشروع Firebase الخاص بك.

## 1. قبل إنشاء مشروع Firebase

اختر الآن اسم حزمة (Application ID) نهائي بدل القيمة المؤقتة
`com.example.axon` الموجودة حالياً في:

```
android/app/build.gradle.kts   →  applicationId = "com.example.axon"
```

غيّرها لشيء مثل `com.yourcompany.carepath`، لأن Firebase يربط المشروع
بهذا الاسم تحديداً — تغييره لاحقاً يعني تسجيل تطبيق Firebase جديد من
الصفر.

## 2. ملف Android: `google-services.json`

من Firebase Console → إعدادات المشروع → أضف تطبيق Android → أدخل نفس
الـ applicationId أعلاه → حمّل الملف وضعه هنا حرفياً:

```
android/app/google-services.json
```

هذا كل ما يلزم من جهة Gradle — البلجن مُفعّل مسبقاً في
`android/settings.gradle.kts` و `android/app/build.gradle.kts`.

## 3. ملف السيرفر: مفتاح Service Account

من Firebase Console → إعدادات المشروع → Service Accounts → Generate new
private key. يُنزَّل ملف JSON **سرّي جداً** — لا يُرفع لأي مستودع Git.

ضعه في أي مكان آمن على السيرفر خارج مجلد المشروع المتتبَّع بـ git، مثلاً:

```
/etc/care_path/firebase-service-account.json
```

ثم اضبط متغيّر البيئة قبل تشغيل الخادم:

```bash
export FIREBASE_CREDENTIALS_PATH=/etc/care_path/firebase-service-account.json
```

(أو أضفه في ملف `.env`/إعدادات الخدمة حسب طريقة تشغيلكم على Hetzner).
طالما هذا المتغيّر غير مضبوط، الإشعارات تُعطَّل بصمت فقط — بقية
التطبيق (بما فيه إرسال الرسائل نفسها) يعمل بشكل طبيعي.

## 4. تثبيت الاعتماديات

```bash
# Backend
pip install -r requirements.txt
python manage.py migrate

# Flutter
flutter pub get
```

## 5. (لاحقاً، اختياري) دعم آيفون

نفس مشروع Firebase يدعم آيفون أيضاً — يتطلب فقط:
- تسجيل تطبيق iOS داخل نفس مشروع Firebase (يعطيك `GoogleService-Info.plist`
  توضعه في `ios/Runner/`)
- رفع مفتاح APNs (.p8) من Apple Developer Account إلى إعدادات Cloud
  Messaging في Firebase — وهذا يتطلب حساب Apple Developer المدفوع
  (99$/سنة) المذكور سابقاً، ولا تكلفة إضافية غيره.

لا تعديل كود مطلوب لهذا لاحقاً — نفس `notifications` app في Django ونفس
`FcmService` في Flutter يعملان لكلا المنصتين كما هما.
