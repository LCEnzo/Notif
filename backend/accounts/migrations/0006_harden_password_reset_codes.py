from django.db import migrations, models


def delete_legacy_reset_codes(apps, schema_editor):
	PasswordResetCode = apps.get_model("accounts", "PasswordResetCode")
	PasswordResetCode.objects.all().delete()


class Migration(migrations.Migration):
	dependencies = [
		("accounts", "0005_passwordresetcode"),
	]

	operations = [
		migrations.RemoveIndex(
			model_name="passwordresetcode",
			name="accounts_pa_code_5fdba2_idx",
		),
		migrations.RenameField(
			model_name="passwordresetcode",
			old_name="code",
			new_name="code_hash",
		),
		migrations.AlterField(
			model_name="passwordresetcode",
			name="code_hash",
			field=models.CharField(max_length=64),
		),
		migrations.AddField(
			model_name="passwordresetcode",
			name="failed_attempts",
			field=models.PositiveSmallIntegerField(default=0),
		),
		migrations.RunPython(delete_legacy_reset_codes, migrations.RunPython.noop),
		migrations.AddIndex(
			model_name="passwordresetcode",
			index=models.Index(fields=["code_hash", "created_at"], name="accounts_pa_code_hash_idx"),
		),
	]
