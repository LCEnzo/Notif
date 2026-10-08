package com.lcenzo.notif.hc_bridge

import androidx.health.connect.client.aggregate.AggregationResultGroupedByPeriod
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.BodyFatRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.AggregateGroupByPeriodRequest
import androidx.health.connect.client.testing.AggregationResult
import androidx.health.connect.client.testing.FakeHealthConnectClient
import androidx.health.connect.client.testing.stubs.Stub
import androidx.health.connect.client.units.Percentage
import java.io.File
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ProbeTest {
    private val now = Instant.parse("2026-10-08T12:34:56Z")
    private val clock = Clock.fixed(now, ZoneOffset.UTC)
    private val client = FakeHealthConnectClient(clock = clock)

    @Suppress("UNCHECKED_CAST")
    private fun types(probe: Map<String, Any?>) =
        (probe["types"] as List<Map<String, Any?>>).associateBy { it["type"] }

    private fun bodyFat(daysAgo: Long) =
        BodyFatRecord(
            time = now.minus(Duration.ofDays(daysAgo)),
            zoneOffset = ZoneOffset.UTC,
            percentage = Percentage(20.0),
            metadata = Metadata.manualEntry(),
        )

    @Test
    fun aggregateKindsShareOneRequestPerYearAndReportTheirMonths() = runTest {
        val requests = mutableListOf<AggregateGroupByPeriodRequest>()
        client.overrides.aggregateGroupByPeriod = Stub { request ->
            requests += request
            if (requests.size == 2) {
                // 2016: steps in June and August, sleep in August only.
                listOf(
                    AggregationResultGroupedByPeriod(
                        AggregationResult(metrics = mapOf(StepsRecord.COUNT_TOTAL to 10L)),
                        LocalDateTime.of(2016, 6, 1, 0, 0),
                        LocalDateTime.of(2016, 7, 1, 0, 0),
                    ),
                    AggregationResultGroupedByPeriod(
                        AggregationResult(
                            metrics =
                                mapOf(
                                    StepsRecord.COUNT_TOTAL to 5L,
                                    SleepSessionRecord.SLEEP_DURATION_TOTAL to Duration.ofHours(7),
                                )
                        ),
                        LocalDateTime.of(2016, 8, 1, 0, 0),
                        LocalDateTime.of(2016, 9, 1, 0, 0),
                    ),
                )
            } else {
                emptyList()
            }
        }

        val probe = probeCoverage(client, clock, setOf(ProbeKind.STEPS, ProbeKind.SLEEP_SESSION))

        // 2015 through 2026 inclusive, one request each, both metrics in each.
        assertEquals(12, requests.size)
        assertEquals(now.toEpochMilli(), probe["computed_at_ms"])
        val byType = types(probe)
        assertEquals(
            mapOf(
                "type" to "steps",
                "method" to "aggregate",
                "months" to 2,
                "first_month" to "2016-06",
                "last_month" to "2016-08",
            ),
            byType["steps"],
        )
        assertEquals(1, byType["sleep_session"]!!["months"])
        assertEquals("2016-08", byType["sleep_session"]!!["first_month"])
    }

    @Test
    fun recordKindsAreCountedWithoutAnyAggregateCall() = runTest {
        var aggregateCalls = 0
        client.overrides.aggregateGroupByPeriod = Stub {
            aggregateCalls++
            emptyList()
        }
        client.insertRecords((1L..3L).map(::bodyFat))

        val byType = types(probeCoverage(client, clock, setOf(ProbeKind.BODY_FAT, ProbeKind.VO2_MAX)))

        assertEquals(0, aggregateCalls)
        assertEquals(mapOf("type" to "body_fat", "method" to "records", "records" to 3, "capped" to false), byType["body_fat"])
        assertEquals(0, byType["vo2_max"]!!["records"])
    }

    @Test
    fun recordCountsStopAtThePageBound() = runTest {
        client.insertRecords((1L..(PROBE_MAX_PAGES * PROBE_PAGE_SIZE + 1).toLong()).map { bodyFat(it % 3_000) })

        val bodyFat = types(probeCoverage(client, clock, setOf(ProbeKind.BODY_FAT)))["body_fat"]!!

        assertEquals(PROBE_MAX_PAGES * PROBE_PAGE_SIZE, bodyFat["records"])
        assertEquals(true, bodyFat["capped"])
    }

    @Test
    fun anEmptyAggregateTypeReportsNoMonths() = runTest {
        client.overrides.aggregateGroupByPeriod = Stub { emptyList() }

        val steps = types(probeCoverage(client, clock, setOf(ProbeKind.STEPS)))["steps"]!!

        assertEquals(0, steps["months"])
        assertEquals(null, steps["first_month"])
    }

    /**
     * The three places that name the types must agree: [ProbeKind], the Dart
     * `HcDataType` table (wire name to permission) and the app manifest.
     */
    @Test
    fun dartTableAndManifestMatchConnectClient() {
        val dart = File("../lib/src/models.dart").readText()
        val dartPermissions =
            Regex("""^\s+\w+\(\s*'([a-z0-9_]+)',\s*'([A-Z0-9_]+)'""", RegexOption.MULTILINE)
                .findAll(dart)
                .associate { it.groupValues[1] to "android.permission.health.READ_" + it.groupValues[2] }
        val manifest = File("../../../android/app/src/main/AndroidManifest.xml").readText()
        val declared =
            Regex("""android:name="(android\.permission\.health\.READ_[A-Z0-9_]+)"""")
                .findAll(manifest)
                .map { it.groupValues[1] }
                .toSet()

        assertEquals(ProbeKind.entries.map { it.wire }.toSet(), dartPermissions.keys)
        for (kind in ProbeKind.entries) {
            val permission = HealthPermission.getReadPermission(kind.recordClass)
            assertEquals(kind.wire, permission, dartPermissions[kind.wire])
            assertTrue("$permission not in the manifest", permission in declared)
        }
        assertEquals(
            ProbeKind.entries.map { HealthPermission.getReadPermission(it.recordClass) }.toSet() +
                HealthPermission.PERMISSION_READ_HEALTH_DATA_HISTORY +
                HealthPermission.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND,
            declared,
        )
    }
}
