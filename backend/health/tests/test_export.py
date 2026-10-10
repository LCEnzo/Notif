"""export_health against fixed CSV.

Belgrade in 2026 springs forward at 2026-03-29T01:00Z (a 23-hour day) and falls back at
2026-10-25T01:00Z (a 25-hour day). Expected rows were worked out by hand from those
instants, not from the code under test.
"""

from datetime import date
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest
from django.core.management import CommandError, call_command

from accounts.models import User
from commons.utils import create_users
from health.export import ExportSpec, Profile, export
from health.ingest import Deletion, RecordVersion, Source, apply_batch
from health.models import AggregateMetric, RecordType
from health.tests.support import HOUR, ORIGIN, batch, ms, steps_version, uid, window

pytestmark = pytest.mark.django_db

OWNER = 3
BELGRADE = ZoneInfo("Europe/Belgrade")
WATCH = Source(ORIGIN, "automatically_recorded", "watch", "Google", "Pixel Watch 2")
DAILY_HEADER = "date,type,value,unit,window_start_utc,window_end_utc,n,partial\n"


@pytest.fixture(autouse=True)
def _owners() -> None:
	# Fixed ids keep the expected rows readable.
	for pk in (OWNER, OWNER + 1):
		User.objects.create(pk=pk, username=f"export-owner-{pk}", email=f"export-owner-{pk}@example.com")


def _export(tmp_path: Path, profile: Profile, record_type: RecordType, **spec: object) -> str:
	options = {"tz": BELGRADE, "start": None, "end": None, **spec}
	[(path, rows)] = export(
		ExportSpec(owner_id=OWNER, profile=profile, types=(record_type,), output_dir=tmp_path, **options)  # type: ignore[arg-type]
	)
	text = path.read_text(encoding="utf-8")
	assert (path, rows) == (tmp_path / f"{profile}-{record_type}.csv", text.count("\n") - 1)
	return text


def _heart(n: int, at: int, bpm: int, last_modified: int = 1) -> RecordVersion:
	return RecordVersion(
		hc_id=uid(n),
		record_type=RecordType.RESTING_HEART_RATE,
		source=Source("com.fitbit.FitbitMobile", "unknown", None, None, None),
		start_ms=at,
		start_offset_s=None,
		end_ms=None,
		end_offset_s=None,
		last_modified_ms=last_modified,
		payload={"beats_per_minute": bpm},
	)


def _sleep(n: int, start: int, end: int, stages: list[tuple[int, int, str]], title: str | None) -> RecordVersion:
	return RecordVersion(
		hc_id=uid(n),
		record_type=RecordType.SLEEP_SESSION,
		source=WATCH,
		start_ms=start,
		start_offset_s=3_600,
		end_ms=end,
		end_offset_s=3_600,
		last_modified_ms=ms(2026, 3, 30),
		payload={
			"title": title,
			"notes": None,
			"stages": [{"start_ms": s, "end_ms": e, "stage": stage} for s, e, stage in stages],
		},
	)


# ── daily ────────────────────────────────────────────────────


def _spring_and_autumn_steps() -> None:
	spring = ms(2026, 3, 28, 22)
	autumn = ms(2026, 10, 24, 22)
	apply_batch(
		OWNER,
		batch(
			# Local 23:00 on the 28th; 00:00, 03:00 (just after the jump) and 23:00 on the 29th; 00:00 on the 30th.
			window(
				AggregateMetric.STEPS_COUNT_TOTAL,
				spring,
				25,
				computed_at=1,
				values={0: 10, 1: 20, 3: 5, 23: 30, 24: 40},
			),
			# Local 00:00, 02:00 CEST, 02:00 CET and 23:00 on the 25th.
			window(AggregateMetric.STEPS_COUNT_TOTAL, autumn, 25, computed_at=1, values={0: 1, 2: 2, 3: 4, 24: 8}),
		),
	)


def test_daily_steps_sum_each_local_day_across_both_transitions(tmp_path: Path):
	_spring_and_autumn_steps()

	assert _export(tmp_path, Profile.DAILY, RecordType.STEPS) == DAILY_HEADER + (
		"2026-03-28,steps,10,count,2026-03-27T23:00:00.000Z,2026-03-28T23:00:00.000Z,1,true\n"
		"2026-03-29,steps,55,count,2026-03-28T23:00:00.000Z,2026-03-29T22:00:00.000Z,3,false\n"
		"2026-03-30,steps,40,count,2026-03-29T22:00:00.000Z,2026-03-30T22:00:00.000Z,1,true\n"
		"2026-10-25,steps,15,count,2026-10-24T22:00:00.000Z,2026-10-25T23:00:00.000Z,4,false\n"
	)


def test_daily_range_is_inclusive_local_dates(tmp_path: Path):
	_spring_and_autumn_steps()

	text = _export(tmp_path, Profile.DAILY, RecordType.STEPS, start=date(2026, 3, 29), end=date(2026, 3, 30))

	assert text == DAILY_HEADER + (
		"2026-03-29,steps,55,count,2026-03-28T23:00:00.000Z,2026-03-29T22:00:00.000Z,3,false\n"
		"2026-03-30,steps,40,count,2026-03-29T22:00:00.000Z,2026-03-30T22:00:00.000Z,1,true\n"
	)


def test_a_day_hc_answered_with_nothing_is_a_zero_not_a_gap(tmp_path: Path):
	day = ms(2026, 6, 30, 22)
	apply_batch(OWNER, batch(window(AggregateMetric.STEPS_COUNT_TOTAL, day, 24, computed_at=1, values={})))

	assert _export(tmp_path, Profile.DAILY, RecordType.STEPS) == DAILY_HEADER + (
		"2026-07-01,steps,0,count,2026-06-30T22:00:00.000Z,2026-07-01T22:00:00.000Z,0,false\n"
	)


def test_one_unasked_hour_makes_a_25_hour_day_partial(tmp_path: Path):
	# The fall-back day's last hour, local 23:00 CET, was never asked about.
	apply_batch(OWNER, batch(window(AggregateMetric.STEPS_COUNT_TOTAL, ms(2026, 10, 24, 22), 24, 1, {0: 3})))

	assert _export(tmp_path, Profile.DAILY, RecordType.STEPS) == DAILY_HEADER + (
		"2026-10-25,steps,3,count,2026-10-24T22:00:00.000Z,2026-10-25T23:00:00.000Z,1,true\n"
	)


def test_daily_sleep_is_counted_noon_to_noon_by_wake_date(tmp_path: Path):
	apply_batch(
		OWNER,
		batch(
			# Local 11:00, 12:00 and 23:00 CET on the 28th; 11:00 and 12:00 CEST on the 29th.
			window(
				AggregateMetric.SLEEP_DURATION_TOTAL,
				ms(2026, 3, 28, 10),
				25,
				computed_at=1,
				values={0: 600_000, 1: 1_800_000, 12: 3_600_000, 23: 1_500, 24: 2_000},
			)
		),
	)

	assert _export(tmp_path, Profile.DAILY, RecordType.SLEEP_SESSION) == DAILY_HEADER + (
		"2026-03-28,sleep_session,600,s,2026-03-27T11:00:00.000Z,2026-03-28T11:00:00.000Z,1,true\n"
		"2026-03-29,sleep_session,5401.5,s,2026-03-28T11:00:00.000Z,2026-03-29T10:00:00.000Z,3,false\n"
		"2026-03-30,sleep_session,2,s,2026-03-29T10:00:00.000Z,2026-03-30T10:00:00.000Z,1,true\n"
	)


def test_daily_resting_heart_rate_is_the_latest_reading_of_the_day(tmp_path: Path):
	apply_batch(
		OWNER,
		batch(
			_heart(1, ms(2026, 10, 25, 22, 59) + 59_999, bpm=50),
			_heart(2, ms(2026, 10, 25, 0, 30), bpm=60),
			# Same instant: the newer modification wins, though its id sorts first.
			_heart(3, ms(2026, 10, 25, 23), bpm=71, last_modified=2),
			_heart(4, ms(2026, 10, 25, 23), bpm=70, last_modified=1),
			coverage_start_ms=ms(2026, 10, 25, 12),
		),
	)
	apply_batch(OWNER, batch(coverage_start_ms=ms(2026, 10, 26)))

	# The first day starts before the earliest coverage any batch reported, so it may be missing readings.
	assert _export(tmp_path, Profile.DAILY, RecordType.RESTING_HEART_RATE) == DAILY_HEADER + (
		"2026-10-25,resting_heart_rate,50,bpm,2026-10-24T22:00:00.000Z,2026-10-25T23:00:00.000Z,2,true\n"
		"2026-10-26,resting_heart_rate,71,bpm,2026-10-25T23:00:00.000Z,2026-10-26T23:00:00.000Z,2,false\n"
	)


def test_one_batch_with_the_history_permission_lifts_the_floor(tmp_path: Path):
	apply_batch(OWNER, batch(_heart(1, ms(2026, 10, 25, 12), bpm=50), coverage_start_ms=ms(2026, 10, 26)))
	apply_batch(OWNER, batch(coverage_start_ms=None))

	assert _export(tmp_path, Profile.DAILY, RecordType.RESTING_HEART_RATE).endswith(",1,false\n")


# ── raw ──────────────────────────────────────────────────────

RAW_COMMON = (
	"hc_id,data_origin,recording_method,device_type,device_manufacturer,device_model,"
	"start_utc,start_local,start_offset_s,end_utc,end_local,end_offset_s,last_modified_utc"
)


def test_raw_steps_render_local_times_on_both_sides_of_the_fall_back(tmp_path: Path):
	apply_batch(
		OWNER,
		batch(
			RecordVersion(
				hc_id=uid(1),
				record_type=RecordType.STEPS,
				source=WATCH,
				start_ms=ms(2026, 10, 25, 0, 30),
				start_offset_s=7_200,
				end_ms=ms(2026, 10, 25, 1, 30),
				end_offset_s=3_600,
				last_modified_ms=ms(2026, 10, 26),
				payload={"count": 42},
			)
		),
	)

	assert _export(tmp_path, Profile.RAW, RecordType.STEPS) == (
		f"{RAW_COMMON},count\n"
		"00000000-0000-0000-0000-000000000001,com.google.android.apps.fitness,automatically_recorded,watch,"
		"Google,Pixel Watch 2,2026-10-25T00:30:00.000Z,2026-10-25T02:30:00.000+02:00,7200,"
		"2026-10-25T01:30:00.000Z,2026-10-25T02:30:00.000+01:00,3600,2026-10-26T00:00:00.000Z,42\n"
	)


def test_raw_instant_records_leave_end_and_device_blank(tmp_path: Path):
	apply_batch(OWNER, batch(_heart(1, ms(2026, 7, 1, 6), bpm=55, last_modified=ms(2026, 7, 1, 7))))

	assert _export(tmp_path, Profile.RAW, RecordType.RESTING_HEART_RATE, tz=ZoneInfo("UTC")) == (
		f"{RAW_COMMON},beats_per_minute\n"
		"00000000-0000-0000-0000-000000000001,com.fitbit.FitbitMobile,unknown,,,,"
		"2026-07-01T06:00:00.000Z,2026-07-01T06:00:00.000+00:00,,,,,2026-07-01T07:00:00.000Z,55\n"
	)


def test_raw_sleep_has_one_row_per_stage_and_one_for_a_session_without_stages(tmp_path: Path):
	night = ms(2026, 3, 29, 20)
	apply_batch(
		OWNER,
		batch(
			_sleep(
				1,
				night,
				night + 2 * HOUR,
				[(night, night + HOUR, "light"), (night + HOUR, night + 2 * HOUR, "rem")],
				"nap, short",
			),
			_sleep(2, night + 24 * HOUR, night + 25 * HOUR, [], None),
		),
	)

	session_1 = (
		"00000000-0000-0000-0000-000000000001,com.google.android.apps.fitness,automatically_recorded,watch,Google,"
		"Pixel Watch 2,2026-03-29T20:00:00.000Z,2026-03-29T22:00:00.000+02:00,3600,2026-03-29T22:00:00.000Z,"
		'2026-03-30T00:00:00.000+02:00,3600,2026-03-30T00:00:00.000Z,"nap, short",,'
	)
	session_2 = (
		"00000000-0000-0000-0000-000000000002,com.google.android.apps.fitness,automatically_recorded,watch,Google,"
		"Pixel Watch 2,2026-03-30T20:00:00.000Z,2026-03-30T22:00:00.000+02:00,3600,2026-03-30T21:00:00.000Z,"
		"2026-03-30T23:00:00.000+02:00,3600,2026-03-30T00:00:00.000Z,,,"
	)
	assert _export(tmp_path, Profile.RAW, RecordType.SLEEP_SESSION) == (
		f"{RAW_COMMON},title,notes,stage,stage_start_utc,stage_start_local,stage_end_utc,stage_end_local\n"
		f"{session_1}light,2026-03-29T20:00:00.000Z,2026-03-29T22:00:00.000+02:00,"
		"2026-03-29T21:00:00.000Z,2026-03-29T23:00:00.000+02:00\n"
		f"{session_1}rem,2026-03-29T21:00:00.000Z,2026-03-29T23:00:00.000+02:00,"
		"2026-03-29T22:00:00.000Z,2026-03-30T00:00:00.000+02:00\n"
		f"{session_2},,,,\n"
	)


def test_raw_range_follows_the_local_date_of_the_start(tmp_path: Path):
	apply_batch(
		OWNER,
		batch(
			steps_version(uid(1), last_modified=1, start=ms(2026, 3, 28, 22, 59), end=ms(2026, 3, 28, 23)),
			steps_version(uid(2), last_modified=1, start=ms(2026, 3, 28, 23), end=ms(2026, 3, 28, 23, 1)),
			steps_version(uid(3), last_modified=1, start=ms(2026, 3, 29, 21, 59), end=ms(2026, 3, 29, 22)),
			steps_version(uid(4), last_modified=1, start=ms(2026, 3, 29, 22), end=ms(2026, 3, 29, 22, 1)),
		),
	)

	text = _export(tmp_path, Profile.RAW, RecordType.STEPS, start=date(2026, 3, 29), end=date(2026, 3, 29))

	assert [line.split(",")[0][-1] for line in text.splitlines()[1:]] == ["2", "3"]


def test_deleted_and_other_owners_records_are_not_exported(tmp_path: Path):
	apply_batch(OWNER, batch(steps_version(uid(1), last_modified=1), steps_version(uid(2), last_modified=1)))
	apply_batch(OWNER, batch(Deletion(uid(2), observed_at_ms=5)))
	apply_batch(OWNER + 1, batch(steps_version(uid(3), last_modified=1)))

	assert _export(tmp_path, Profile.RAW, RecordType.STEPS).count("\n") == 2


def test_start_after_end_is_refused(tmp_path: Path):
	with pytest.raises(ValueError, match="after end"):
		_export(tmp_path, Profile.RAW, RecordType.STEPS, start=date(2026, 2, 2), end=date(2026, 2, 1))


# ── command ──────────────────────────────────────────────────


def test_the_command_writes_one_file_per_type(tmp_path: Path):
	user = create_users()[0]
	apply_batch(user.pk, batch(steps_version(uid(1), last_modified=1)))

	call_command("export_health", user=user.get_username(), profile="raw", output_dir=tmp_path)

	assert sorted(path.name for path in tmp_path.iterdir()) == [
		"raw-resting_heart_rate.csv",
		"raw-sleep_session.csv",
		"raw-steps.csv",
	]
	assert (tmp_path / "raw-steps.csv").read_text(encoding="utf-8").count("\n") == 2


def test_the_command_takes_a_type_list(tmp_path: Path):
	user = create_users()[0]

	call_command("export_health", user=user.get_username(), profile="daily", types="steps,steps", output_dir=tmp_path)

	assert [path.name for path in tmp_path.iterdir()] == ["daily-steps.csv"]


@pytest.mark.parametrize(
	("options", "message"),
	[
		({"user": "nobody"}, "No user named"),
		({"types": "steps,heart_rate"}, "Unknown types"),
		({"types": ","}, "Unknown types"),
		({"start": "2026-13-01"}, "--start must be a date"),
		({"tz": "Mars/Olympus"}, "Unknown time zone"),
		({"start": "2026-02-02", "end": "2026-02-01"}, "after end"),
	],
)
def test_the_command_refuses_bad_options(tmp_path: Path, options: dict[str, str], message: str):
	user = create_users()[0]

	with pytest.raises(CommandError, match=message):
		call_command(
			"export_health", **{"user": user.get_username(), "profile": "raw", "output_dir": tmp_path, **options}
		)
