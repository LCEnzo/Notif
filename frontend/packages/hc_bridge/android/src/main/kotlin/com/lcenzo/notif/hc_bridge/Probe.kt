package com.lcenzo.notif.hc_bridge

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.aggregate.AggregateMetric
import androidx.health.connect.client.feature.ExperimentalMindfulnessSessionApi
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.BasalBodyTemperatureRecord
import androidx.health.connect.client.records.BasalMetabolicRateRecord
import androidx.health.connect.client.records.BloodGlucoseRecord
import androidx.health.connect.client.records.BloodPressureRecord
import androidx.health.connect.client.records.BodyFatRecord
import androidx.health.connect.client.records.BodyTemperatureRecord
import androidx.health.connect.client.records.BodyWaterMassRecord
import androidx.health.connect.client.records.BoneMassRecord
import androidx.health.connect.client.records.CervicalMucusRecord
import androidx.health.connect.client.records.CyclingPedalingCadenceRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ElevationGainedRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.FloorsClimbedRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.HeightRecord
import androidx.health.connect.client.records.HydrationRecord
import androidx.health.connect.client.records.IntermenstrualBleedingRecord
import androidx.health.connect.client.records.LeanBodyMassRecord
import androidx.health.connect.client.records.MenstruationFlowRecord
import androidx.health.connect.client.records.MenstruationPeriodRecord
import androidx.health.connect.client.records.MindfulnessSessionRecord
import androidx.health.connect.client.records.NutritionRecord
import androidx.health.connect.client.records.OvulationTestRecord
import androidx.health.connect.client.records.OxygenSaturationRecord
import androidx.health.connect.client.records.PlannedExerciseSessionRecord
import androidx.health.connect.client.records.PowerRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.RespiratoryRateRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SexualActivityRecord
import androidx.health.connect.client.records.SkinTemperatureRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.SpeedRecord
import androidx.health.connect.client.records.StepsCadenceRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.records.Vo2MaxRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.records.WheelchairPushesRecord
import androidx.health.connect.client.request.AggregateGroupByPeriodRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Clock
import java.time.Instant
import java.time.LocalDateTime
import java.time.Period
import java.util.Locale
import kotlin.reflect.KClass

/** First local month the coverage probe asks about. */
internal val COVERAGE_FLOOR: LocalDateTime = LocalDateTime.of(2015, 1, 1, 0, 0)

/** Pages of 1,000 the records path reads per type before reporting "at least". */
internal const val PROBE_MAX_PAGES = 10
internal const val PROBE_PAGE_SIZE = 1_000

/**
 * Every HC record type the coverage probe can look at. [metric] is set where an
 * aggregate shows presence per month cheaply and faithfully: computed by the
 * platform on every SDK extension, never synthesized from other data (total
 * and basal calories are, from weight and height). The rest are counted with
 * bounded record reads.
 */
@OptIn(ExperimentalMindfulnessSessionApi::class)
internal enum class ProbeKind(
    val wire: String,
    val recordClass: KClass<out Record>,
    val metric: AggregateMetric<*>? = null,
) {
    ACTIVE_CALORIES_BURNED(
        "active_calories_burned",
        ActiveCaloriesBurnedRecord::class,
        ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL,
    ),
    BASAL_BODY_TEMPERATURE("basal_body_temperature", BasalBodyTemperatureRecord::class),
    BASAL_METABOLIC_RATE("basal_metabolic_rate", BasalMetabolicRateRecord::class),
    BLOOD_GLUCOSE("blood_glucose", BloodGlucoseRecord::class),
    BLOOD_PRESSURE("blood_pressure", BloodPressureRecord::class),
    BODY_FAT("body_fat", BodyFatRecord::class),
    BODY_TEMPERATURE("body_temperature", BodyTemperatureRecord::class),
    BODY_WATER_MASS("body_water_mass", BodyWaterMassRecord::class),
    BONE_MASS("bone_mass", BoneMassRecord::class),
    CERVICAL_MUCUS("cervical_mucus", CervicalMucusRecord::class),
    CYCLING_PEDALING_CADENCE("cycling_pedaling_cadence", CyclingPedalingCadenceRecord::class),
    DISTANCE("distance", DistanceRecord::class, DistanceRecord.DISTANCE_TOTAL),
    ELEVATION_GAINED("elevation_gained", ElevationGainedRecord::class, ElevationGainedRecord.ELEVATION_GAINED_TOTAL),
    EXERCISE_SESSION("exercise_session", ExerciseSessionRecord::class, ExerciseSessionRecord.EXERCISE_DURATION_TOTAL),
    FLOORS_CLIMBED("floors_climbed", FloorsClimbedRecord::class, FloorsClimbedRecord.FLOORS_CLIMBED_TOTAL),
    HEART_RATE("heart_rate", HeartRateRecord::class, HeartRateRecord.MEASUREMENTS_COUNT),
    HEART_RATE_VARIABILITY_RMSSD("heart_rate_variability_rmssd", HeartRateVariabilityRmssdRecord::class),
    HEIGHT("height", HeightRecord::class, HeightRecord.HEIGHT_AVG),
    HYDRATION("hydration", HydrationRecord::class, HydrationRecord.VOLUME_TOTAL),
    INTERMENSTRUAL_BLEEDING("intermenstrual_bleeding", IntermenstrualBleedingRecord::class),
    LEAN_BODY_MASS("lean_body_mass", LeanBodyMassRecord::class),
    MENSTRUATION_FLOW("menstruation_flow", MenstruationFlowRecord::class),
    MENSTRUATION_PERIOD("menstruation_period", MenstruationPeriodRecord::class),
    MINDFULNESS_SESSION("mindfulness_session", MindfulnessSessionRecord::class),
    NUTRITION("nutrition", NutritionRecord::class),
    OVULATION_TEST("ovulation_test", OvulationTestRecord::class),
    OXYGEN_SATURATION("oxygen_saturation", OxygenSaturationRecord::class),
    PLANNED_EXERCISE_SESSION("planned_exercise_session", PlannedExerciseSessionRecord::class),
    POWER("power", PowerRecord::class, PowerRecord.POWER_AVG),
    RESPIRATORY_RATE("respiratory_rate", RespiratoryRateRecord::class),
    RESTING_HEART_RATE("resting_heart_rate", RestingHeartRateRecord::class, RestingHeartRateRecord.BPM_AVG),
    SEXUAL_ACTIVITY("sexual_activity", SexualActivityRecord::class),
    SKIN_TEMPERATURE("skin_temperature", SkinTemperatureRecord::class),
    SLEEP_SESSION("sleep_session", SleepSessionRecord::class, SleepSessionRecord.SLEEP_DURATION_TOTAL),
    SPEED("speed", SpeedRecord::class),
    STEPS("steps", StepsRecord::class, StepsRecord.COUNT_TOTAL),
    STEPS_CADENCE("steps_cadence", StepsCadenceRecord::class),
    TOTAL_CALORIES_BURNED("total_calories_burned", TotalCaloriesBurnedRecord::class),
    VO2_MAX("vo2_max", Vo2MaxRecord::class),
    WEIGHT("weight", WeightRecord::class, WeightRecord.WEIGHT_AVG),
    WHEELCHAIR_PUSHES("wheelchair_pushes", WheelchairPushesRecord::class, WheelchairPushesRecord.COUNT_TOTAL);

    companion object {
        fun fromWire(wire: String): ProbeKind =
            entries.firstOrNull { it.wire == wire } ?: throw BridgeArgumentException("unknown data type \"$wire\"")
    }
}

/**
 * Which of [kinds] hold data. Aggregate kinds: the local months with a value,
 * from one `aggregateGroupByPeriod` per calendar year for all of them at once.
 * Record kinds: a count of up to [PROBE_MAX_PAGES] pages over all time.
 */
internal suspend fun probeCoverage(
    client: HealthConnectClient,
    clock: Clock,
    kinds: Set<ProbeKind>,
): Map<String, Any?> {
    if (kinds.isEmpty()) throw BridgeArgumentException("types must not be empty")
    val computedAtMs = clock.millis()
    val now = LocalDateTime.now(clock)
    val aggregated = kinds.filter { it.metric != null }
    val months = aggregated.associateWith { mutableListOf<LocalDateTime>() }
    var yearStart = COVERAGE_FLOOR
    while (aggregated.isNotEmpty() && yearStart.isBefore(now)) {
        val nextYear = yearStart.plusYears(1)
        val groups =
            client.aggregateGroupByPeriod(
                AggregateGroupByPeriodRequest(
                    metrics = aggregated.mapNotNull { it.metric }.toSet(),
                    timeRangeFilter = TimeRangeFilter.between(yearStart, minOf(nextYear, now)),
                    timeRangeSlicer = Period.ofMonths(1),
                )
            )
        for (group in groups) {
            for (kind in aggregated) {
                if (kind.metric!! in group.result) months.getValue(kind) += group.startTime
            }
        }
        yearStart = nextYear
    }

    val types =
        kinds.map { kind ->
            val seen = months[kind]
            if (seen != null) {
                val first = seen.minOrNull()
                val last = seen.maxOrNull()
                mapOf(
                    "type" to kind.wire,
                    "method" to "aggregate",
                    "months" to seen.size,
                    "first_month" to first?.let { String.format(Locale.ROOT, "%04d-%02d", it.year, it.monthValue) },
                    "last_month" to last?.let { String.format(Locale.ROOT, "%04d-%02d", it.year, it.monthValue) },
                )
            } else {
                val (count, capped) = countRecords(client, kind, Instant.ofEpochMilli(computedAtMs))
                mapOf("type" to kind.wire, "method" to "records", "records" to count, "capped" to capped)
            }
        }
    return mapOf("computed_at_ms" to computedAtMs, "types" to types)
}

private suspend fun countRecords(client: HealthConnectClient, kind: ProbeKind, now: Instant): Pair<Int, Boolean> {
    val range = TimeRangeFilter.between(Instant.parse("2015-01-01T00:00:00Z"), now)
    var count = 0
    var token: String? = null
    for (page in 1..PROBE_MAX_PAGES) {
        val response =
            client.readRecords(
                ReadRecordsRequest(
                    recordType = kind.recordClass,
                    timeRangeFilter = range,
                    pageSize = PROBE_PAGE_SIZE,
                    pageToken = token,
                )
            )
        count += response.records.size
        token = response.pageToken?.takeIf { it.isNotEmpty() } ?: return count to false
    }
    return count to true
}
