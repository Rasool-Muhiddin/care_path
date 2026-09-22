from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('cases', '0006_caseprogressnote'),
    ]

    operations = [
        migrations.RenameField(
            model_name='case',
            old_name='weekly_episode_count',
            new_name='monthly_episode_count',
        ),
        migrations.AlterField(
            model_name='case',
            name='monthly_episode_count',
            field=models.PositiveIntegerField(blank=True, help_text='عدد النوبات في الشهر', null=True),
        ),
        migrations.AlterField(
            model_name='case',
            name='episode_duration_minutes',
            field=models.PositiveIntegerField(
                blank=True,
                help_text='متوسط مدة النوبة بالدقائق (يُخزَّن دائماً بالدقائق حتى لو أدخله الطبيب بالساعات)',
                null=True,
            ),
        ),
        migrations.AlterField(
            model_name='case',
            name='diagnosis_type',
            field=models.CharField(choices=[('migraine', 'Migraine'), ('epilepsy', 'Epilepsy')], max_length=20),
        ),
        migrations.AddField(
            model_name='case',
            name='disease_type',
            field=models.CharField(
                blank=True,
                choices=[('type1', 'Type 1'), ('type2', 'Type 2'), ('type3', 'Type 3')],
                help_text='نوع/تصنيف فرعي للمرض (قيم مؤقتة: type1/type2/type3)',
                max_length=20,
            ),
        ),
        migrations.AddField(
            model_name='case',
            name='symptoms',
            field=models.TextField(blank=True, help_text='الأعراض التي يعاني منها المريض (نص حر)'),
        ),
    ]