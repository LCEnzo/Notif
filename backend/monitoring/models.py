from django.db import models
from accounts.models import User
from monitoring import strategies


class Strategy(models.Model):
    data = models.JSONField()
    function = models.CharField(
        max_length=20,
        choices=strategies.STRATEGY_CHOICES,
        default='strategy1',
    )


class Link(models.Model):
    name = models.CharField(max_length=200)
    url = models.URLField(max_length=1000)
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    strategy = models.ForeignKey(Strategy, default=None, null=True, on_delete=models.SET_NULL)
    last_scraped = models.DateTimeField(null=True, default=None)

