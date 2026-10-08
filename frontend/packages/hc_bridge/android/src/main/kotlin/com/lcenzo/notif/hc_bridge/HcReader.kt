package com.lcenzo.notif.hc_bridge

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.changes.DeletionChange
import androidx.health.connect.client.changes.UpsertionChange
import androidx.health.connect.client.feature.ExperimentalMindfulnessSessionApi
import androidx.health.connect.client.request.AggregateGroupByDurationRequest
import androidx.health.connect.client.request.ChangesTokenRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Clock
import java.time.Duration
import java.time.Instant

internal const val HOUR_MS = 3_600_000L
internal const val MAX_WINDOW_HOURS = 744L
internal const val MAX_PAGE_SIZE = 5_000

/** The HC features the app gates on, by the name the Dart side uses. */
@OptIn(ExperimentalMindfulnessSessionApi::class)
internal val FEATURES =
    mapOf(
        "history" to HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_HISTORY,
        "background" to HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_IN_BACKGROUND,
        "skin_temperature" to HealthConnectFeatures.FEATURE_SKIN_TEMPERATURE,
        "planned_exercise" to HealthConnectFeatures.FEATURE_PLANNED_EXERCISE,
        "mindfulness" to HealthConnectFeatures.FEATURE_MINDFULNESS_SESSION,
    )

/**
 * Every Health Connect read Notif makes, as channel-ready maps. Pure over
 * [client], so it runs against `FakeHealthConnectClient` in unit tests.
 *
 * @param upsertsWinWithinPage true where a `getChanges` page lists upserts
 *   before deletions instead of in change order (the Android 14+ platform
 *   path), see [changes].
 */
internal class HcReader(
    private val client: HealthConnectClient,
    private val clock: Clock,
    private val upsertsWinWithinPage: Boolean,
) {
    suspend fun status(): Map<String, Any?> =
        mapOf(
            "sdk" to "available",
            "features" to FEATURES.mapValues { (_, feature) -> featureStatus(feature) },
            "granted" to client.permissionController.getGrantedPermissions().sorted(),
        )

    private fun featureStatus(feature: Int): String =
        if (client.features.getFeatureStatus(feature) == HealthConnectFeatures.FEATURE_STATUS_AVAILABLE) {
            "available"
        } else {
            "unavailable"
        }

    suspend fun readRecords(
        kind: RecordKind,
        startMs: Long,
        endMs: Long,
        pageToken: String?,
        pageSize: Int,
    ): Map<String, Any?> {
        requireRange(startMs, endMs)
        if (pageSize !in 1..MAX_PAGE_SIZE) {
            throw BridgeArgumentException("page_size must be within 1..$MAX_PAGE_SIZE")
        }
        val response =
            client.readRecords(
                ReadRecordsRequest(
                    recordType = kind.recordClass,
                    timeRangeFilter = TimeRangeFilter.between(Instant.ofEpochMilli(startMs), Instant.ofEpochMilli(endMs)),
                    pageSize = pageSize,
                    pageToken = pageToken,
                )
            )
        return mapOf(
            "records" to response.records.mapNotNull(::encodeRecord),
            "next_page_token" to response.pageToken?.takeIf { it.isNotEmpty() },
        )
    }

    suspend fun aggregateHourly(kind: AggregateKind, startMs: Long, endMs: Long): Map<String, Any?> {
        requireRange(startMs, endMs)
        if (startMs % HOUR_MS != 0L || endMs % HOUR_MS != 0L) {
            throw BridgeArgumentException("start_ms and end_ms must fall on UTC hours")
        }
        if ((endMs - startMs) / HOUR_MS > MAX_WINDOW_HOURS) {
            throw BridgeArgumentException("a window spans at most $MAX_WINDOW_HOURS hours")
        }
        val computedAtMs = clock.millis()
        val groups =
            client.aggregateGroupByDuration(
                AggregateGroupByDurationRequest(
                    metrics = setOf(kind.metric),
                    timeRangeFilter = TimeRangeFilter.between(Instant.ofEpochMilli(startMs), Instant.ofEpochMilli(endMs)),
                    timeRangeSlicer = Duration.ofHours(1),
                )
            )
        val buckets =
            groups.mapNotNull { group ->
                val value = kind.valueIn(group.result) ?: return@mapNotNull null
                mapOf(
                    "start_ms" to group.startTime.toEpochMilli(),
                    "end_ms" to group.endTime.toEpochMilli(),
                    "value" to value,
                    "data_origins" to group.result.dataOrigins.map { it.packageName }.sorted(),
                )
            }
        return mapOf(
            "metric" to kind.wire,
            "start_ms" to startMs,
            "end_ms" to endMs,
            "computed_at_ms" to computedAtMs,
            "buckets" to buckets,
        )
    }

    suspend fun changesToken(kinds: Set<RecordKind>): String {
        if (kinds.isEmpty()) throw BridgeArgumentException("types must not be empty")
        return client.getChangesToken(ChangesTokenRequest(recordTypes = kinds.map { it.recordClass }.toSet()))
    }

    /**
     * One `getChanges` page, ordered so that "the last change per id wins" holds.
     *
     * The pre-14 client lists changes in the order they happened. The Android
     * 14+ platform path lists every upsert, then every deletion, and an upsert
     * there is a record that exists now; so an id with both in one page was
     * deleted and re-written, and its deletion is dropped.
     */
    suspend fun changes(token: String): Map<String, Any?> {
        if (token.isEmpty()) throw BridgeArgumentException("token must not be empty")
        val observedAtMs = clock.millis()
        val response = client.getChanges(token)
        val upsertedIds =
            if (upsertsWinWithinPage) {
                response.changes.filterIsInstance<UpsertionChange>().map { it.record.metadata.id }.toSet()
            } else {
                emptySet()
            }
        var skipped = 0
        val changes =
            response.changes.mapNotNull { change ->
                when (change) {
                    is UpsertionChange -> {
                        val encoded = encodeRecord(change.record)
                        if (encoded == null) skipped++
                        encoded?.let { mapOf("kind" to "upsert", "record" to it) }
                    }
                    is DeletionChange ->
                        if (change.recordId in upsertedIds) {
                            null
                        } else {
                            mapOf("kind" to "deletion", "id" to change.recordId)
                        }
                    else -> {
                        skipped++
                        null
                    }
                }
            }
        return mapOf(
            "changes" to changes,
            "next_token" to response.nextChangesToken,
            "has_more" to response.hasMore,
            "token_expired" to response.changesTokenExpired,
            "observed_at_ms" to observedAtMs,
            "skipped_unsupported" to skipped,
        )
    }

    suspend fun coverageProbe(kinds: Set<ProbeKind>): Map<String, Any?> = probeCoverage(client, clock, kinds)

    private fun requireRange(startMs: Long, endMs: Long) {
        if (startMs < 0 || endMs <= startMs) {
            throw BridgeArgumentException("need 0 <= start_ms < end_ms, got $startMs..$endMs")
        }
    }
}
