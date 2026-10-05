package com.mindgate.mindgate

/**
 * Represents a single completed foreground application usage session.
 *
 * All timestamps are in epoch milliseconds (System.currentTimeMillis()).
 *
 * Privacy note: Only the package-level identifier is stored.
 * No screen content, text, messages, URLs, or personal data are captured.
 */
data class AppUsageRecord(
    /** Android package name of the foreground application (e.g. "com.google.android.youtube"). */
    val packageName: String,

    /** Epoch milliseconds when this package became the foreground application. */
    val startTime: Long,

    /** Epoch milliseconds when this package left the foreground. */
    val endTime: Long,

    /** Duration of the session in milliseconds (endTime - startTime). */
    val duration: Long,
) {
    /**
     * Serialises this record to a [Map] compatible with Flutter's EventChannel.
     * All Long values are passed as Long — the Dart side receives them as int.
     */
    fun toMap(): Map<String, Any> = mapOf(
        "packageName" to packageName,
        "startTime"   to startTime,
        "endTime"     to endTime,
        "duration"    to duration,
    )
}
