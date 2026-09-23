# Generated manually for patient inquiry routing.

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('chat', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='chatmessage',
            name='inquiry_type',
            field=models.CharField(
                choices=[('technical', 'Technical inquiry'), ('medical', 'Medical inquiry')],
                default='medical',
                help_text='القناة التي تنتمي إليها الرسالة؛ التقنية للمهندس، والطبية للطبيب والمهندس.',
                max_length=20,
            ),
        ),
    ]
