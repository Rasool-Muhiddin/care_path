from django.db import migrations
from django.utils import timezone


def backfill_last_seen(apps, schema_editor):
    # بدون هذا، كل المستخدمين الحاليين last_seen_at=NULL بعد النشر، فيعتبرهم
    # send_attack_reminders غير نشطين منذ انضمامهم ويرسل لهم تذكيراً بأول
    # تشغيل. نعتبرهم "شوهدوا" لحظة النشر: التذكير يبدأ لمن لا يفتح التطبيق
    # خلال 3 أيام بعده.
    User = apps.get_model("accounts", "User")
    User.objects.filter(last_seen_at__isnull=True).update(last_seen_at=timezone.now())


class Migration(migrations.Migration):
    dependencies = [
        ("accounts", "0003_user_activity_tracking"),
    ]

    operations = [
        migrations.RunPython(backfill_last_seen, migrations.RunPython.noop),
    ]
