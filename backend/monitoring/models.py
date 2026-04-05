from django.core.serializers.json import DjangoJSONEncoder
from django.db import models

from accounts.models import User
from monitoring import strategies


def choices_dict_to_tuple() -> list[tuple[str, str]]:
	names = strategies.STRATEGY_CHOICES.keys()
	return [(el, el) for el in names]


class Strategy(models.Model):
	'''
	A instance of a class contains 2 things. A reference to a strategy class, and data.
	The data is configuration, like a CSS selector. This data is why the model exists.
	In principle, this could all be part of the Link model.
	'''
	data = models.JSONField(
		encoder=DjangoJSONEncoder,
		default=dict,
	)
	strat_cls = models.CharField(
		max_length=256,
		choices=choices_dict_to_tuple(),
	)

	def __str__(self):
		return f"Strategy {self.pk}: {self.strat_cls}"


class Link(models.Model):
	name = models.CharField(max_length=200)
	url = models.URLField(max_length=1000)
	user = models.ForeignKey(User, on_delete=models.CASCADE)
	strategy = models.ForeignKey(Strategy, default=None, null=True, on_delete=models.SET_NULL, related_name='link_set')
	last_scraped = models.DateTimeField(auto_now=True, null=True, blank=True)
	# Information with which to compare newly scraped data, to see whether a update has occurred
	# Will probably add things like timestamps, html snippet hashes, etc
	# I should consider what type of field to have. Previous scrape response or whatever
	comparison_info = models.CharField(max_length=16*16*1024, blank=True)

	def __str__(self):
		return f"Link {self.pk} - {self.name}: {self.url}"
