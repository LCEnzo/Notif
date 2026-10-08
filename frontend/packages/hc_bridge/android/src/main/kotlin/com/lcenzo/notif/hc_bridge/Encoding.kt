package com.lcenzo.notif.hc_bridge

import androidx.health.connect.client.aggregate.AggregateMetric
import androidx.health.connect.client.aggregate.AggregationResult
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.records.metadata.Metadata
import kotlin.reflect.KClass

/** The record types Notif reads; [wire] is the ingest contract's list key. */
internal enum class RecordKind(val wire: String, val recordClass: KClass<out Record>) {
    STEPS("steps", StepsRecord::class),
    RESTING_HEART_RATE("resting_heart_rate", RestingHeartRateRecord::class),
    SLEEP_SESSION("sleep_session", SleepSessionRecord::class);

    companion object {
        fun fromWire(wire: String): RecordKind =
            entries.firstOrNull { it.wire == wire }
                ?: throw BridgeArgumentException("unknown record type \"$wire\"")

        fun of(record: Record): RecordKind? = entries.firstOrNull { it.recordClass.isInstance(record) }
    }
}

/** The hourly aggregates Notif uploads; [wire] is the contract's `metric`. */
internal enum class AggregateKind(val wire: String, val metric: AggregateMetric<*>) {
    STEPS_COUNT_TOTAL("steps_count_total", StepsRecord.COUNT_TOTAL),
    SLEEP_DURATION_TOTAL("sleep_duration_total", SleepSessionRecord.SLEEP_DURATION_TOTAL);

    /** Steps, or milliseconds of sleep; null when HC returned no value for this metric. */
    fun valueIn(result: AggregationResult): Long? =
        when (this) {
            STEPS_COUNT_TOTAL -> result[StepsRecord.COUNT_TOTAL]
            SLEEP_DURATION_TOTAL -> result[SleepSessionRecord.SLEEP_DURATION_TOTAL]?.toMillis()
        }

    companion object {
        fun fromWire(wire: String): AggregateKind =
            entries.firstOrNull { it.wire == wire }
                ?: throw BridgeArgumentException("unknown aggregate metric \"$wire\"")
    }
}

// HC adds constants over time. An unknown one maps to "unknown", as the ingest
// contract asks, so a newer HC never stalls a sync.

internal fun recordingMethodName(value: Int): String =
    when (value) {
        Metadata.RECORDING_METHOD_ACTIVELY_RECORDED -> "actively_recorded"
        Metadata.RECORDING_METHOD_AUTOMATICALLY_RECORDED -> "automatically_recorded"
        Metadata.RECORDING_METHOD_MANUAL_ENTRY -> "manual_entry"
        else -> "unknown"
    }

internal fun deviceTypeName(value: Int): String =
    when (value) {
        Device.TYPE_WATCH -> "watch"
        Device.TYPE_PHONE -> "phone"
        Device.TYPE_SCALE -> "scale"
        Device.TYPE_RING -> "ring"
        Device.TYPE_HEAD_MOUNTED -> "head_mounted"
        Device.TYPE_FITNESS_BAND -> "fitness_band"
        Device.TYPE_CHEST_STRAP -> "chest_strap"
        Device.TYPE_SMART_DISPLAY -> "smart_display"
        else -> "unknown"
    }

internal fun sleepStageName(value: Int): String =
    when (value) {
        SleepSessionRecord.STAGE_TYPE_AWAKE -> "awake"
        SleepSessionRecord.STAGE_TYPE_SLEEPING -> "sleeping"
        SleepSessionRecord.STAGE_TYPE_OUT_OF_BED -> "out_of_bed"
        SleepSessionRecord.STAGE_TYPE_LIGHT -> "light"
        SleepSessionRecord.STAGE_TYPE_DEEP -> "deep"
        SleepSessionRecord.STAGE_TYPE_REM -> "rem"
        SleepSessionRecord.STAGE_TYPE_AWAKE_IN_BED -> "awake_in_bed"
        else -> "unknown"
    }

/** The channel form of [record], or null for a type Notif does not read. */
internal fun encodeRecord(record: Record): Map<String, Any?>? {
    val kind = RecordKind.of(record) ?: return null
    val metadata = record.metadata
    val common =
        mapOf(
            "type" to kind.wire,
            "id" to metadata.id,
            "data_origin" to metadata.dataOrigin.packageName,
            "last_modified_ms" to metadata.lastModifiedTime.toEpochMilli(),
            "recording_method" to recordingMethodName(metadata.recordingMethod),
            "device" to metadata.device?.let(::encodeDevice),
        )
    val specific: Map<String, Any?> =
        when (record) {
            is StepsRecord ->
                mapOf(
                    "start_ms" to record.startTime.toEpochMilli(),
                    "start_offset_s" to record.startZoneOffset?.totalSeconds,
                    "end_ms" to record.endTime.toEpochMilli(),
                    "end_offset_s" to record.endZoneOffset?.totalSeconds,
                    "count" to record.count,
                )
            is RestingHeartRateRecord ->
                mapOf(
                    "time_ms" to record.time.toEpochMilli(),
                    "offset_s" to record.zoneOffset?.totalSeconds,
                    "beats_per_minute" to record.beatsPerMinute,
                )
            is SleepSessionRecord ->
                mapOf(
                    "start_ms" to record.startTime.toEpochMilli(),
                    "start_offset_s" to record.startZoneOffset?.totalSeconds,
                    "end_ms" to record.endTime.toEpochMilli(),
                    "end_offset_s" to record.endZoneOffset?.totalSeconds,
                    "title" to record.title,
                    "notes" to record.notes,
                    "stages" to
                        record.stages.map {
                            mapOf(
                                "start_ms" to it.startTime.toEpochMilli(),
                                "end_ms" to it.endTime.toEpochMilli(),
                                "stage" to sleepStageName(it.stage),
                            )
                        },
                )
            else -> return null
        }
    return common + specific
}

private fun encodeDevice(device: Device): Map<String, Any?> =
    mapOf(
        "type" to deviceTypeName(device.type),
        "manufacturer" to device.manufacturer,
        "model" to device.model,
    )
