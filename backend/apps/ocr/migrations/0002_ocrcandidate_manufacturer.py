from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("ocr", "0001_initial")]

    operations = [
        migrations.AddField(
            model_name="ocrcandidate",
            name="manufacturer",
            field=models.CharField(blank=True, max_length=200),
        ),
    ]
