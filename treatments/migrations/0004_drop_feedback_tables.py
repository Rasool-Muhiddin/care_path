"""
حذف تطبيق feedback (تقييم/تعليق لكل جلسة) نهائياً.

التطبيق أُزيل من INSTALLED_APPS في نفس الـ commit، فلا يمكن حذف جدوله
بـ migration داخله. لذلك يحذفه هذا الـ migration (feedback كان يتبع
جلسات treatments):
- جدول feedback_feedback (IF EXISTS: قاعدة جديدة لم تُنشئه أصلاً).
- صفوف django_migrations الخاصة بـ feedback.
ContentType/صلاحيات feedback القديمة تُنظَّف بـ:
    python manage.py remove_stale_contenttypes
لا رجوع: البيانات المحذوفة غير مطلوبة.
"""

from django.db import migrations


def drop_feedback(apps, schema_editor):
    quote = schema_editor.quote_name
    with schema_editor.connection.cursor() as cursor:
        cursor.execute(f"DROP TABLE IF EXISTS {quote('feedback_feedback')}")
        cursor.execute(f"DELETE FROM {quote('django_migrations')} WHERE app = %s", ["feedback"])


class Migration(migrations.Migration):

    dependencies = [
        ("treatments", "0003_ordering_id_tiebreaker"),
    ]

    operations = [
        migrations.RunPython(drop_feedback, migrations.RunPython.noop),
    ]
