# `run_due_tasks` — scheduled maintenance command

Source: `backend/ops/management/commands/run_due_tasks.py`.

## Purpose

A single management command that a systemd timer invokes on a fixed cadence (e.g. every 5 minutes). It decides what is due — scrape jobs, cleanup tasks — and runs a bounded slice of them. systemd expresses cadence; the command and DB express which work is due.

This is the production scheduler. The older `manage.py scrape` command remains for ad-hoc invocation but should not be the cron entry-point.

## Responsibilities

1. Acquire a single-process maintenance lock (`MaintenanceLock`, key `run_due_tasks`). Skip the run if a non-stale lock is held.
2. Delete expired or attempt-locked password-reset codes.
3. Select due Links — `next_scrape_at` is null or `<= now`, `scrape_disabled = False` — ordered by `(next_scrape_at, pk)`.
4. Run a bounded number of scrapes with per-domain rate limiting (`DomainRateLimiter`).
5. Record outcome:
   - **Success** resets `scrape_failure_count`, clears `last_scrape_error`, schedules `next_scrape_at = now + scrape_interval_minutes`.
   - **Failure** increments `scrape_failure_count` (capped at 30), stores a truncated error in `last_scrape_error`, applies exponential backoff capped at 24h.
6. Emit a `SystemEvent` row summarizing the run.

## CLI flags

| Flag | Default | Meaning |
|---|---|---|
| `--max-links` | 20 | Max due Links scraped per run |
| `--max-runtime-seconds` | 240 | Soft runtime cap; loop exits between Links once exceeded |
| `--delay` | 2.0 | Seconds between same-domain requests |
| `--lock-ttl-seconds` | 1800 | Stale-lock threshold (30 min) |

## Scheduling state on `Link`

| Field | Type | Default | Meaning |
|---|---|---|---|
| `scrape_interval_minutes` | PositiveIntegerField | 15 | Cadence; validated 5..1440 |
| `next_scrape_at` | DateTimeField (indexed, nullable) | null | When this Link is next eligible. Null = due immediately |
| `scrape_disabled` | BooleanField | False | Skip this Link entirely |
| `scrape_failure_count` | PositiveSmallIntegerField | 0 | Capped at 30; drives exponential backoff |
| `last_scrape_error` | CharField(500) | "" | Truncated message from the last failure |
| `last_scraped` | DateTimeField (nullable) | null | Last successful scrape |

## Backoff math

```
backoff_minutes = min(
    scrape_interval_minutes * 2^(failure_count - 1),
    24 * 60,
)
```

A Link with a 15-minute interval that fails 6 times in a row backs off to ≈8 hours; further failures cap at 24 hours.

## Production status

Preferred production wiring as of **2026-05-18**: `deploy/systemd/notif-run-due-tasks.timer` invokes `deploy/systemd/notif-run-due-tasks.service`, which runs `python manage.py run_due_tasks` inside the backend container. To verify operationally: `systemctl list-timers 'notif-*'`, `journalctl -u notif-run-due-tasks.service --since today --no-pager`, plus recent `SystemEvent` rows with `source='ops.run_due_tasks'`.
