from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("medicines", "0005_expirybatchaction_change_json_and_more"),
    ]

    operations = [
        migrations.AddField(
            model_name="medicineitem",
            name="manufacturer",
            field=models.CharField(blank=True, max_length=200),
        ),
        migrations.AddField(
            model_name="medicineitem",
            name="photo_content_type",
            field=models.CharField(blank=True, max_length=32),
        ),
        migrations.AddField(
            model_name="medicineitem",
            name="photo_object_key",
            field=models.CharField(blank=True, max_length=300),
        ),
    ]
