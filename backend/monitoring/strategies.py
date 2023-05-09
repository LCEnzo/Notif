# This file contains scraping strategies/callables
# This whole file is TODO

registry = {}

def register(cls):
    registry[cls.__name__] = cls
    return cls  # return the class so that it's still defined


# Used for choices for the Strategy model
STRATEGY_CHOICES = [(name, name) for name in registry.keys()]


class BaseStrategy():
    def validateUrl(self, url):
        """
        This function exists to check if the strategy CAN scrape the URL. Whether that be a hardcoded list of sites, or whatever.
        """
        pass

    def scrape(self, url, data):
        """
        This function is the basic functionality. It takes in the URL to be scraped, as well as JSON data.
        It should return whether there was new stuff found, and if so, what it is. Return an Optional? <- TODO
        """
        pass


class QQLogInMixin():
    """
    Check generalizability outside of just QQ, to other forums.
    """
    def login(self):
        pass

    pass


@register
class XenoforoThreadmarksStrategy(BaseStrategy):
    """
    Check Xenoforo forum threadmarks. Should optionally have log in functionality.
    """
    pass


@register
class XenoforoAlertsStrategy(BaseStrategy, QQLogInMixin):
    """
    Check QQ threadmarks. Needs to be able to login.
    """
    pass


@register
class GeneralSelectorStrategy(BaseStrategy):
    """
    Uses a CSS selector to check just some element on a page, instead of the whole thing.
    """
    pass