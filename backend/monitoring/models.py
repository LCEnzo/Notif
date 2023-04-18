from django.db import models
from accounts.models import User

class Link(models.Model):
    name = models.CharField(max_length=200)
    url = models.URLField(max_length=1000)
    user = models.ForeignKey(User, on_delete=models.CASCADE)
