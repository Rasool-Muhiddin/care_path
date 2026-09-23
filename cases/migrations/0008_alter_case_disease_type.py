from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('cases', '0007_case_disease_type_case_symptoms_and_more'),
    ]

    operations = [
        migrations.AlterField(
            model_name='case',
            name='disease_type',
            field=models.CharField(
                blank=True,
                choices=[('type1', 'Type 1'), ('type2', 'Type 2'), ('type3', 'Type 3')],
                help_text='نوع/تصنيف فرعي للمرض — يعتمد على diagnosis_type (انظر DISEASE_TYPE_CHOICES_BY_DIAGNOSIS)',
                max_length=20,
            ),
        ),
    ]
