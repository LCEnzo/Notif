from django.db import migrations


class Migration(migrations.Migration):
	dependencies = [
		("monitoring", "0006_alter_link_comparison_info_alter_link_last_scraped_and_more"),
	]

	operations = [
		migrations.RenameField(
			model_name="strategy",
			old_name="function",
			new_name="strat_cls",
		),
	]
