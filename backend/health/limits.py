"""The ingest contract's bounds. Value bounds are looser than HC's own: a record HC accepted must
never be refused here, or one odd record would stall a whole backfill."""

# 4 MiB, enforced while reading the body.
MAX_INGEST_BYTES = 4 * 1024 * 1024
# Records of every type, deletions, and aggregate-window hours, together.
MAX_INGEST_ITEMS = 5_000
# 2100-01-01T00:00:00Z.
MAX_EPOCH_MS = 4_102_444_800_000
# java.time.ZoneOffset's range.
MAX_ZONE_OFFSET_S = 18 * 3_600
MAX_STRING_LENGTH = 255
MAX_TEXT_LENGTH = 10_000
MAX_SLEEP_STAGES = 10_000
MAX_STEPS_PER_RECORD = 10_000_000
MAX_BEATS_PER_MINUTE = 1_000
# 31 days of hourly buckets.
MAX_WINDOW_HOURS = 31 * 24
MAX_DATA_ORIGINS = 100
# Steps per hour, or milliseconds of sleep per hour.
MAX_AGGREGATE_VALUE = 1_000_000_000
