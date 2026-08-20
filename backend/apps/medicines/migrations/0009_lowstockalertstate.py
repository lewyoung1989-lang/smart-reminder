from decimal import Decimal
import uuid

import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("medicines", "0008_inventorybatch_loose_units_and_more"),
    ]

    operations = [
        migrations.CreateModel(
            name="LowStockAlertState",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid4,
                        editable=False,
                        primary_key=True,
                        serialize=False,
                    ),
                ),
                ("unit_name", models.CharField(max_length=16)),
                ("threshold_days", models.PositiveIntegerField()),
                (
                    "remaining_quantity",
                    models.DecimalField(decimal_places=3, max_digits=12),
                ),
                (
                    "daily_quantity",
                    models.DecimalField(decimal_places=3, max_digits=12),
                ),
                (
                    "days_remaining",
                    models.DecimalField(decimal_places=2, max_digits=8),
                ),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("pending", "Pending"),
                            ("active", "Active"),
                            ("resolved", "Resolved"),
                            ("superseded", "Superseded"),
                        ],
                        default="pending",
                        max_length=16,
                    ),
                ),
                ("activated_at", models.DateTimeField(blank=True, null=True)),
                ("resolved_at", models.DateTimeField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "medicine",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="low_stock_alerts",
                        to="medicines.medicineitem",
                    ),
                ),
            ],
        ),
        migrations.AddConstraint(
            model_name="lowstockalertstate",
            constraint=models.UniqueConstraint(
                fields=("medicine", "unit_name", "threshold_days"),
                name="low_stock_alert_medicine_unit_threshold_unique",
            ),
        ),
        migrations.AddConstraint(
            model_name="lowstockalertstate",
            constraint=models.CheckConstraint(
                condition=~models.Q(("unit_name", "")),
                name="low_stock_alert_unit_name_nonempty",
            ),
        ),
        migrations.AddConstraint(
            model_name="lowstockalertstate",
            constraint=models.CheckConstraint(
                condition=models.Q(("threshold_days__gt", 0)),
                name="low_stock_alert_threshold_days_positive",
            ),
        ),
        migrations.AddConstraint(
            model_name="lowstockalertstate",
            constraint=models.CheckConstraint(
                condition=models.Q(("remaining_quantity__gte", Decimal("0"))),
                name="low_stock_alert_remaining_quantity_nonnegative",
            ),
        ),
        migrations.AddConstraint(
            model_name="lowstockalertstate",
            constraint=models.CheckConstraint(
                condition=models.Q(("daily_quantity__gt", Decimal("0"))),
                name="low_stock_alert_daily_quantity_positive",
            ),
        ),
        migrations.AddConstraint(
            model_name="lowstockalertstate",
            constraint=models.CheckConstraint(
                condition=models.Q(("days_remaining__gte", Decimal("0"))),
                name="low_stock_alert_days_remaining_nonnegative",
            ),
        ),
    ]
