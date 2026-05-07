# Pagination & Filtering

Describes the shipped behavior in `backend/monitoring/views.py` (and `backend/ops/views.py` for system events).

## Page-based, not infinite scroll

Both Links and Notifications use page-based pagination — page numbers at the bottom when `totalPages > 1`. Each page fetch replaces the visible list entirely. There is no "load more" / infinite scroll model, deliberately.

| Resource | Class | `page_size` default | `max_page_size` |
|---|---|---|---|
| Notifications | `NotificationPagination` | 50 | 200 |
| Links | `LinkPagination` | 100 | 500 |
| System events (ops) | `SystemEventPagination` | (see `backend/ops/views.py`) | — |

### Why not continuous scroll?

1. **Dedup complexity.** Pages shift when new items land — a fresh notification on page 1 pushes the old page 1's last item onto page 2. Load-more-then-dedup creates visual glitches where items appear, disappear, or reorder.
2. **Navigation loss.** You can't link to or return to "page 3 of notifications" with infinite scroll. With page numbers, position is explicit and recoverable.
3. **Unread count accuracy.** The server reports a global `unread_count` independent of the current page filter. Continuous scroll makes the relationship between visible items and unread count confusing — "UNREAD 0" with unread items on unloaded pages.
4. **Power-user ergonomics.** For an app meant to handle hundreds of sources and thousands of notifications, paged scanning beats endless scroll.

## Sorting

Sorting is delegated to the backend via DRF's `OrderingFilter`. The FE sends `?ordering=<field>`; the server orders the queryset, paginates, and returns.

Tiebreaker fields (`-pk`) are included in the ordering tuple to keep page boundaries deterministic. Without that, items with identical sort keys can hop pages between fetches.

## Filtering (notifications)

- `?status=unread` (or `read` / `dismissed`) — scopes the queryset to a single status.
- `?since=<ISO datetime>` — only items whose underlying `Update.created_at` is at or after the given timestamp.

Filters apply *before* pagination, so page counts and the visible set both reflect the filtered view.

## `unread_count` is global, not filter-scoped

The `unread_count` field in the paginated response always represents the user's global unread total, independent of `?status=` or `?since=`. The FE's badge stays accurate regardless of the current view.

## Adding more filter dimensions

Same shape: query param → `get_queryset().filter(...)` → paginated response. Candidates: by Link / source, by strategy type, free-text search.
