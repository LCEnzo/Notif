# Scraping strategies for Notif — pluggable callables that extract updates from
# monitored web pages. Each strategy is registered via the @register decorator
# and surfaced through the STRATEGY_CHOICES dict.
#
# TODO: Add batch fetch to Strat classes. By default call _scrape for every URL.
# Implement via requests session, to reduce network load, and request spam.

import hashlib
import json
import logging
import re
from abc import ABC, abstractmethod
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from typing import Any, NamedTuple, NewType, TypeGuard
from urllib.parse import urlsplit, urlunsplit

import feedparser
import requests
from bs4 import BeautifulSoup
from bs4.element import AttributeValueList, ResultSet, Tag
from django.utils import timezone

from commons.result import Err, Ok, Result
from commons.safe_fetch import safe_get

logger = logging.getLogger(__name__)

REQUEST_TIMEOUT_SECONDS = 30
MAX_UPDATE_DESCRIPTION_CHARS = 12000
SELECTOR_DIGEST_BYTES = 16

_BLOCK_TEXT_TAGS = {
	"article",
	"aside",
	"blockquote",
	"br",
	"dd",
	"div",
	"dl",
	"dt",
	"figcaption",
	"figure",
	"h1",
	"h2",
	"h3",
	"h4",
	"h5",
	"h6",
	"header",
	"hr",
	"li",
	"main",
	"nav",
	"ol",
	"p",
	"pre",
	"section",
	"table",
	"tbody",
	"td",
	"tfoot",
	"th",
	"thead",
	"tr",
	"ul",
}

_NON_CONTENT_TAGS = {"button", "form", "iframe", "noscript", "script", "style", "svg"}

# Types
# TODO: Think of moving them to a central location so that the whole app can use them
URL = NewType("URL", str)


class ScrapedUpdate(NamedTuple):
	"""One normalized update emitted by a scraping strategy."""

	title: str
	description: str
	item_url: URL


# A scrape result payload: the normalized updates a strategy found for one source.
type NotifData = list[ScrapedUpdate]
type JsonScalar = None | bool | int | float | str
type JsonValue = JsonScalar | Sequence[JsonValue] | Mapping[str, JsonValue]
type ComparisonState = dict[str, JsonValue]
type ComparisonStateUpdate = ComparisonState | None
type SelectorDigestState = list[str]
type LegacySelectorHashState = list[int]


@dataclass(frozen=True, slots=True)
class ScrapeSuccess:
	"""Successful scrape payload: updates plus optional comparison state to persist."""

	updates: NotifData
	comparison_state_update: ComparisonStateUpdate = None


type ScrapeResult = Result[ScrapeSuccess, str]

# Used for choices for the Strategy model
STRATEGY_CHOICES: dict[str, type[BaseStrategy]] = {}


def register(cls: type[BaseStrategy]) -> type[BaseStrategy]:
	STRATEGY_CHOICES[cls.__name__] = cls
	return cls  # return the class so that it's still defined


def _string_attr_value(value: str | AttributeValueList | None) -> str | None:
	if value is None:
		return None

	if isinstance(value, Sequence) and not isinstance(value, str):
		return " ".join(str(part) for part in value)

	return value


def _fetch_url_content(url: URL) -> str | None:
	try:
		response = safe_get(url, timeout=REQUEST_TIMEOUT_SECONDS)
	except requests.RequestException:
		return None
	if response.status_code == requests.codes.ok:
		return response.text

	return None


def _get_content_with_css_selector(html_content: str, css_selector: str) -> ResultSet[Tag]:
	soup = BeautifulSoup(html_content, "html.parser")
	elements = soup.select(css_selector)
	return elements


def _stable_tag_digest(tag: Tag) -> str:
	return hashlib.blake2s(str(tag).encode("utf-8"), digest_size=SELECTOR_DIGEST_BYTES).hexdigest()


def _legacy_selector_state(value: JsonValue) -> TypeGuard[LegacySelectorHashState]:
	return bool(value) and isinstance(value, list) and all(isinstance(item, int) for item in value)


def _selector_digest_state(value: JsonValue) -> SelectorDigestState:
	if not isinstance(value, list):
		return []
	return [item for item in value if isinstance(item, str)]


def _selector_comparison_state(selector_state: Mapping[str, SelectorDigestState]) -> ComparisonState:
	return dict(selector_state)


def _html_to_readable_text(html_content: str) -> str:
	"""Convert feed HTML into bounded readable text for notification bodies."""
	soup = BeautifulSoup(html_content, "html.parser")

	for tag in soup(_NON_CONTENT_TAGS):
		tag.decompose()

	for tag in soup.find_all(_BLOCK_TEXT_TAGS):
		if tag.name == "br":
			tag.replace_with("\n")
			continue
		tag.insert_before("\n")
		tag.append("\n")

	raw_text = soup.get_text(separator="", strip=False).replace("\xa0", " ")
	lines = [re.sub(r"[ \t\f\v]+", " ", line).strip() for line in raw_text.splitlines()]
	text = "\n".join(line for line in lines if line)
	text = re.sub(r"\s+([,.;:!?])", r"\1", text)
	text = re.sub(r"\n{3,}", "\n\n", text).strip()

	if len(text) <= MAX_UPDATE_DESCRIPTION_CHARS:
		return text

	return text[:MAX_UPDATE_DESCRIPTION_CHARS].rstrip() + "..."


class BaseStrategy(ABC):
	display_name: str = ""  # set by subclasses; used in admin labels

	@abstractmethod
	def can_scrape_url(self, url: URL) -> bool:
		"""
		This function exists to check if the strategy CAN scrape the URL.
		Whether that be a hardcoded list of sites, or whatever.
		"""
		pass

	@abstractmethod
	def scrape(
		self,
		url: URL,
		config_data: dict[str, Any],
		comparison_data: ComparisonState,
		*args: Any,
		**kwargs: Any,
	) -> ScrapeResult:
		"""
		This function is the basic functionality. It takes in the URL to be scraped, as well as JSON data/dict.
		It should return whether there was new stuff found, and if so, what it is.
		Returns Ok(ScrapeSuccess) on success, Err(str) on failure.

		ScrapeSuccess.updates -> list[ScrapedUpdate]
		ScrapeSuccess.comparison_state_update -> None | { "attr name": data for comparison }
		"""
		pass

	def __call__(
		self,
		url: URL,
		config_data: dict[str, Any],
		comparison_data: ComparisonState,
		*args: Any,
		**kwargs: Any,
	) -> ScrapeResult:
		return self.scrape(url, config_data, comparison_data, *args, **kwargs)


@register
class GeneralSelectorStrategy(BaseStrategy):
	"""
	Uses a CSS selector to check just   some element on a page, instead of the whole thing.
	"""

	display_name = "General Selector"

	def can_scrape_url(self, url: URL) -> bool:
		return True

	def scrape(
		self,
		url: URL,
		config_data: dict[str, Any],
		comparison_data: ComparisonState,
		*args: Any,
		**kwargs: Any,
	) -> ScrapeResult:
		selectors: list[str] = config_data["selectors"]
		updates: NotifData = []
		comparison_state_update: ComparisonStateUpdate = None
		has_legacy_selector_state = False
		empty_selector_state: JsonValue = []

		html_content = _fetch_url_content(url)
		if html_content is None:
			return Err("Empty html_content")

		current_selector_state = {
			selector: [_stable_tag_digest(ret) for ret in _get_content_with_css_selector(html_content, selector)]
			for selector in selectors
		}
		comparison_state_update = _selector_comparison_state(current_selector_state)

		for selector in selectors:
			tags = current_selector_state.get(f"{selector}", [])
			old_value = comparison_data.get(str(selector), empty_selector_state)
			old_tags = _selector_digest_state(old_value)
			legacy_state = _legacy_selector_state(old_value)
			has_legacy_selector_state = has_legacy_selector_state or legacy_state

			update = not legacy_state and (len(tags) != len(old_tags) or tags != old_tags)

			if update:
				split = urlsplit(url)
				site_name = split.netloc.split(".")[0]
				updates.append(
					ScrapedUpdate(
						title=f"{site_name} update",
						description=f"selector: {selector}",
						item_url=url,
					)
				)

		# No need to save new info to the db if the new info is the same as the old info
		if len(updates) == 0 and not has_legacy_selector_state:
			comparison_state_update = None

		return Ok(ScrapeSuccess(updates=updates, comparison_state_update=comparison_state_update))


@dataclass
class SThreadmarkInfo:
	title: str | None = None
	word_count: str | None = None
	pub_date: datetime | None = None
	link: URL | None = None

	def to_json(self) -> str:
		json_dict = {
			"title": self.title,
			"word_count": self.word_count,
			"pub_date": None if self.pub_date is None else self.pub_date.isoformat(),
			"link": self.link,
		}
		return json.dumps(json_dict)

	@classmethod
	def from_json(cls, json_str: str) -> SThreadmarkInfo:
		json_dict = json.loads(json_str)
		pub_date = None if json_dict["pub_date"] is None else datetime.fromisoformat(json_dict["pub_date"])
		return cls(
			title=json_dict["title"], word_count=json_dict["word_count"], pub_date=pub_date, link=json_dict["link"]
		)

	def __str__(self) -> str:
		return (
			f"SThreadmark Information:\n"
			f"- Title: {self.title}\n"
			f"- Word Count: {self.word_count}\n"
			f"- Pub Date: {self.pub_date}\n"
			f"- Link: {self.link}"
		)


@register
class SBSVThreadmarksStrategy(BaseStrategy):
	"""
	Check SpaceBattles and SufficientVelocity threadmarks.
	TODO: Specify in configuration which threadmark tabs should be checked.
	"""

	display_name = "SB/SV Threadmarks"

	# format used by strptime strftime
	# found as a attr on an time element
	time_format: str = "%Y-%m-%dT%H:%M:%S%z"

	def can_scrape_url(self, url: URL) -> bool:
		return ("forums.spacebattles.com/threads" in url) or ("forums.sufficientvelocity.com/threads" in url)

	def scrape(self, url: URL, config_data: dict[str, Any], comparison_data: ComparisonState) -> ScrapeResult:
		last_alert_value = comparison_data.get("last_alert")
		last_alert_str = last_alert_value if isinstance(last_alert_value, str) else None

		last_alert: datetime | None = (
			datetime.strptime(last_alert_str, self.time_format).astimezone(timezone.get_default_timezone())
			if last_alert_str is not None and last_alert_str != ""
			else None
		)

		req_url = self._get_threadmarks_url(url)

		try:
			response = safe_get(req_url, timeout=REQUEST_TIMEOUT_SECONDS)
		except requests.RequestException as exc:
			return Err(f"Request failed: {exc}")
		marks = self._extract_threadmarks(response)

		updates: NotifData = [
			ScrapedUpdate(
				title=mark.title if mark.title is not None else "Title not found",
				description=f"New threadmark with {mark.word_count} words, since {mark.pub_date}",
				item_url=mark.link if mark.link is not None else req_url,
			)
			for mark in marks
			if mark.pub_date is not None and (last_alert is None or mark.pub_date > last_alert)
		]

		comparison_state_update: ComparisonState = {"last_alert": ""}
		if len(marks) > 0:
			latest_mark = marks.pop()
			while latest_mark.pub_date is None and len(marks) > 0:
				latest_mark = marks.pop()

			if latest_mark.pub_date is not None and (last_alert is None or latest_mark.pub_date > last_alert):
				comparison_state_update["last_alert"] = latest_mark.pub_date.strftime(self.time_format)

		return Ok(ScrapeSuccess(updates=updates, comparison_state_update=comparison_state_update))

	def _get_threadmarks_url(self, url: URL) -> URL:
		"""
		Takes in a given thread URL, and transforms it into one with a path
		'threadmarks-load-range?threadmark_category_id=1', as to be able to
		easily get a list of all threadmarks.
		"""
		parsed = urlsplit(url)

		# Split the path on 'threadmarks' and take the first part
		new_path = parsed.path.split("threadmarks")[0]
		# Ensure that new_path has a '/' between parts
		if not new_path.endswith("/"):
			new_path += "/"
		new_path += "threadmarks-load-range?threadmark_category_id=1"

		new_url = urlunsplit((parsed.scheme, parsed.netloc, new_path, "", ""))

		return URL(new_url)

	def _extract_title_and_link(self, mark_tag: Tag, base_url: str) -> tuple[str | None, str | None]:
		# The title of the threadmark and the href/link are on the same HTML tag
		title_tag = mark_tag.select_one("a")
		title = link = None
		if title_tag is not None:
			title = title_tag.text
			link = _string_attr_value(title_tag.attrs.get("href"))
			if link is not None:
				link = base_url + link
		return title, link

	def _extract_pub_date(self, mark_tag: Tag) -> datetime | None:
		pub_date_tag = mark_tag.select_one("time")
		if pub_date_tag is not None:
			pub_date_str = _string_attr_value(pub_date_tag.attrs.get("datetime"))
			if pub_date_str is not None:
				try:
					return datetime.strptime(pub_date_str, "%Y-%m-%dT%H:%M:%S%z")
				except ValueError as err:
					logger.error(f"SBSVThreadmarksStrategy | _extract_pub_date: Value Error {err}")
					return None
		return None

	def _extract_wordcount(self, mark_tag: Tag) -> str | None:
		wordcount_tag = mark_tag.select_one("dd")
		return wordcount_tag.text if wordcount_tag is not None else None

	def _extract_threadmarks(self, response: requests.Response) -> list[SThreadmarkInfo]:
		"""
		Takes in a response that should contain the threadmarks page,
		and returns a list of threadmarks encoded as SThreadmarkInfo.
		"""
		marks: list[SThreadmarkInfo] = []
		mark_tags = _get_content_with_css_selector(response.text, ".structItem--threadmark")

		base_url = response.url
		parsed_url = urlsplit(base_url)
		scheme = parsed_url.scheme
		netloc = parsed_url.netloc
		base_url = f"{scheme}://{netloc}"

		for mark_tag in mark_tags:
			title, link = self._extract_title_and_link(mark_tag, base_url)
			pub_date = self._extract_pub_date(mark_tag)
			wordcount = self._extract_wordcount(mark_tag)

			mark_info = SThreadmarkInfo(
				title=title, word_count=wordcount, pub_date=pub_date, link=URL(link) if link is not None else None
			)

			if mark_info.link is not None:
				marks.append(mark_info)

		return marks


@dataclass
class AlertInfo:
	"""
	Mainly exists for QQ alerts, can probably be used for SV and SB.
	"""

	author_name: str | None = None
	author_link: str | None = None
	avatar_image_url: str | None = None
	post_link: str | None = None
	alert_text: str | None = None
	post_time: time | None = None
	# lengthy ergo likely a chapter post
	lengthy_response: bool = False
	post_date: date | None = None

	def to_json(self) -> str:
		json_dict = {
			"author_name": self.author_name,
			"author_link": self.author_link,
			"avatar_image_url": self.avatar_image_url,
			"post_link": self.post_link,
			"alert_text": self.alert_text,
			"lengthy_response": self.lengthy_response,
			"post_date": None if self.post_date is None else self.post_date.isoformat(),
			"post_time": None if self.post_time is None else self.post_time.strftime("%H:%M:%S"),
		}
		return json.dumps(json_dict)

	@classmethod
	def from_json(cls, json_str: str) -> AlertInfo:
		json_dict = json.loads(json_str)
		post_date = None if json_dict["post_date"] is None else date.fromisoformat(json_dict["post_date"])
		post_time = None if json_dict["post_time"] is None else time.fromisoformat(json_dict["post_time"])
		return cls(
			author_name=json_dict["author_name"],
			author_link=json_dict["author_link"],
			avatar_image_url=json_dict["avatar_image_url"],
			post_link=json_dict["post_link"],
			alert_text=json_dict["alert_text"],
			lengthy_response=json_dict["lengthy_response"],
			post_date=post_date,
			post_time=post_time,
		)

	def __str__(self) -> str:
		return (
			f"Alert Information:\n"
			f"- Author Name: {self.author_name}\n"
			f"- Author Link: {self.author_link}\n"
			f"- Avatar Image URL: {self.avatar_image_url}\n"
			f"- Post Link: {self.post_link}\n"
			f"- Alert Text: {self.alert_text}\n"
			f"- Date: {self.post_date}\n"
			f"- Time: {self.post_time}\n"
			f"- Likely chapter: {self.lengthy_response}"
		)


@register
class QQAlertsStrategy(BaseStrategy):
	"""
	Check QQ alerts.

	Config data should include username, password, and optionally
	whether to include notifications other than likely story updates.
	"""

	display_name = "QQ Alerts"

	login_url = "https://forum.questionablequesting.com/login/login"
	alerts_url = "https://forum.questionablequesting.com/account/alerts"

	def can_scrape_url(self, url: URL) -> bool:
		parsed_url = urlsplit(url)

		alerts_domain = urlsplit(self.alerts_url).netloc
		alerts_path = urlsplit(self.alerts_url).path

		return alerts_domain == parsed_url.netloc and alerts_path == parsed_url.path

	def scrape(
		self,
		url: URL,
		config_data: dict[str, Any],
		comparison_data: ComparisonState,
		*args: Any,
		**kwargs: Any,
	) -> ScrapeResult:
		if not self.can_scrape_url(url):
			return Err("Invalid URL")
		updates: NotifData = []

		username: str = config_data["username"]
		password: str = config_data["password"]
		# Whether to include all alerts, or only those likely to be a new chapter
		include_all: bool = bool(config_data["include_all"])

		last_alert_datetime = self._parse_last_alert_datetime(comparison_data.get("last_alert"))

		try:
			resp = self._get_alerts_html(username, password)
		except requests.RequestException as exc:
			return Err(f"Request failed: {exc}")
		alerts = self._extract_alerts(resp.text)

		# Fill updates with new alerts
		for alert in alerts:
			if alert.post_date is not None and alert.post_time is not None:
				alert_dt = datetime.combine(alert.post_date, alert.post_time, tzinfo=timezone.get_default_timezone())

				if (last_alert_datetime is None or alert_dt > last_alert_datetime) and (
					include_all or alert.lengthy_response
				):
					title = "QQ: " + (
						f"Likely chapter by {alert.author_name}"
						if alert.lengthy_response
						else f"Alert - {alert.author_name}"
					)
					description = alert.alert_text if alert.alert_text is not None else "-/-"
					link = URL(alert.post_link) if alert.post_link is not None else url

					updates.append(ScrapedUpdate(title=title, description=description, item_url=link))

		comparison_state_update: ComparisonStateUpdate = None
		# search alerts for latest update (discarding those with None time)
		for alert in alerts:
			if alert.post_date is not None and alert.post_time is not None:
				alert_dt = datetime.combine(alert.post_date, alert.post_time, tzinfo=timezone.get_default_timezone())

				if (last_alert_datetime is None or alert_dt > last_alert_datetime) and (
					include_all or alert.lengthy_response
				):
					comparison_state_update = {"last_alert": alert_dt.strftime("%Y-%m-%d %H:%M:%S")}
					break

		return Ok(ScrapeSuccess(updates=updates, comparison_state_update=comparison_state_update))

	@staticmethod
	def _parse_last_alert_datetime(value: object) -> datetime | None:
		if not isinstance(value, str) or value.strip() == "":
			return None
		return datetime.strptime(value, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.get_default_timezone())

	@staticmethod
	def _extract_alerts(html: str) -> list[AlertInfo]:
		groups = _get_content_with_css_selector(html, ".alertGroup")

		alerts = []
		for group in groups:
			date_text = group.select("h2.textHeading")[0].text
			date = QQAlertsStrategy._convert_relative_date(date_text)

			alert_list_items = group.select("li.primaryContent")
			for alert in alert_list_items:
				alert_info = QQAlertsStrategy._extract_alert_info(alert)
				alert_info.post_date = date
				alerts.append(alert_info)

		return alerts

	@staticmethod
	def _get_alerts_html(username: str, password: str) -> requests.Response:
		parsed_url = urlsplit(QQAlertsStrategy.alerts_url)

		session_cookie_name = "xf_session"
		# mce_cookie_name = 'xf_mce_ccv'

		payload = {
			"login": username,
			"register": "0",
			"password": password,
			"cookie_check": "1",
			"_xfToken": "",
			"redirect": "/account/alerts",
		}

		user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " + (
			"(KHTML, like Gecko) Chrome/105.0.0.0 Safari/537.36 Edg/105.0.1343.42"
		)

		login_headers = {
			"User-Agent": user_agent,
			"Referer": QQAlertsStrategy.alerts_url,
			"Host": parsed_url.netloc,
			"Origin": f"{parsed_url.scheme}://{parsed_url.netloc}",
		}

		with requests.Session() as session:
			get_response = session.get(QQAlertsStrategy.alerts_url, timeout=REQUEST_TIMEOUT_SECONDS)
			get_response.raise_for_status()
			session_cookie = get_response.cookies.get(session_cookie_name)
			login_headers["Cookie"] = f"{session_cookie_name}={session_cookie}"

			# Adds login_headers to session
			for header, value in login_headers.items():
				session.headers[header] = value

			# AFAIK this will get the alerts page HTML due to the redirect part of the payload/data
			response = session.post(QQAlertsStrategy.login_url, data=payload, timeout=REQUEST_TIMEOUT_SECONDS)
			response.raise_for_status()
			session.close()

		return response

	@staticmethod
	def _extract_alert_info(notif: Tag) -> AlertInfo:
		parsed_url = urlsplit(QQAlertsStrategy.alerts_url)
		url: URL = URL(f"{parsed_url.scheme}://{parsed_url.netloc}")

		# Initialize the fields with None
		author_name = None
		author_link = None
		avatar_image_url = None
		post_link = None
		alert_text = None
		post_time = None

		# Extract author name and link
		author_tag = notif.find("a", class_="username subject")
		if author_tag is not None:
			author_name = author_tag.text.strip()
			author_link = f"{url}/{author_tag['href']}"

		# Extract author avatar image URL
		avatar_img = notif.find("img")
		if avatar_img is not None:
			avatar_image_url = f"{url}/{avatar_img['src']}"

		# Extract post link
		post_link_tag = notif.find("a", class_="PopupItemLink")
		if post_link_tag is not None:
			post_link = f"{url}/{post_link_tag['href']}"

		time_tag = notif.find("span", class_="time")
		if time_tag is not None:
			time_as_list = [int(s) for s in time_tag.text.strip().split(":")]
			# If given hours and minutes, or HH MM ss
			if len(time_as_list) in [2, 3]:
				post_time = time(time_as_list[0], time_as_list[1])

		# Extract alert text
		lengthy_response = False
		alert_text_div = notif.find("div", class_="alertText")
		if alert_text_div is not None:
			alert_text = alert_text_div.text.strip()
			alert_text = alert_text.replace("\n", " ")

			# Remove the time from alert text
			if time_tag is not None:
				alert_text = alert_text.replace(time_tag.text.strip(), "")

			regex_pattern = r"replied with [0-9]+(\.[0-9]+)?k? words"
			lengthy_response = bool(re.search(regex_pattern, alert_text))

		# Return the extracted information as an instance of the AlertInfo data class
		return AlertInfo(
			author_name=author_name,
			author_link=author_link,
			avatar_image_url=avatar_image_url,
			post_link=post_link,
			alert_text=alert_text,
			post_time=post_time,
			lengthy_response=lengthy_response,
		)

	@staticmethod
	def _convert_relative_date(relative_date: str) -> date:
		"""
		Note, can cause an exception if neither Today, Yesterday,
		of a valid argument for strptime is provided ("%Y-%m-%d").
		"""
		today = datetime.now(tz=timezone.get_default_timezone()).date()

		match relative_date:
			case "Today":
				return today
			case "Yesterday":
				return today - timedelta(days=1)
			case "Monday" | "Tuesday" | "Wednesday" | "Thursday" | "Friday" | "Saturday" | "Sunday":
				weekday = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"].index(
					relative_date.title()
				)
				days_offset = (today.weekday() - weekday) % 7
				return today - timedelta(days=days_offset)
			case _:
				return date.fromisoformat(relative_date.replace("/", "-"))

		# For mypy
		raise ValueError


@dataclass
class KemonoCardInfo:
	name: str | None = None
	date_time: datetime | None = None
	service: str | None = None
	link: URL | None = None

	def to_json(self) -> str:
		json_dict = {
			"name": self.name,
			"date_time": None if self.date_time is None else self.date_time.isoformat(),
			"service": self.service,
			"link": self.link,
		}
		return json.dumps(json_dict)

	@classmethod
	def from_json(cls, json_str: str) -> KemonoCardInfo:
		json_dict = json.loads(json_str)
		date_time = None if json_dict["date_time"] is None else datetime.fromisoformat(json_dict["date_time"])
		return cls(name=json_dict["name"], date_time=date_time, service=json_dict["service"], link=json_dict["link"])

	def __str__(self) -> str:
		return (
			f"Kemono Profile Information:\n"
			f"- Service: {self.service}\n"
			f"- Name: {self.name}\n"
			f"- Date and Time: {self.date_time}\n"
			f"- Link: {self.link}"
		)


@register
class KemonoFavouritesStrategy(BaseStrategy):
	"""
	Check Kemono favourites.

	Config data should include username, password.
	"""

	display_name = "Kemono Favourites"

	login_url = "https://kemono.party/account/login"
	fav_url = "https://kemono.party/favorites"

	def can_scrape_url(self, url: URL) -> bool:
		parsed_url = urlsplit(url)

		alerts_domain = urlsplit(self.fav_url).netloc
		alerts_path = urlsplit(self.fav_url).path

		return alerts_domain == parsed_url.netloc and alerts_path == parsed_url.path

	def scrape(
		self,
		url: URL,
		config_data: dict[str, Any],
		comparison_data: ComparisonState,
		*args: Any,
		**kwargs: Any,
	) -> ScrapeResult:
		if not self.can_scrape_url(url):
			return Err("Invalid URL")
		updates: NotifData = []

		username: str = config_data["username"]
		password: str = config_data["password"]

		last_update_datetime = self._parse_last_update_datetime(comparison_data.get("last_update"))

		try:
			resp = self._get_favourites_html(username, password)
		except requests.RequestException as exc:
			return Err(f"Request failed: {exc}")
		cards = self._extract_kemono_profile_cards(resp.text)

		# Fill updates with new alerts
		for card in cards:
			if card.date_time is not None and (last_update_datetime is None or card.date_time > last_update_datetime):
				title = f"Kemono: {card.name} - {card.service}"
				description = f"New posts by {card.name} on {card.service}, time {card.date_time}"
				link = card.link if card.link is not None else url

				updates.append(ScrapedUpdate(title=title, description=description, item_url=link))

		comparison_state_update = None
		# search alerts for latest update (discarding those with None time)
		for card in cards:
			if card.date_time is not None and (last_update_datetime is None or card.date_time > last_update_datetime):
				json_dt = json.loads(card.to_json())["date_time"]
				comparison_state_update = {"last_update": json_dt}
				break

		return Ok(ScrapeSuccess(updates=updates, comparison_state_update=comparison_state_update))

	@staticmethod
	def _parse_last_update_datetime(value: object) -> datetime | None:
		if not isinstance(value, str) or value.strip() == "":
			return None
		try:
			parsed = datetime.fromisoformat(value)
		except ValueError:
			parsed = datetime.strptime(value, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.get_default_timezone())
		if timezone.is_naive(parsed):
			return timezone.make_aware(parsed, timezone.get_default_timezone())
		return parsed.astimezone(timezone.get_default_timezone())

	def _extract_service(self, card_tag: Tag) -> str | None:
		service = card_tag.select_one(".user-card__service")
		return service.text.strip() if service is not None else None

	def _extract_name(self, card_tag: Tag) -> str | None:
		name = card_tag.select_one(".user-card__name")
		return name.text.strip() if name is not None else None

	def _extract_datetime(self, card_tag: Tag) -> datetime | None:
		dt = card_tag.select_one("time.timestamp")
		if dt is not None:
			return datetime.strptime(dt.text.strip(), "%Y-%m-%d %H:%M:%S.%f").replace(
				tzinfo=timezone.get_default_timezone()
			)
		return None

	def _extract_link(self, card_tag: Tag, url: URL) -> URL | None:
		link = _string_attr_value(card_tag.attrs.get("href"))
		return URL(url + "/" + link) if link is not None else None

	def _extract_kemono_profile_cards(self, html: str) -> list[KemonoCardInfo]:
		card_tags = _get_content_with_css_selector(html, ".user-card")
		parsed_url = urlsplit(KemonoFavouritesStrategy.fav_url)
		url: URL = URL(f"{parsed_url.scheme}://{parsed_url.netloc}")

		cards = []
		for card_tag in card_tags:
			service = self._extract_service(card_tag)
			name = self._extract_name(card_tag)
			dt = self._extract_datetime(card_tag)
			link = self._extract_link(card_tag, url)

			cards.append(KemonoCardInfo(name=name, date_time=dt, service=service, link=link))

		return cards

	@staticmethod
	def _get_favourites_html(username: str, password: str) -> requests.Response:
		data = {
			"username": f"{username}",
			"password": f"{password}",
		}

		with requests.session() as session:
			login_response = session.post(
				KemonoFavouritesStrategy.login_url, data=data, timeout=REQUEST_TIMEOUT_SECONDS
			)
			login_response.raise_for_status()

			fav_response = session.get(KemonoFavouritesStrategy.fav_url, timeout=REQUEST_TIMEOUT_SECONDS)
			fav_response.raise_for_status()

			session.close()

		return fav_response


@register
class FeedStrategy(BaseStrategy):
	"""
	Parse RSS and Atom feeds using feedparser.

	Works with:
	- Substack (e.g. https://example.substack.com/feed)
	- XenForo forums (e.g. https://forum.example.com/index.rss)
	- Any standard RSS 2.0 or Atom feed

	Config data (all optional):
	- No config required — just the feed URL.

	Comparison state:
	- ``last_entry_id``: the best newest-entry marker available for backwards compatibility.
	- ``seen_entry_hashes``: a bounded list of recently seen entry identifier hashes for compact dedupe.
	"""

	display_name = "RSS"

	ENTRY_ID_HASH_BYTES = 16
	MAX_SEEN_ENTRY_HASHES = 1000

	def can_scrape_url(self, url: URL) -> bool:
		"""No URL-shape prefilter; validity is determined by fetching and parsing."""
		return True

	def scrape(
		self,
		url: URL,
		config_data: dict[str, Any],
		comparison_data: ComparisonState,
		*args: Any,
		**kwargs: Any,
	) -> ScrapeResult:
		try:
			response = safe_get(url, timeout=REQUEST_TIMEOUT_SECONDS)
			response.raise_for_status()
		except requests.RequestException as exc:
			return Err(f"Feed fetch failed: {exc}")

		feed = feedparser.parse(response.content)

		if feed.bozo and not feed.entries:
			bozo_msg = str(feed.bozo_exception) if feed.bozo_exception else "unknown parse error"
			logger.warning("FeedStrategy: bozo error for %s: %s", url, bozo_msg)
			return Err(f"Feed parse error: {bozo_msg}")

		entries = self._sorted_entries(feed.entries)
		if not entries:
			empty_updates: NotifData = []
			return Ok(ScrapeSuccess(updates=empty_updates))

		last_entry_value = comparison_data.get("last_entry_id")
		last_entry_id = last_entry_value if isinstance(last_entry_value, str) else None
		seen_entry_hashes = self._seen_entry_hashes(comparison_data)
		seen_entry_hash_set = set(seen_entry_hashes)

		updates: NotifData = []
		current_entry_hashes: list[str] = []
		new_last_entry_id: str | None = None

		for entry in entries:
			entry_id = self._entry_id(entry)
			entry_hash = self._entry_id_hash(entry_id)
			current_entry_hashes.append(entry_hash)
			if new_last_entry_id is None:
				new_last_entry_id = entry_id

			if seen_entry_hash_set and entry_hash in seen_entry_hash_set:
				continue

			# Backwards compatibility for comparison state written before
			# seen_entry_hashes existed. We skip the marker, but keep scanning
			# because feed order is not guaranteed.
			if not seen_entry_hash_set and last_entry_id is not None and entry_id == last_entry_id:
				continue

			# A present-but-empty <title> is common in the wild, and dict.get
			# only substitutes when the key is absent.
			title = str(entry.get("title") or "").strip() or "Untitled"
			description = self._entry_description(entry)
			link = URL(entry.get("link", url))

			updates.append(ScrapedUpdate(title=title, description=description, item_url=link))

		new_seen_entry_hashes = self._merge_seen_entry_hashes(current_entry_hashes, seen_entry_hashes)

		comparison_update: ComparisonStateUpdate = None
		if updates and new_last_entry_id is not None:
			comparison_update = {
				"last_entry_id": new_last_entry_id,
				"seen_entry_hashes": new_seen_entry_hashes,
			}

		return Ok(ScrapeSuccess(updates=updates, comparison_state_update=comparison_update))

	@classmethod
	def _entry_description(cls, entry: dict[str, Any]) -> str:
		for value in cls._entry_content_values(entry):
			text = _html_to_readable_text(value)
			if text:
				return text
		return ""

	@staticmethod
	def _entry_content_values(entry: dict[str, Any]) -> list[str]:
		values: list[str] = []

		content = entry.get("content")
		if isinstance(content, list):
			for item in content:
				if isinstance(item, dict):
					value = item.get("value")
					if isinstance(value, str) and value.strip():
						values.append(value)

		for key in ("content_encoded", "description", "summary"):
			value = entry.get(key)
			if isinstance(value, str) and value.strip():
				values.append(value)

		return values

	@classmethod
	def _merge_seen_entry_hashes(cls, current_entry_hashes: list[str], previous_entry_hashes: list[str]) -> list[str]:
		merged_entry_hashes: list[str] = []
		merged_entry_hash_set: set[str] = set()

		for entry_hash in [*current_entry_hashes, *previous_entry_hashes]:
			if entry_hash in merged_entry_hash_set:
				continue
			merged_entry_hashes.append(entry_hash)
			merged_entry_hash_set.add(entry_hash)

			if len(merged_entry_hashes) >= cls.MAX_SEEN_ENTRY_HASHES:
				break

		return merged_entry_hashes

	@classmethod
	def _seen_entry_hashes(cls, comparison_data: ComparisonState) -> list[str]:
		value = comparison_data.get("seen_entry_hashes")
		if isinstance(value, list):
			entry_hashes = [str(entry_hash) for entry_hash in value if entry_hash]
			if entry_hashes:
				return entry_hashes

		legacy_entry_ids = comparison_data.get("seen_entry_ids")
		if not isinstance(legacy_entry_ids, list):
			return []
		return [cls._entry_id_hash(str(entry_id)) for entry_id in legacy_entry_ids if entry_id]

	@classmethod
	def _entry_id_hash(cls, entry_id: str) -> str:
		return hashlib.blake2s(entry_id.encode("utf-8"), digest_size=cls.ENTRY_ID_HASH_BYTES).hexdigest()

	@staticmethod
	def _sorted_entries(entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
		indexed_entries = list(enumerate(entries))
		if not any(FeedStrategy._entry_timestamp(entry) is not None for _, entry in indexed_entries):
			return entries

		return [
			entry
			for _, entry in sorted(
				indexed_entries,
				key=lambda indexed_entry: FeedStrategy._entry_sort_key(indexed_entry[0], indexed_entry[1]),
			)
		]

	@staticmethod
	def _entry_sort_key(index: int, entry: dict[str, Any]) -> tuple[int, float, int]:
		timestamp = FeedStrategy._entry_timestamp(entry)
		if timestamp is None:
			return (1, 0, index)
		return (0, -timestamp, index)

	@staticmethod
	def _entry_timestamp(entry: dict[str, Any]) -> float | None:
		for key in ("published_parsed", "updated_parsed", "created_parsed"):
			parsed = entry.get(key)
			if parsed is None:
				continue

			try:
				year, month, day, hour, minute, second = parsed[:6]
				return datetime(year, month, day, hour, minute, second, tzinfo=UTC).timestamp()
			except TypeError, ValueError:
				continue

		return None

	@staticmethod
	def _entry_id(entry: dict[str, Any]) -> str:
		"""Return a stable identifier for a feed entry.

		Prefers the ``id`` field; falls back to ``link``. If neither is
		present, hashes the title so we always return *something*.
		"""
		eid = entry.get("id")
		if eid:
			return str(eid)
		link = entry.get("link")
		if link:
			return str(link)
		title = str(entry.get("title", ""))
		return f"sha256:{hashlib.sha256(title.encode('utf-8')).hexdigest()}"
