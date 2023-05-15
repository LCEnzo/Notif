# This file contains scraping strategies/callables
# This whole file is TODO

from typing import TypeAlias, Any
from abc import ABC, abstractmethod
from urllib.parse import urlsplit

import requests
from bs4 import BeautifulSoup
from bs4.element import ResultSet, Tag

from rest_framework import status

# Types
# TODO: Think of moving them to a centreal location so that the whole app can use them
URL: TypeAlias = str
NotifData: TypeAlias = list[tuple[str, str, str]]
DataDict: TypeAlias = None | dict[str, Any]
NotifDataOrError: TypeAlias = str | NotifData


registry = {}

def register(cls):
    registry[cls.__name__] = cls
    return cls  # return the class so that it's still defined


# Used for choices for the Strategy model
STRATEGY_CHOICES = [(name, name) for name in registry.keys()]

def _fetch_url_content(url: URL) -> str | None:
    response = requests.get(url)
    if response.status_code == status.HTTP_200_OK:
        return response.text
    else:
        return None

def _get_content_with_css_selector(html_content: str, css_selector: str) -> ResultSet[Tag]:
    soup = BeautifulSoup(html_content, 'html.parser')
    elements = soup.select(css_selector)
    return elements


class BaseStrategy(ABC):
    @abstractmethod
    def can_scrape_url(self, url: URL) -> bool:
        """
        This function exists to check if the strategy CAN scrape the URL. 
        Whether that be a hardcoded list of sites, or whatever.
        """
        pass

    @abstractmethod
    def scrape(self, url: URL, config_data: dict, comparison_data: dict, 
               *args, **kwargs) -> tuple[NotifDataOrError, DataDict]:
        """
        This function is the basic functionality. It takes in the URL to be scraped, as well as JSON data.
        It should return whether there was new stuff found, and if so, what it is. 
        Returns None in case nothing was found, str for errors, and the list of tuples containing a 
        title, descrpition, and link in case of new content. It also returns new data if there is any.
        """
        pass

    def __call__(self, url: URL, config_data: dict, comparison_data: dict, 
                 *args, **kwargs) -> tuple[NotifDataOrError, DataDict]:
        return self.scrape(url, config_data, comparison_data, args, kwargs)


@register
class GeneralSelectorStrategy(BaseStrategy):
    """
    Uses a CSS selector to check just some element on a page, instead of the whole thing.
    """
    def can_scrape_url(self, url: URL) -> bool:
        return True

    def scrape(self, url: URL, config_data: dict[str, Any], comparison_data: dict[str, list[int]], 
               *args, **kwargs) -> tuple[NotifDataOrError, DataDict]:
        selectors: list[str] = config_data['selectors'] 
        old_data: dict[str, list[int]] = { 
            selector: 
                comparison_data.get(str(selector), []) 
            for selector in selectors 
        }
        updates: NotifData = []
        new_data: dict[str, list[int]] | None = None

        html_content = _fetch_url_content(url)
        if html_content is None:
            return "Empty html_content", None

        new_data = {
            selector: 
                list(
                    [hash(ret) for ret in _get_content_with_css_selector(html_content, selector)]
                ) 
            for selector in selectors
        }

        for selector in selectors:
            tags = new_data.get(f'{selector}', [])
            old_tags = old_data.get(f'{selector}', [])
            update = False

            if len(tags) != len(old_tags):
                update = True
            else:
                update = tags != old_tags
            
            if update:
                split = urlsplit(url)
                site_name = split.netloc.split('.')[0]
                updates += [(f'{site_name} update', f'selector: {selector}', url)]

        # No need to save new info to the db if the new info is the same as the old info
        if len(updates) == 0:
            new_data = None

        return updates, new_data


class QQLogInMixin():
    """
    Check generalizability outside of just QQ, to other forums.
    """
    def login(self):
        pass

    pass


@register
class SpaceBattlesThreadmarksStrategy(BaseStrategy):
    """
    Check SpaceBattles threadmarks. Configuration should specify which threadmark tabs should be checked.
    """
    pass


@register
class QQAlertsStrategy(BaseStrategy, QQLogInMixin):
    """
    Check QQ alerts. Needs to be able to login.
    """
    pass
