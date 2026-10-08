package com.lcenzo.notif.hc_bridge

import androidx.health.connect.client.aggregate.AggregationResultGroupedByDuration
import androidx.health.connect.client.aggregate.AggregationResultGroupedByPeriod
import androidx.health.connect.client.changes.DeletionChange
import androidx.health.connect.client.changes.UpsertionChange
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.metadata.DataOrigin
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.response.ChangesResponse
import androidx.health.connect.client.testing.AggregationResult
import androidx.health.connect.client.testing.FakeHealthConnectClient
import androidx.health.connect.client.testing.FakePermissionController
import androidx.health.connect.client.testing.populatedWithTestValues
import androidx.health.connect.client.testing.stubs.Stub
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class HcReaderTest {
    private val now = Instant.parse("2026-10-08T12:34:56Z")
    private val clock = Clock.fixed(now, ZoneOffset.UTC)
    private val permissions = FakePermissionController(grantAll = false)
    private val client = FakeHealthConnectClient(clock = clock, permissionController = permissions)
    private val reader = HcReader(client, clock, upsertsWinWithinPage = false)

    private fun steps(startMinute: Long, count: Long = 10, clientId: String? = null): StepsRecord {
        val start = now.minusSeconds(3 * 86_400).plusSeconds(startMinute * 60)
        return StepsRecord(
            startTime = start,
            startZoneOffset = ZoneOffset.UTC,
            endTime = start.plusSeconds(60),
            endZoneOffset = ZoneOffset.UTC,
            count = count,
            metadata = if (clientId == null) Metadata.manualEntry() else Metadata.manualEntry(clientRecordId = clientId),
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun records(page: Map<String, Any?>) = page["records"] as List<Map<String, Any?>>

    @Suppress("UNCHECKED_CAST")
    private fun changes(page: Map<String, Any?>) = page["changes"] as List<Map<String, Any?>>

    @Test
    fun statusReportsGrantedPermissionsSortedAndFeatures() = runTest {
        permissions.grantPermissions(
            setOf(HealthPermission.PERMISSION_READ_HEALTH_DATA_HISTORY, HealthPermission.getReadPermission(StepsRecord::class))
        )

        val status = reader.status()

        assertEquals("available", status["sdk"])
        assertEquals(
            listOf("android.permission.health.READ_HEALTH_DATA_HISTORY", "android.permission.health.READ_STEPS"),
            status["granted"],
        )
        // The fake implements no features; a real device answers per its HC version.
        assertEquals("unavailable", status["history"])
        assertEquals("unavailable", status["background"])
    }

    @Test
    fun readRecordsPagesUntilTheTokenRunsOut() = runTest {
        client.insertRecords((0L until 5L).map { steps(it) })
        val start = now.minusSeconds(7 * 86_400).toEpochMilli()
        val end = now.toEpochMilli()

        val seen = mutableListOf<Map<String, Any?>>()
        var token: String? = null
        var pages = 0
        do {
            val page = reader.readRecords(RecordKind.STEPS, start, end, token, pageSize = 2)
            seen += records(page)
            token = page["next_page_token"] as String?
            pages++
        } while (token != null && pages < 10)

        assertEquals(3, pages)
        assertEquals(5, seen.size)
        assertEquals(5, seen.map { it["id"] }.toSet().size)
        assertTrue(seen.all { it["type"] == "steps" && it["data_origin"] == FakeHealthConnectClient.DEFAULT_PACKAGE_NAME })
        assertTrue(seen.all { it["last_modified_ms"] == now.toEpochMilli() })
    }

    @Test
    fun readRecordsRefusesEmptyRangesAndPageSizes() {
        val t = now.toEpochMilli()
        assertRefused { reader.readRecords(RecordKind.STEPS, t, t, null, 10) }
        assertRefused { reader.readRecords(RecordKind.STEPS, t, t - 1, null, 10) }
        assertRefused { reader.readRecords(RecordKind.STEPS, 0, t, null, 0) }
        assertRefused { reader.readRecords(RecordKind.STEPS, 0, t, null, MAX_PAGE_SIZE + 1) }
    }

    @Test
    fun aggregateHourlyKeepsOnlyHoursWithAValue() = runTest {
        val start = Instant.parse("2026-10-07T00:00:00Z")
        val origin = DataOrigin("com.example.b")
        client.overrides.aggregateGroupByDuration = Stub {
                listOf(
                    AggregationResultGroupedByDuration(
                        AggregationResult(
                            dataOrigins = setOf(origin, DataOrigin("com.example.a")),
                            metrics = mapOf(SleepSessionRecord.SLEEP_DURATION_TOTAL to Duration.ofMinutes(42)),
                        ),
                        start,
                        start.plusSeconds(3_600),
                        ZoneOffset.UTC,
                    ),
                    // A slice HC answered for without this metric: not a bucket.
                    AggregationResultGroupedByDuration(
                        AggregationResult(dataOrigins = setOf(origin)),
                        start.plusSeconds(3_600),
                        start.plusSeconds(7_200),
                        ZoneOffset.UTC,
                    ),
                )
        }

        val window =
            reader.aggregateHourly(
                AggregateKind.SLEEP_DURATION_TOTAL,
                start.toEpochMilli(),
                start.plusSeconds(3 * 3_600).toEpochMilli(),
            )

        assertEquals("sleep_duration_total", window["metric"])
        assertEquals(now.toEpochMilli(), window["computed_at_ms"])
        assertEquals(
            listOf(
                mapOf(
                    "start_ms" to start.toEpochMilli(),
                    "end_ms" to start.plusSeconds(3_600).toEpochMilli(),
                    "value" to 42L * 60_000L,
                    "data_origins" to listOf("com.example.a", "com.example.b"),
                )
            ),
            window["buckets"],
        )
    }

    @Test
    fun aggregateHourlyRefusesUnalignedOrOverlongWindows() {
        val hour = Instant.parse("2026-10-07T00:00:00Z").toEpochMilli()
        assertRefused { reader.aggregateHourly(AggregateKind.STEPS_COUNT_TOTAL, hour + 1, hour + HOUR_MS) }
        assertRefused {
            reader.aggregateHourly(AggregateKind.STEPS_COUNT_TOTAL, hour, hour + (MAX_WINDOW_HOURS + 1) * HOUR_MS)
        }
    }

    @Test
    fun changesReportUpsertsDeletionsAndPaging() = runTest {
        val token = reader.changesToken(setOf(RecordKind.STEPS))
        val ids = client.insertRecords((0L until 3L).map { steps(it) }).recordIdsList
        client.deleteRecords(StepsRecord::class, recordIdsList = listOf(ids[0]), clientRecordIdsList = emptyList())
        client.pageSizeGetChanges = 2

        val first = reader.changes(token)
        assertEquals(true, first["has_more"])
        assertEquals(false, first["token_expired"])
        assertEquals(now.toEpochMilli(), first["observed_at_ms"])
        val second = reader.changes(first["next_token"] as String)
        assertEquals(false, second["has_more"])

        val all = changes(first) + changes(second)
        @Suppress("UNCHECKED_CAST")
        val upserted = all.filter { it["kind"] == "upsert" }.map { (it["record"] as Map<String, Any?>)["id"] }
        assertEquals(setOf(ids[1], ids[2]), upserted.toSet())
        assertEquals(listOf(ids[0]), all.filter { it["kind"] == "deletion" }.map { it["id"] })
    }

    @Test
    fun anExpiredTokenIsReportedNotThrown() = runTest {
        val token = reader.changesToken(setOf(RecordKind.STEPS, RecordKind.SLEEP_SESSION))
        client.expireToken(token)

        assertEquals(true, reader.changes(token)["token_expired"])
    }

    @Test
    fun aDeletedThenRewrittenRecordEndsWithItsUpsertInChangeOrder() = runTest {
        val token = reader.changesToken(setOf(RecordKind.STEPS))
        val id = client.insertRecords(listOf(steps(0, clientId = "walk-1"))).recordIdsList.single()
        client.deleteRecords(StepsRecord::class, recordIdsList = listOf(id), clientRecordIdsList = emptyList())
        client.insertRecords(listOf(steps(0, count = 99, clientId = "walk-1")))

        val page = changes(reader.changes(token))

        assertEquals(listOf("deletion", "upsert"), page.map { it["kind"] })
        @Suppress("UNCHECKED_CAST")
        assertEquals(99L, (page.last()["record"] as Map<String, Any?>)["count"])
    }

    @Test
    fun onTheUpsertsFirstLayoutAnUpsertCancelsItsIdsDeletion() = runTest {
        val rewritten =
            steps(5).let {
                StepsRecord(
                    it.startTime,
                    it.startZoneOffset,
                    it.endTime,
                    it.endZoneOffset,
                    it.count,
                    Metadata.manualEntry().populatedWithTestValues(id = "x-1", dataOrigin = DataOrigin("com.example")),
                )
            }
        client.overrides.getChanges = Stub {
            ChangesResponse(
                changes = listOf(UpsertionChange(rewritten), DeletionChange("x-1"), DeletionChange("y-2")),
                nextChangesToken = "next",
                hasMore = false,
                changesTokenExpired = false,
            )
        }

        val platform = changes(HcReader(client, clock, upsertsWinWithinPage = true).changes("t"))
        val ordered = changes(reader.changes("t"))

        assertEquals(listOf("upsert", "deletion"), platform.map { it["kind"] })
        assertEquals("y-2", platform.last()["id"])
        assertEquals(listOf("upsert", "deletion", "deletion"), ordered.map { it["kind"] })
    }

    @Test
    fun coverageProbeAsksOneYearAtATimeAndSkipsEmptyMonths() = runTest {
        var calls = 0
        val responses =
            ArrayDeque(
                listOf(
                    emptyList(),
                    listOf(
                        AggregationResultGroupedByPeriod(
                            AggregationResult(metrics = mapOf(StepsRecord.COUNT_TOTAL to 12_345L)),
                            LocalDateTime.of(2016, 6, 1, 0, 0),
                            LocalDateTime.of(2016, 7, 1, 0, 0),
                        )
                    ),
                )
            )
        client.overrides.aggregateGroupByPeriod = Stub {
            calls++
            responses.removeFirstOrNull()
                ?: listOf(
                    AggregationResultGroupedByPeriod(
                        AggregationResult(
                            metrics =
                                mapOf(
                                    RestingHeartRateRecord.BPM_AVG to 55L,
                                    SleepSessionRecord.SLEEP_DURATION_TOTAL to Duration.ofHours(7),
                                )
                        ),
                        LocalDateTime.of(2026, 9, 1, 0, 0),
                        LocalDateTime.of(2026, 10, 1, 0, 0),
                    ),
                    AggregationResultGroupedByPeriod(
                        AggregationResult(),
                        LocalDateTime.of(2026, 10, 1, 0, 0),
                        LocalDateTime.of(2026, 10, 8, 12, 0),
                    ),
                )
        }

        val probe =
            reader.coverageProbe(setOf(RecordKind.STEPS, RecordKind.RESTING_HEART_RATE, RecordKind.SLEEP_SESSION))

        // 2015 through 2026 inclusive.
        assertEquals(12, calls)
        @Suppress("UNCHECKED_CAST")
        val months = probe["months"] as List<Map<String, Any?>>
        val june2016 = months.first()
        assertEquals(2016, june2016["year"])
        assertEquals(6, june2016["month"])
        assertEquals(12_345L, june2016["steps_total"])
        assertNull(june2016["sleep_ms"])
        val september2026 = months.first { it["year"] == 2026 && it["month"] == 9 }
        assertEquals(55L, september2026["resting_hr_avg"])
        assertEquals(7L * 3_600_000L, september2026["sleep_ms"])
        // 2017..2025 echo the September answer; October 2026 had no metric and is absent.
        assertFalse(months.any { it["month"] == 10 })
    }

    @Test
    fun coverageProbeLeavesOutTypesItWasNotAskedFor() = runTest {
        client.overrides.aggregateGroupByPeriod = Stub {
            listOf(
                AggregationResultGroupedByPeriod(
                    AggregationResult(metrics = mapOf(StepsRecord.COUNT_TOTAL to 1L)),
                    LocalDateTime.of(2020, 1, 1, 0, 0),
                    LocalDateTime.of(2020, 2, 1, 0, 0),
                )
            )
        }

        val probe = reader.coverageProbe(setOf(RecordKind.SLEEP_SESSION))

        @Suppress("UNCHECKED_CAST")
        assertTrue((probe["months"] as List<Map<String, Any?>>).isEmpty())
    }

    @Test
    fun emptyTypeSetsAreRefused() {
        assertRefused { reader.changesToken(emptySet()) }
        assertRefused { reader.coverageProbe(emptySet()) }
    }

    private fun assertRefused(block: suspend () -> Unit) {
        assertThrows(BridgeArgumentException::class.java) { runBlocking { block() } }
    }
}
