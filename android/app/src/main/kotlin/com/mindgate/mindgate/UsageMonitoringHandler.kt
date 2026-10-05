package com.mindgate.mindgate

import android.app.usage.UsageStatsManager
import android.content.Context
import java.util.Calendar

/**
 * Handles queries to [UsageStatsManager] for historical per-package usage statistics.
 *
 * Requires the PACKAGE_USAGE_STATS permission (granted via the Usage Access settings page).
 * All results are returned as plain Maps for safe transport over Flutter MethodChannel.
 *
 * This class is purely a query layer — it does not persist data, classify apps,
 * or maintain any state. All persistence belongs to a later phase.
 */
class UsageMonitoringHandler(private val context: Context) {

    /**
     * Queries usage statistics for the current day (from midnight to now).
     *
     * @return A list of usage stat maps, one per package that had foreground activity today.
     *         Returns an empty list if Usage Access is not granted or the API is unavailable.
     */
    fun queryTodayUsageStats(): List<Map<String, Any>> {
        val now = System.currentTimeMillis()
        val midnight = todayMidnightMs()
        return queryUsageStats(beginTime = midnight, endTime = now)
    }

    /**
     * Queries usage statistics for a custom time range.
     *
     * Each returned map contains:
     * - `packageName`           (String)  — Android package identifier
     * - `totalTimeInForeground` (Long ms) — Cumulative foreground duration in the period
     * - `firstTimeStamp`        (Long ms) — Epoch ms of first event in the period
     * - `lastTimeStamp`         (Long ms) — Epoch ms of last event in the period
     * - `lastTimeUsed`          (Long ms) — Epoch ms when the app was last used
     *
     * @param beginTime Start of the query range, epoch milliseconds.
     * @param endTime   End of the query range, epoch milliseconds.
     * @return List of usage stat maps (only packages with totalTimeInForeground > 0).
     *         Returns an empty list if Usage Access is not granted.
     */
    fun queryUsageStats(beginTime: Long, endTime: Long): List<Map<String, Any>> {
        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
            ?: return emptyList()

        val stats = usm.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            beginTime,
            endTime,
        ) ?: return emptyList()

        return stats
            .filter { it.totalTimeInForeground > 0L }
            .sortedByDescending { it.totalTimeInForeground }
            .map { stat ->
                mapOf(
                    "packageName"           to stat.packageName,
                    "totalTimeInForeground" to stat.totalTimeInForeground,
                    "firstTimeStamp"        to stat.firstTimeStamp,
                    "lastTimeStamp"         to stat.lastTimeStamp,
                    "lastTimeUsed"          to stat.lastTimeUsed,
                )
            }
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    /** Returns the epoch ms for midnight at the start of today in the device's local timezone. */
    private fun todayMidnightMs(): Long {
        return Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
    }
}
