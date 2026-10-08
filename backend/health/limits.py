"""Every bound the ingest contract enforces, in one place.

Value bounds are deliberately looser than Health Connect's own: a record HC accepted
must never be refused here, or one odd record would stall a whole backfill.
"""

from health.models import HOUR_MS

# 4 MiB. Enforced while reading, before any JSON parsing.
MAX_INGEST_BYTES = 4 * 1024 * 1024
# Records of every type, deletions, and the hours the aggregate windows span, together.
MAX_INGEST_ITEMS = 5_000

# 2100-01-01T00:00:00Z. HC timestamps are epoch ms on the phone's clock.
MAX_EPOCH_MS = 4_102_444_800_000
# java.time.ZoneOffset's range, in seconds.
MAX_ZONE_OFFSET_S = 18 * 3_600

MAX_STRING_LENGTH = 255
MAX_TEXT_LENGTH = 10_000
MAX_SLEEP_STAGES = 10_000
MAX_STEPS_PER_RECORD = 10_000_000
MAX_BEATS_PER_MINUTE = 1_000

# One aggregate window spans at most 31 days of hourly buckets.
MAX_WINDOW_HOURS = 31 * 24
MAX_DATA_ORIGINS = 100
# Steps per hour, or milliseconds of sleep per hour bucket.
MAX_AGGREGATE_VALUE = 1_000_000_000

__all__ = [
	"HOUR_MS",
	"MAX_AGGREGATE_VALUE",
	"MAX_BEATS_PER_MINUTE",
	"MAX_DATA_ORIGINS",
	"MAX_EPOCH_MS",
	"MAX_INGEST_BYTES",
	"MAX_INGEST_ITEMS",
	"MAX_SLEEP_STAGES",
	"MAX_STEPS_PER_RECORD",
	"MAX_STRING_LENGTH",
	"MAX_TEXT_LENGTH",
	"MAX_WINDOW_HOURS",
	"MAX_ZONE_OFFSET_S",
]
