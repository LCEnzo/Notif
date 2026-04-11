# Backend MVP Plan

Source: Plan subagent from dead remote session `57c639b1-ca54-4f44-a7a8-a1beae9d17a8` (2026-04-11)

5 phases, ordered by dependency. Each phase is independently completable and testable.

## Dependency Graph

```
Phase 1 (Result type)
    |
    v
Phase 2 (Update + Notification models)    Phase 3 (Timeouts + Rate limiting)
    |                                         |
    +------------------+----------------------+
                       |
                       v
              Phase 4 (Service layer + Command + Trigger endpoint)
                       |
                       v
              Phase 5 (Polish + Integration tests)
```

Phases 2 and 3 are independent of each other but both depend on Phase 1. Phase 4 depends on both.

---

## Phase 1: Result Type (`commons/result.py`)

**Why first**: Every subsequent phase uses this type. Replaces `type NotifDataOrError = str | NotifData` with a proper discriminated union.

**New file**: `backend/commons/result.py`

```python
from dataclasses import dataclass
from typing import Generic, TypeVar

T = TypeVar("T")
E = TypeVar("E")

@dataclass(frozen=True, slots=True)
class Ok(Generic[T]):
    value: T
    def is_ok(self) -> bool: return True
    def is_err(self) -> bool: return False

@dataclass(frozen=True, slots=True)
class Err(Generic[E]):
    error: E
    def is_ok(self) -> bool: return False
    def is_err(self) -> bool: return True

type Result[T, E] = Ok[T] | Err[E]
```

Design notes:
- `frozen=True` — immutable value objects
- `slots=True` — minor memory efficiency
- Python 3.13 `type` statement (matches existing codebase style — see `type NotifData = ...` in strategies.py)
- Pattern matching: `match result: case Ok(value=data): ... case Err(error=msg): ...`

**Modifications to `backend/monitoring/strategies.py`**:
- Change `type NotifDataOrError = str | NotifData` → `type ScrapeResult = Result[NotifData, str]`
- Update `BaseStrategy.scrape()` return type from `tuple[NotifDataOrError, DataDict]` → `tuple[ScrapeResult, DataDict]`
- Update each strategy's `scrape()` to return `Ok(updates)` / `Err("error message")`
- Update `__call__` accordingly

**Tests**:
- `test_ok_is_ok`, `test_err_is_err` — basic construction
- `test_match_ok`, `test_match_err` — pattern matching
- Update existing strategy tests to check for `Ok` instead of `not isinstance(notif_data, str)`

**Scope**: ~40 lines new code, ~20 lines modified across strategies.

**Status**: `result.py` created (with additional `map`, `map_err`, `and_then`, `unwrap`, `unwrap_or`, `unwrap_err` methods beyond the minimal plan). `strategies.py` not yet updated.

---

## Phase 2: Update and Notification Models (`monitoring/models.py`)

**Why second**: The scrape command (Phase 4) needs somewhere to store results.

**New models in `backend/monitoring/models.py`**:

```python
class Update(models.Model):
    """A single scraped update item (what was found)."""
    link = models.ForeignKey(Link, on_delete=models.CASCADE, related_name='updates')
    title = models.CharField(max_length=500)
    description = models.TextField(blank=True)
    item_url = models.URLField(max_length=1000, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

class Notification(models.Model):
    """Delivery state for an update — tracks whether the user has seen it."""
    class Status(models.TextChoices):
        UNREAD = 'unread', 'Unread'
        READ = 'read', 'Read'
        DISMISSED = 'dismissed', 'Dismissed'

    update = models.OneToOneField(Update, on_delete=models.CASCADE, related_name='notification')
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.UNREAD)
    read_at = models.DateTimeField(null=True, blank=True)
```

Design rationale:
- Separate models: Update = what was scraped, Notification = delivery/read state
- OneToOneField: every update gets exactly one notification (can become FK later for multi-user)
- No `user` FK — derived through `update.link.user`
- `item_url` maps to the third element of `NotifData` tuple `(title, description, link)`

**New serializers** (`backend/monitoring/serializers.py`):

```python
class UpdateSerializer(ModelSerializer):
    class Meta:
        model = Update
        fields = ['id', 'link', 'title', 'description', 'item_url', 'created_at']
        read_only_fields = fields  # Created by scraper, not user

class NotificationSerializer(ModelSerializer):
    update = UpdateSerializer(read_only=True)
    class Meta:
        model = Notification
        fields = ['id', 'update', 'status', 'read_at']
        read_only_fields = ['id', 'update', 'read_at']
```

**New views** (`backend/monitoring/views.py`):
- `NotificationViewSet`: list (filtered to auth user), PATCH status, bulk "mark all read"
- No create/delete — notifications created by scraper, dismissal is status change

**URLs**: `router.register(r'notifications', NotificationViewSet, basename="notifications")`

**Admin**: Register `Update` and `Notification`

**Tests**:
- List notifications returns only requesting user's
- PATCH mark as read sets `read_at`
- Other users cannot see/modify your notifications
- Factory helpers in `commons/utils.py`

**Scope**: ~80 lines models/serializers/views, ~60 lines tests.

---

## Phase 3: Request Timeouts and Rate Limiting

**Why third**: Scrape command (Phase 4) needs these before it can safely run.

### 3A: Request Timeouts

Add `timeout=30` to every `requests.get/post` call in `strategies.py`:
- `_fetch_url_content()` 
- `SBSVThreadmarksStrategy.scrape()` 
- `QQAlertsStrategy._get_alerts_html()` 
- `KemonoFavouritesStrategy._get_favourites_html()`

Each strategy's `scrape()` should catch `requests.Timeout` and `requests.RequestException` → return `Err(...)`.

### 3B: Per-Domain Rate Limiting

**New file**: `backend/monitoring/rate_limiter.py`

```python
import time
from urllib.parse import urlsplit

DEFAULT_DOMAIN_DELAY = 2.0

class DomainRateLimiter:
    def __init__(self, delay: float = DEFAULT_DOMAIN_DELAY):
        self._delay = delay
        self._last_request: dict[str, float] = {}

    def wait_for_domain(self, url: str) -> None:
        domain = urlsplit(url).netloc
        now = time.monotonic()
        last = self._last_request.get(domain, 0.0)
        wait = self._delay - (now - last)
        if wait > 0:
            time.sleep(wait)
        self._last_request[domain] = time.monotonic()
```

- Instance-based, not global state
- `time.monotonic()` for elapsed-time measurement
- Rate limiter is caller's responsibility, not embedded in strategies (keeps strategies testable)

**Tests**:
- Same domain waits, different domains don't
- Timeout returns Err

**Scope**: ~30 lines rate limiter, ~15 lines timeout additions, ~30 lines tests.

---

## Phase 4: Scrape Orchestration

**Why fourth**: Depends on all prior phases.

### 4A: Scrape Service (`backend/monitoring/services.py`)

```python
def scrape_link(link: Link, rate_limiter: DomainRateLimiter | None = None) -> Result[int, str]:
    """Scrape a single link. Returns Ok(update_count) or Err(error_message)."""
    # 1. Resolve strategy class from link.strategy.strat_cls
    # 2. Rate-limit if provided
    # 3. Call strategy.scrape(url, config_data, comparison_data)
    # 4. On Ok: create Update + Notification for each item, update link.comparison_info
    # 5. On Err: log and return error

def scrape_all_links(user_id: int | None = None) -> dict[int, Result[int, str]]:
    """Scrape all links (or for a specific user). Returns {link_id: result}."""
```

Key details:
- Parse `comparison_data` from `link.comparison_info` (JSON string in CharField)
- **Deduplication**: Before creating Update, check if identical `(link, title, item_url)` exists within last 24 hours
- **Fix `last_scraped`**: Change from `auto_now=True` to `default=None`, manage explicitly in `scrape_link`

### 4B: Management Command (`backend/monitoring/management/commands/scrape.py`)

```
python manage.py scrape                  # scrape everything
python manage.py scrape --user 1         # one user's links
python manage.py scrape --link 5         # one link
python manage.py scrape --delay 5        # 5s between same-domain requests
```

For cron: `*/30 * * * * cd /path/to/backend && python manage.py scrape`

### 4C: Trigger Endpoint (`backend/monitoring/views.py`)

```python
@api_view(['POST'])
@permission_classes([IsAuthenticated])
def trigger_scrape(request):
    # POST with link_id: scrape one link
    # POST without: scrape all user's links
```

URL: `path("trigger-scrape/", trigger_scrape, name='trigger-scrape')`

**Tests**:
- scrape_link with Ok result creates Update + Notification
- scrape_link with error returns Err, no Update created
- Deduplication works
- Management command runs
- Trigger endpoint works
- Other user's links forbidden
- comparison_info updated after scrape

**Scope**: ~100 lines service, ~40 lines command, ~30 lines endpoint, ~120 lines tests.

---

## Phase 5: Polish and Integration Testing

### 5A: Fix `last_scraped` auto_now
Change `auto_now=True` → `default=None`, manage explicitly. (Logically belongs in Phase 4.)

### 5B: Notification endpoint optimization
- `?status=unread` filter
- `?since=<iso_datetime>` for polling efficiency

### 5C: End-to-end tests
1. Create user, strategy, link via API
2. Call `scrape_link` (mocked HTTP)
3. Query notifications API, verify update appears
4. Mark notification as read, verify status changes

---

## Files Summary

**New files**:
| File | Purpose |
|------|---------|
| `backend/commons/result.py` | `Ok[T]` / `Err[E]` / `Result[T, E]` type |
| `backend/monitoring/services.py` | `scrape_link()`, `scrape_all_links()` orchestration |
| `backend/monitoring/rate_limiter.py` | `DomainRateLimiter` class |
| `backend/monitoring/management/commands/scrape.py` | `manage.py scrape` command |

**Modified files**:
| File | Changes |
|------|---------|
| `backend/monitoring/strategies.py` | Use `Result` type, add timeouts, catch exceptions |
| `backend/monitoring/models.py` | Add `Update` and `Notification` models, fix `last_scraped` |
| `backend/monitoring/serializers.py` | Add `UpdateSerializer`, `NotificationSerializer` |
| `backend/monitoring/views.py` | Add `NotificationViewSet`, `trigger_scrape` endpoint |
| `backend/monitoring/urls.py` | Register new routes |
| `backend/monitoring/admin.py` | Register new models |
| `backend/monitoring/tests.py` | All new tests |
| `backend/commons/utils.py` | Test data factory for updates/notifications |
