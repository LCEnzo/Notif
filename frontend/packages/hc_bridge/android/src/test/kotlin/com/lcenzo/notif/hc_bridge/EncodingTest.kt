package com.lcenzo.notif.hc_bridge

import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.metadata.DataOrigin
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.testing.populatedWithTestValues
import java.time.Instant
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class EncodingTest {
    // The ingest contract's enum values (docs/architecture/health-ingest.md).
    private val contractRecordingMethods = setOf("unknown", "actively_recorded", "automatically_recorded", "manual_entry")
    private val contractDeviceTypes =
        setOf(
            "unknown",
            "watch",
            "phone",
            "scale",
            "ring",
            "head_mounted",
            "fitness_band",
            "chest_strap",
            "smart_display",
        )
    private val contractSleepStages =
        setOf("unknown", "awake", "sleeping", "out_of_bed", "light", "deep", "rem", "awake_in_bed")

    @Test
    fun recordingMethodsMapToContractNames() {
        assertEquals("unknown", recordingMethodName(Metadata.RECORDING_METHOD_UNKNOWN))
        assertEquals("actively_recorded", recordingMethodName(Metadata.RECORDING_METHOD_ACTIVELY_RECORDED))
        assertEquals("automatically_recorded", recordingMethodName(Metadata.RECORDING_METHOD_AUTOMATICALLY_RECORDED))
        assertEquals("manual_entry", recordingMethodName(Metadata.RECORDING_METHOD_MANUAL_ENTRY))
        assertEquals(contractRecordingMethods, (-1..20).map(::recordingMethodName).toSet())
    }

    @Test
    fun deviceTypesMapToContractNames() {
        assertEquals("watch", deviceTypeName(Device.TYPE_WATCH))
        assertEquals("phone", deviceTypeName(Device.TYPE_PHONE))
        assertEquals("scale", deviceTypeName(Device.TYPE_SCALE))
        assertEquals("ring", deviceTypeName(Device.TYPE_RING))
        assertEquals("head_mounted", deviceTypeName(Device.TYPE_HEAD_MOUNTED))
        assertEquals("fitness_band", deviceTypeName(Device.TYPE_FITNESS_BAND))
        assertEquals("chest_strap", deviceTypeName(Device.TYPE_CHEST_STRAP))
        assertEquals("smart_display", deviceTypeName(Device.TYPE_SMART_DISPLAY))
        assertEquals("unknown", deviceTypeName(Device.TYPE_UNKNOWN))
        assertEquals(contractDeviceTypes, (-1..40).map(::deviceTypeName).toSet())
    }

    @Test
    fun sleepStagesMapToContractNames() {
        assertEquals("awake", sleepStageName(SleepSessionRecord.STAGE_TYPE_AWAKE))
        assertEquals("sleeping", sleepStageName(SleepSessionRecord.STAGE_TYPE_SLEEPING))
        assertEquals("out_of_bed", sleepStageName(SleepSessionRecord.STAGE_TYPE_OUT_OF_BED))
        assertEquals("light", sleepStageName(SleepSessionRecord.STAGE_TYPE_LIGHT))
        assertEquals("deep", sleepStageName(SleepSessionRecord.STAGE_TYPE_DEEP))
        assertEquals("rem", sleepStageName(SleepSessionRecord.STAGE_TYPE_REM))
        assertEquals("awake_in_bed", sleepStageName(SleepSessionRecord.STAGE_TYPE_AWAKE_IN_BED))
        assertEquals("unknown", sleepStageName(SleepSessionRecord.STAGE_TYPE_UNKNOWN))
        assertEquals(contractSleepStages, (-1..40).map(::sleepStageName).toSet())
    }

    @Test
    fun unknownConstantsBeyondTodaysRangeMapToUnknown() {
        for (value in listOf(Int.MIN_VALUE, -1, 99, 1_000, Int.MAX_VALUE)) {
            assertEquals("unknown", recordingMethodName(value))
            assertEquals("unknown", deviceTypeName(value))
            assertEquals("unknown", sleepStageName(value))
        }
    }

    @Test
    fun encodesStepsWithMetadataDeviceAndOffsets() {
        val record =
            StepsRecord(
                startTime = Instant.ofEpochMilli(1_700_000_000_123),
                startZoneOffset = ZoneOffset.ofHours(2),
                endTime = Instant.ofEpochMilli(1_700_000_060_456),
                endZoneOffset = ZoneOffset.ofHoursMinutes(-3, -30),
                count = 42,
                metadata =
                    Metadata.autoRecorded(Device(type = Device.TYPE_WATCH, manufacturer = "Acme", model = "W1"))
                        .populatedWithTestValues(
                            id = "6f1c2a3b-0000-4000-8000-000000000001",
                            dataOrigin = DataOrigin("com.example.fit"),
                            lastModifiedTime = Instant.ofEpochMilli(1_700_000_100_000),
                        ),
            )

        val encoded = encodeRecord(record)!!

        assertEquals("steps", encoded["type"])
        assertEquals("6f1c2a3b-0000-4000-8000-000000000001", encoded["id"])
        assertEquals("com.example.fit", encoded["data_origin"])
        assertEquals(1_700_000_100_000L, encoded["last_modified_ms"])
        assertEquals("automatically_recorded", encoded["recording_method"])
        assertEquals(mapOf("type" to "watch", "manufacturer" to "Acme", "model" to "W1"), encoded["device"])
        assertEquals(1_700_000_000_123L, encoded["start_ms"])
        assertEquals(7_200, encoded["start_offset_s"])
        assertEquals(1_700_000_060_456L, encoded["end_ms"])
        assertEquals(-12_600, encoded["end_offset_s"])
        assertEquals(42L, encoded["count"])
    }

    @Test
    fun encodesRestingHeartRateWithoutOffsetOrDevice() {
        val record =
            RestingHeartRateRecord(
                time = Instant.ofEpochMilli(1_700_000_000_000),
                zoneOffset = null,
                beatsPerMinute = 51,
                metadata =
                    Metadata.manualEntry()
                        .populatedWithTestValues(
                            id = "6f1c2a3b-0000-4000-8000-000000000002",
                            dataOrigin = DataOrigin("com.example.hr"),
                            lastModifiedTime = Instant.ofEpochMilli(1_700_000_000_500),
                        ),
            )

        val encoded = encodeRecord(record)!!

        assertEquals("resting_heart_rate", encoded["type"])
        assertEquals("manual_entry", encoded["recording_method"])
        assertNull(encoded["device"])
        assertEquals(1_700_000_000_000L, encoded["time_ms"])
        assertNull(encoded["offset_s"])
        assertEquals(51L, encoded["beats_per_minute"])
    }

    @Test
    fun encodesSleepSessionWithStagesTitleAndNotes() {
        val start = Instant.ofEpochMilli(1_700_000_000_000)
        val record =
            SleepSessionRecord(
                startTime = start,
                startZoneOffset = ZoneOffset.UTC,
                endTime = start.plusSeconds(8 * 3_600),
                endZoneOffset = ZoneOffset.UTC,
                metadata =
                    Metadata.unknownRecordingMethod()
                        .populatedWithTestValues(
                            id = "6f1c2a3b-0000-4000-8000-000000000003",
                            dataOrigin = DataOrigin("com.example.sleep"),
                            lastModifiedTime = start.plusSeconds(9 * 3_600),
                        ),
                title = "Night",
                notes = null,
                stages =
                    listOf(
                        SleepSessionRecord.Stage(start, start.plusSeconds(3_600), SleepSessionRecord.STAGE_TYPE_LIGHT),
                        SleepSessionRecord.Stage(
                            start.plusSeconds(3_600),
                            start.plusSeconds(7_200),
                            SleepSessionRecord.STAGE_TYPE_DEEP,
                        ),
                    ),
            )

        val encoded = encodeRecord(record)!!

        assertEquals("sleep_session", encoded["type"])
        assertEquals("unknown", encoded["recording_method"])
        assertEquals("Night", encoded["title"])
        assertNull(encoded["notes"])
        assertEquals(0, encoded["start_offset_s"])
        assertEquals(
            listOf(
                mapOf("start_ms" to 1_700_000_000_000L, "end_ms" to 1_700_003_600_000L, "stage" to "light"),
                mapOf("start_ms" to 1_700_003_600_000L, "end_ms" to 1_700_007_200_000L, "stage" to "deep"),
            ),
            encoded["stages"],
        )
    }
}
