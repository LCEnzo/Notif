from django.core.serializers.json import DjangoJSONEncoder
from django.db import models

from accounts.models import User
from monitoring import strategies


class Strategy(models.Model):
	# Things like what selectors to use, and the like
	# Think of it like configuration
	data = models.JSONField(
		encoder=DjangoJSONEncoder,
		default=dict,
	)
	function = models.CharField(
		max_length=256,
		choices=strategies.STRATEGY_CHOICES,
	)

	def __str__(self):
		return f"Strategy {self.pk}: {self.function}"


class Link(models.Model):
	name = models.CharField(max_length=200)
	url = models.URLField(max_length=1000)
	user = models.ForeignKey(User, on_delete=models.CASCADE)
	strategy = models.ForeignKey(Strategy, default=None, null=True, on_delete=models.SET_NULL)
	last_scraped = models.DateTimeField(auto_now=True, null=True, blank=True)
	# Information with which to compare newly scraped data, to see whether a update has occurred
	# Will probably add things like timestamps, html snippet hashes, etc
	# I should consider what type of field to have
	comparison_info = models.CharField(max_length=16*16*1024, blank=True)

	def __str__(self):
		return f"Link {self.pk} - {self.name}: {self.url}"
