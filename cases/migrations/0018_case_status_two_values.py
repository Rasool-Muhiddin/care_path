from django.db import migrations, models


def to_two_statuses(apps, schema_editor):
    # كل حالة غير مغلقة (new, under_evaluation, ...) تصبح in_treatment؛
    # المغلقة تبقى مغلقة. القيود الفريدة تعتمد فقط على "مغلقة أم لا"،
    # فلا يمكن أن يخرقها هذا التحويل.
    Case = apps.get_model("cases", "Case")
    Case.objects.exclude(status="closed").exclude(status="in_treatment").update(status="in_treatment")


class Migration(migrations.Migration):

    dependencies = [
        ("cases", "0017_remove_case_progress_note"),
    ]

    operations = [
        migrations.RunPython(to_two_statuses, migrations.RunPython.noop),
        migrations.AlterField(
            model_name="case",
            name="status",
            field=models.CharField(
                choices=[("in_treatment", "In Treatment"), ("closed", "Closed")],
                default="in_treatment",
                max_length=25,
            ),
        ),
    ]
