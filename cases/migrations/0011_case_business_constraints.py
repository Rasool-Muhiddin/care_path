from django.db import migrations, models
from django.db.models import Count


def check_existing_data(apps, schema_editor):
    """
    يفحص البيانات الحالية قبل إضافة القيود، ويتوقف برسالة تسرد الحالات
    المخالفة بالتحديد بدل خطأ IntegrityError غامض من قاعدة البيانات.
    """
    Case = apps.get_model("cases", "Case")
    problems = []

    duplicate_patients = (
        Case.objects.exclude(status="closed")
        .values("patient_id")
        .annotate(n=Count("id"))
        .filter(n__gt=1)
    )
    for row in duplicate_patients:
        ids = list(
            Case.objects.filter(patient_id=row["patient_id"])
            .exclude(status="closed")
            .values_list("id", flat=True)
        )
        problems.append(
            f"- المريض #{row['patient_id']} لديه أكثر من حالة غير مغلقة: {ids} "
            "(أغلق الزائد منها status=closed)"
        )

    duplicate_devices = (
        Case.objects.filter(device__isnull=False)
        .values("device_id")
        .annotate(n=Count("id"))
        .filter(n__gt=1)
    )
    for row in duplicate_devices:
        ids = list(Case.objects.filter(device_id=row["device_id"]).values_list("id", flat=True))
        problems.append(
            f"- الجهاز {row['device_id']} مرتبط بأكثر من حالة: {ids} "
            "(أبقِه على حالة واحدة واجعل device فارغاً في البقية)"
        )

    if problems:
        raise RuntimeError(
            "لا يمكن إضافة قيود الحالات لأن البيانات الحالية تخالفها. "
            "أصلح الحالات التالية من لوحة الأدمن ثم أعد تشغيل migrate:\n"
            + "\n".join(problems)
        )


class Migration(migrations.Migration):

    dependencies = [
        ('cases', '0010_alter_case_disease_type'),
    ]

    operations = [
        migrations.RunPython(check_existing_data, migrations.RunPython.noop),
        migrations.AddConstraint(
            model_name='case',
            constraint=models.UniqueConstraint(
                condition=models.Q(('status', 'closed'), _negated=True),
                fields=('patient',),
                name='one_active_case_per_patient',
            ),
        ),
        migrations.AddConstraint(
            model_name='case',
            constraint=models.UniqueConstraint(
                condition=models.Q(('device__isnull', False)),
                fields=('device',),
                name='one_case_per_device',
            ),
        ),
    ]
