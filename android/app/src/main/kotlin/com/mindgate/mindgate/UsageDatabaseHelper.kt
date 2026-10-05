package com.mindgate.mindgate

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log

/**
 * Native Android SQLite database helper for MindGate usage persistence.
 *
 * Operates on `mindgate.db` in [Context.getDatabasePath], sharing the exact same
 * database file used by Flutter's sqflite plugin.
 *
 * Enables [MindGateAccessibilityService] to persist completed [AppUsageRecord]s
 * directly to SQLite without relying on [MainActivity] or the Flutter Engine.
 */
class UsageDatabaseHelper private constructor(context: Context) : SQLiteOpenHelper(
    context,
    DB_NAME,
    null,
    DB_VERSION
) {

    companion object {
        private const val TAG = "UsageDatabaseHelper"
        private const val DB_NAME = "mindgate.db"
        private const val DB_VERSION = 1

        const val TABLE_USAGE_RECORDS = "usage_records"
        const val COLUMN_ID = "id"
        const val COLUMN_PACKAGE_NAME = "packageName"
        const val COLUMN_START_TIME = "startTime"
        const val COLUMN_END_TIME = "endTime"
        const val COLUMN_DURATION = "duration"

        @Volatile
        private var instance: UsageDatabaseHelper? = null

        fun getInstance(context: Context): UsageDatabaseHelper {
            return instance ?: synchronized(this) {
                instance ?: UsageDatabaseHelper(context.applicationContext).also { instance = it }
            }
        }
    }

    override fun onCreate(db: SQLiteDatabase) {
        val createTableQuery = """
            CREATE TABLE IF NOT EXISTS $TABLE_USAGE_RECORDS (
                $COLUMN_ID INTEGER PRIMARY KEY AUTOINCREMENT,
                $COLUMN_PACKAGE_NAME TEXT NOT NULL,
                $COLUMN_START_TIME INTEGER NOT NULL,
                $COLUMN_END_TIME INTEGER NOT NULL,
                $COLUMN_DURATION INTEGER NOT NULL
            )
        """.trimIndent()
        db.execSQL(createTableQuery)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Schema migrations if needed in future database versions
    }

    /**
     * Persists a completed usage record directly to `usage_records` table in `mindgate.db`.
     *
     * Performs a check for existing records matching (packageName, startTime, endTime)
     * to prevent duplicate entries.
     *
     * @return Row ID of the inserted record, or -1 if insertion was skipped or failed.
     */
    fun insertUsageRecord(packageName: String, startTime: Long, endTime: Long, duration: Long): Long {
        if (packageName.isBlank() || duration <= 0) return -1L

        return try {
            val db = writableDatabase

            // Deduplication check: verify whether an identical record already exists
            val cursor = db.query(
                TABLE_USAGE_RECORDS,
                arrayOf(COLUMN_ID),
                "$COLUMN_PACKAGE_NAME = ? AND $COLUMN_START_TIME = ? AND $COLUMN_END_TIME = ?",
                arrayOf(packageName, startTime.toString(), endTime.toString()),
                null,
                null,
                null,
                "1"
            )

            val exists = cursor.use { it.moveToFirst() }
            if (exists) {
                Log.d(TAG, "Record already exists for $packageName ($startTime), skipping duplicate.")
                return -1L
            }

            val values = ContentValues().apply {
                put(COLUMN_PACKAGE_NAME, packageName)
                put(COLUMN_START_TIME, startTime)
                put(COLUMN_END_TIME, endTime)
                put(COLUMN_DURATION, duration)
            }

            val rowId = db.insert(TABLE_USAGE_RECORDS, null, values)
            Log.d(TAG, "Persisted usage record natively: $packageName, duration: ${duration}ms, rowId: $rowId")
            rowId
        } catch (e: Exception) {
            Log.e(TAG, "Failed to insert usage record into native SQLite", e)
            -1L
        }
    }

    /**
     * Checks whether [packageName] has reached its configured category usage limit in `mindgate.db`.
     *
     * Takes an optional [activeSessionDurationMs] parameter to incorporate the duration
     * of an ongoing in-progress foreground session without modifying SQLite.
     *
     * Safely queries `user_settings`, `app_categories`, and `usage_records` while preserving:
     * - Configured category limits
     * - Toggle enable/disable status
     * - User's manual category overrides
     * - Today's usage aggregation since midnight
     * - Intervention settings (gracePeriod, snoozeEnabled, snoozeDuration)
     *
     * Catches all exceptions safely so monitoring continues uninterrupted.
     */
    fun checkLimitForPackage(packageName: String, activeSessionDurationMs: Long = 0L): LimitCheckResult {
        if (packageName.isBlank()) {
            return LimitCheckResult(false, "neutral", 0L, -1)
        }

        return try {
            val db = readableDatabase

            // 1. Check user_settings
            var usageLimitsEnabled = 1
            var negativeLimit = 30
            var neutralLimit = 120
            var productiveLimit = -1
            var gracePeriod = 5
            var snoozeEnabled = 1
            var snoozeDuration = 5

            val settingsCursor = db.query(
                "user_settings",
                arrayOf(
                    "usageLimitsEnabled",
                    "negativeAppLimit",
                    "neutralAppLimit",
                    "productiveAppLimit",
                    "gracePeriod",
                    "snoozeEnabled",
                    "snoozeDuration"
                ),
                "settingId = 1",
                null,
                null,
                null,
                null
            )
            settingsCursor.use { cursor ->
                if (cursor.moveToFirst()) {
                    val enabledIdx = cursor.getColumnIndex("usageLimitsEnabled")
                    if (enabledIdx >= 0) usageLimitsEnabled = cursor.getInt(enabledIdx)

                    val negIdx = cursor.getColumnIndex("negativeAppLimit")
                    if (negIdx >= 0) negativeLimit = cursor.getInt(negIdx)

                    val neutIdx = cursor.getColumnIndex("neutralAppLimit")
                    if (neutIdx >= 0) neutralLimit = cursor.getInt(neutIdx)

                    val prodIdx = cursor.getColumnIndex("productiveAppLimit")
                    if (prodIdx >= 0) productiveLimit = cursor.getInt(prodIdx)

                    val graceIdx = cursor.getColumnIndex("gracePeriod")
                    if (graceIdx >= 0) gracePeriod = cursor.getInt(graceIdx)

                    val snoozeEnIdx = cursor.getColumnIndex("snoozeEnabled")
                    if (snoozeEnIdx >= 0) snoozeEnabled = cursor.getInt(snoozeEnIdx)

                    val snoozeDurIdx = cursor.getColumnIndex("snoozeDuration")
                    if (snoozeDurIdx >= 0) snoozeDuration = cursor.getInt(snoozeDurIdx)
                }
            }

            if (usageLimitsEnabled == 0) {
                return LimitCheckResult(
                    isLimitReached = false,
                    category = "neutral",
                    usageMs = 0L,
                    limitMinutes = -1,
                    gracePeriodMinutes = gracePeriod,
                    snoozeEnabled = snoozeEnabled == 1,
                    snoozeDurationMinutes = snoozeDuration
                )
            }

            // 2. Resolve category and appName from app_categories table (preserves manual overrides)
            var category = "neutral"
            var appName = ""
            val catCursor = db.query(
                "app_categories",
                arrayOf("category", "appName"),
                "packageName = ?",
                arrayOf(packageName),
                null,
                null,
                null
            )
            catCursor.use { cursor ->
                if (cursor.moveToFirst()) {
                    val catIdx = cursor.getColumnIndex("category")
                    if (catIdx >= 0) category = cursor.getString(catIdx)

                    val appNameIdx = cursor.getColumnIndex("appName")
                    if (appNameIdx >= 0) appName = cursor.getString(appNameIdx)
                }
            }

            // 3. Determine limit for this category
            val limitMinutes = when (category.lowercase()) {
                "negative" -> negativeLimit
                "productive" -> productiveLimit
                else -> neutralLimit
            }

            if (limitMinutes == -1) {
                return LimitCheckResult(
                    isLimitReached = false,
                    category = category,
                    usageMs = 0L,
                    limitMinutes = -1,
                    appName = appName,
                    gracePeriodMinutes = gracePeriod,
                    snoozeEnabled = snoozeEnabled == 1,
                    snoozeDurationMinutes = snoozeDuration
                )
            }

            // 4. Calculate today's category usage
            val calendar = java.util.Calendar.getInstance().apply {
                set(java.util.Calendar.HOUR_OF_DAY, 0)
                set(java.util.Calendar.MINUTE, 0)
                set(java.util.Calendar.SECOND, 0)
                set(java.util.Calendar.MILLISECOND, 0)
            }
            val todayMidnight = calendar.timeInMillis

            // Query all packages belonging to the same category
            val categoryPackages = mutableListOf<String>()
            val catPkgsCursor = db.query(
                "app_categories",
                arrayOf("packageName"),
                "category = ?",
                arrayOf(category),
                null,
                null,
                null
            )
            catPkgsCursor.use { cursor ->
                val pkgIdx = cursor.getColumnIndex("packageName")
                if (pkgIdx >= 0) {
                    while (cursor.moveToNext()) {
                        categoryPackages.add(cursor.getString(pkgIdx))
                    }
                }
            }
            if (!categoryPackages.contains(packageName)) {
                categoryPackages.add(packageName)
            }

            var todayUsageMs = 0L
            if (categoryPackages.isNotEmpty()) {
                val placeholders = categoryPackages.joinToString(",") { "?" }
                val queryArgs = Array(categoryPackages.size + 1) { i ->
                    if (i < categoryPackages.size) categoryPackages[i] else todayMidnight.toString()
                }

                val usageCursor = db.rawQuery(
                    "SELECT SUM($COLUMN_DURATION) FROM $TABLE_USAGE_RECORDS WHERE $COLUMN_PACKAGE_NAME IN ($placeholders) AND $COLUMN_START_TIME >= ?",
                    queryArgs
                )
                usageCursor.use { cursor ->
                    if (cursor.moveToFirst() && !cursor.isNull(0)) {
                        todayUsageMs = cursor.getLong(0)
                    }
                }
            }

            val totalUsageMs = todayUsageMs + maxOf(0L, activeSessionDurationMs)
            val limitMs = limitMinutes.toLong() * 60L * 1000L
            val isLimitReached = totalUsageMs >= limitMs

            LimitCheckResult(
                isLimitReached = isLimitReached,
                category = category,
                usageMs = totalUsageMs,
                limitMinutes = limitMinutes,
                appName = appName,
                gracePeriodMinutes = gracePeriod,
                snoozeEnabled = snoozeEnabled == 1,
                snoozeDurationMinutes = snoozeDuration
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error checking limit for package $packageName", e)
            LimitCheckResult(false, "neutral", 0L, -1)
        }
    }
}

/**
 * Result data class for native usage limit evaluation.
 */
data class LimitCheckResult(
    val isLimitReached: Boolean,
    val category: String,
    val usageMs: Long,
    val limitMinutes: Int,
    val appName: String = "",
    val gracePeriodMinutes: Int = 5,
    val snoozeEnabled: Boolean = true,
    val snoozeDurationMinutes: Int = 5,
)
