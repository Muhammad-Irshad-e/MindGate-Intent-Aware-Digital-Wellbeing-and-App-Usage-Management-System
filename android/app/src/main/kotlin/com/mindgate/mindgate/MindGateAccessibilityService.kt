package com.mindgate.mindgate

import android.accessibilityservice.AccessibilityService
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import io.flutter.plugin.common.EventChannel

/**
 * MindGate Accessibility Service — real-time foreground application detection & enforcement.
 *
 * This service listens for [AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED] events to track
 * which application is currently in the foreground. When the foreground application changes,
 * it closes the previous session, calculates the duration, persists it to native SQLite,
 * and emits a completed [AppUsageRecord] to Flutter through an [EventChannel].
 *
 * ─── Phase 12B-3A: Transient Window Hysteresis & Session Preservation ────────────────────────
 * Transient system/overlay windows (e.g. Samsung Honeyboard / Gboard keyboards, Autofill dialogs,
 * Credential Manager, Google Play Services, notification shade peek, OEM edge panels) do NOT
 * destroy the primary user app session.
 *
 * Keyboards are recognized as input overlays and never terminate or timeout the active session.
 * Other transient/launcher transitions enter a short (3-second) grace window. If the primary user
 * app returns within 3 seconds, the session continues seamlessly with its ORIGINAL sessionStartTime.
 * Actual user-app switches (e.g. Brave -> Instagram) immediately finalize the previous session
 * with its original sessionStartTime and begin tracking the new application.
 *
 * ─── Privacy guarantees ──────────────────────────────────────────────────────────────────────
 *  • canRetrieveWindowContent is false in accessibility_service_config.xml. No screen content,
 *    view hierarchy, text, message, URL, or personal data is read.
 *  • Only the package name of the foreground application is extracted from each event.
 *  • No keyboard input, passwords, contacts, files, or screenshots are captured.
 * ─────────────────────────────────────────────────────────────────────────────────────────────
 */
class MindGateAccessibilityService : AccessibilityService() {

    // ── Primary User App Session State ─────────────────────────────────────────

    /** The package name currently being tracked as the active user application. */
    private var currentPackage: String? = null

    /** Package name of the last active user application before entering system UI. */
    private var lastUserPackage: String? = null

    /** Flag indicating whether the foreground event currently is inside a system UI package. */
    private var inSystemUI: Boolean = false

    /** Epoch milliseconds when the current session started. */
    private var sessionStartTime: Long = 0L

    /** BroadcastReceiver for monitoring device screen off and unlock events. */
    private var screenStateReceiver: BroadcastReceiver? = null

    // ── Transient Window Hysteresis State (Phase 12B-3A) ───────────────────────

    /** Package awaiting finalized closure during transient grace period. */
    private var pendingClosePackage: String? = null

    /** Original start time of the pending close session. */
    private var pendingCloseStartTime: Long = 0L

    /** Timestamp when the primary user app was temporarily obscured or left. */
    private var pendingCloseEndTime: Long = 0L

    /** Runnable scheduled to finalize the session if primary app does not resume. */
    private var pendingCloseRunnable: Runnable? = null

    /** Handler for session hysteresis grace timers. */
    private val sessionHandler: Handler = Handler(Looper.getMainLooper())

    // ── Active Session Evaluation Ticker State (Phase 12B-3) ───────────────────
    private var activeSessionHandler: Handler? = null
    private var activeSessionRunnable: Runnable? = null
    private val nativeGraceStartMap = mutableMapOf<String, Long>()
    private val nativeSnoozeStartMap = mutableMapOf<String, Long>()

    // ── Companion: shared EventSink & Constants ────────────────────────────────

    companion object {
        /** Active session evaluation ticker interval (5 seconds). */
        private const val ACTIVE_SESSION_TICK_MS = 5_000L

        /** Grace period (3 seconds) to allow transient windows/overlays to dismiss without destroying the session. */
        private const val TRANSIENT_GRACE_MS = 3_000L

        /**
         * The [EventChannel.EventSink] provided by Flutter when it begins listening on
         * the [EventChannel] registered in [MainActivity].
         *
         * Annotated [@Volatile] because the main thread writes it (via [MainActivity])
         * and the accessibility thread reads it.
         */
        @Volatile
        var eventSink: EventChannel.EventSink? = null

        /**
         * Minimum session duration in milliseconds.
         * Sessions shorter than this are discarded to suppress noise from rapid
         * window transitions (e.g. permission dialogs, transient overlays).
         */
        private const val MIN_SESSION_DURATION_MS = 1_000L

        /** Keyboards and Input Method Editors (IMEs). */
        private val KEYBOARD_PACKAGES: Set<String> = setOf(
            "com.samsung.android.honeyboard",
            "com.google.android.inputmethod.latin",
            "com.touchtype.swiftkey",
            "com.touchtype.swiftkey.phone.tablet",
        )

        /** OEM launchers / Home screen packages. */
        private val LAUNCHER_PACKAGES: Set<String> = setOf(
            "com.android.launcher",
            "com.android.launcher2",
            "com.android.launcher3",
            "com.sec.android.app.launcher",
            "com.google.android.apps.nexuslauncher",
            "com.miui.home",
            "com.oppo.launcher",
            "com.huawei.android.launcher",
            "com.oneplus.launcher",
        )

        /** Transient system, overlay, credential manager, autofill, and permission dialog packages. */
        private val TRANSIENT_SYSTEM_PACKAGES: Set<String> = setOf(
            "android",
            "com.android.systemui",
            "com.google.android.gms",
            "com.google.android.permissioncontroller",
            "com.android.permissioncontroller",
            "com.android.packageinstaller",
            "com.samsung.android.authfw",
            "com.samsung.android.samsungpass",
            "com.samsung.android.samsungpassautofill",
            "com.samsung.android.spay",
            "com.samsung.android.app.cocktailbarservice",
        )

        /**
         * System UI, OEM launcher, and input method packages that should NOT be
         * recorded as user application sessions.
         * Synchronized with Dart's SystemPackages utility.
         */
        private val SYSTEM_UI_PACKAGES: Set<String> = setOf(
            "android",
            "com.android.systemui",
            "com.android.launcher",
            "com.android.launcher2",
            "com.android.launcher3",
            "com.sec.android.app.launcher",
            "com.samsung.android.honeyboard",
            "com.google.android.apps.nexuslauncher",
            "com.google.android.inputmethod.latin",
            "com.touchtype.swiftkey",
            "com.miui.home",
            "com.oppo.launcher",
            "com.huawei.android.launcher",
            "com.google.android.permissioncontroller",
            "com.android.permissioncontroller",
            "com.android.packageinstaller",
        )

        /**
         * Returns true if [packageName] is an on-screen keyboard / IME.
         */
        fun isKeyboardPackage(packageName: String): Boolean {
            val pkg = packageName.trim().lowercase()
            if (pkg.isEmpty()) return false
            if (pkg in KEYBOARD_PACKAGES) return true
            if (pkg.contains("honeyboard") ||
                pkg.contains("inputmethod") ||
                pkg.contains("keyboard") ||
                pkg.endsWith(".ime")) {
                return true
            }
            return false
        }

        /**
         * Returns true if [packageName] is an OEM launcher / home screen.
         */
        fun isLauncherPackage(packageName: String): Boolean {
            val pkg = packageName.trim().lowercase()
            if (pkg.isEmpty()) return false
            if (pkg in LAUNCHER_PACKAGES) return true
            if (pkg.startsWith("com.android.launcher") ||
                pkg.startsWith("com.sec.android.app.launcher") ||
                pkg.startsWith("com.google.android.apps.nexuslauncher") ||
                pkg.endsWith(".launcher") ||
                pkg.endsWith(".home")) {
                return true
            }
            return false
        }

        /**
         * Returns true if [packageName] is a transient system/overlay, autofill,
         * credential manager, or permission dialog.
         */
        fun isTransientPackage(packageName: String): Boolean {
            val pkg = packageName.trim().lowercase()
            if (pkg.isEmpty()) return true
            if (pkg in TRANSIENT_SYSTEM_PACKAGES) return true
            if (pkg.contains("autofill") ||
                pkg.contains("credentialmanager") ||
                pkg.contains("permissioncontroller") ||
                pkg.contains("packageinstaller")) {
                return true
            }
            return false
        }

        /**
         * Returns true when [packageName] is a known system UI, OEM launcher, or input method.
         */
        fun isSystemPackage(packageName: String): Boolean {
            val pkg = packageName.trim().lowercase()
            if (pkg.isEmpty()) return true
            if (pkg in SYSTEM_UI_PACKAGES) return true
            if (isLauncherPackage(pkg) || isKeyboardPackage(pkg) || isTransientPackage(pkg)) {
                return true
            }
            return false
        }
    }

    // ── Service lifecycle overrides ──────────────────────────────────────────────

    override fun onServiceConnected() {
        super.onServiceConnected()
        registerScreenStateReceiver()
    }

    // ── AccessibilityService overrides ─────────────────────────────────────────

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val eventType = event.eventType
        // Only TYPE_WINDOW_STATE_CHANGED signals authoritative window focus / app switches.
        // TYPE_WINDOWS_CHANGED events (e.g. system shade collapse, volume panel, layer animations)
        // must NOT terminate an active user session.
        if (eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        val newPackage = event.packageName?.toString()?.trim()

        // Ignore events from MindGate's own overlay windows (e.g. TYPE_ACCESSIBILITY_OVERLAY).
        // Without this guard, showing the intervention overlay fires a TYPE_WINDOW_STATE_CHANGED
        // event with packageName="com.mindgate.mindgate", which the service would misinterpret
        // as a new user application — immediately hiding the overlay and killing the active session.
        if (newPackage == packageName) return

        // 1. Null, empty, or keyboard packages:
        // Keyboards (e.g. Samsung Honeyboard, Gboard) appear directly over the active user app.
        // The user is actively typing inside the primary application.
        // Do NOT close session, do NOT reset sessionStartTime, do NOT schedule pending close.
        if (!newPackage.isNullOrEmpty() && isKeyboardPackage(newPackage)) {
            if (pendingClosePackage != null && pendingClosePackage == currentPackage) {
                cancelPendingSessionClose()
            }
            return
        }

        // 2. Returning to currently active package or resuming pending close package:
        // E.g. Brave -> Honeyboard -> Brave, or Brave -> transient autofill -> Brave.
        // Resume the existing session using the ORIGINAL sessionStartTime!
        if (newPackage != null && (newPackage == currentPackage || newPackage == pendingClosePackage)) {
            if (pendingCloseRunnable != null) {
                cancelPendingSessionClose()
            }
            currentPackage = newPackage
            inSystemUI = false
            // Session continues uninterrupted with original sessionStartTime
            return
        }

        // 3. Launcher / Home screen:
        // User may have pressed Home to switch apps or temporarily glance at home screen.
        // Schedule a 3-second grace period. If they return to the primary app within 3s,
        // the session is preserved. If 3s elapse, the session is finalized at the moment they went home.
        if (!newPackage.isNullOrEmpty() && isLauncherPackage(newPackage)) {
            if (currentPackage != null) {
                lastUserPackage = currentPackage
                schedulePendingSessionClose()
            }
            // Temporarily hide overlay while on home screen
            InterventionOverlayManager.getInstance().hideOverlay()
            return
        }

        // 4. Transient system packages, autofill, credential manager, GMS, or null package:
        // Do NOT immediately close the session. Schedule 3s grace period.
        if (newPackage.isNullOrEmpty() || isTransientPackage(newPackage) || isSystemPackage(newPackage)) {
            if (currentPackage != null) {
                lastUserPackage = currentPackage
                schedulePendingSessionClose()
            }
            return
        }

        // 5. Genuine USER APPLICATION has come into foreground:
        // E.g. Brave, Instagram, YouTube, etc.

        // If there was a pending close session from a previous user app, finalize it immediately
        if (pendingCloseRunnable != null) {
            finalizePendingSession()
        } else if (currentPackage != null) {
            // Actual user app switch (e.g. Brave -> Instagram)
            // Finalize previous app using its original sessionStartTime
            closeCurrentSession()
        }

        // Start new user app session
        inSystemUI = false
        currentPackage = newPackage
        lastUserPackage = newPackage
        sessionStartTime = System.currentTimeMillis()

        // If package changed away from the restricted app, dismiss overlay
        val overlayMgr = InterventionOverlayManager.getInstance()
        if (overlayMgr.isShowing && overlayMgr.getActivePackage() != newPackage) {
            overlayMgr.hideOverlay()
        }

        // Phase 12A: Detect foreground application and check category usage limit
        checkAndEmitForegroundEvent(newPackage, sessionStartTime)
        // Phase 12B-3: Start native active-session limit ticker
        startActiveSessionTicker()
    }

    override fun onInterrupt() {
        if (pendingCloseRunnable != null) {
            finalizePendingSession()
        } else {
            closeCurrentSession()
        }
        stopActiveSessionTicker()
        currentPackage = null
        lastUserPackage = null
        inSystemUI = false
        InterventionOverlayManager.getInstance().hideOverlay()
    }

    override fun onUnbind(intent: Intent?): Boolean {
        if (pendingCloseRunnable != null) {
            finalizePendingSession()
        } else {
            closeCurrentSession()
        }
        stopActiveSessionTicker()
        currentPackage = null
        lastUserPackage = null
        inSystemUI = false
        unregisterScreenStateReceiver()
        InterventionOverlayManager.getInstance().hideOverlay()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        if (pendingCloseRunnable != null) {
            finalizePendingSession()
        } else {
            closeCurrentSession()
        }
        stopActiveSessionTicker()
        currentPackage = null
        lastUserPackage = null
        inSystemUI = false
        unregisterScreenStateReceiver()
        InterventionOverlayManager.getInstance().hideOverlay()
        super.onDestroy()
    }

    // ── Screen state receiver ──────────────────────────────────────────────────

    private fun registerScreenStateReceiver() {
        if (screenStateReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    Intent.ACTION_SCREEN_OFF -> {
                        if (pendingCloseRunnable != null) {
                            finalizePendingSession()
                        } else if (currentPackage != null) {
                            lastUserPackage = currentPackage
                            closeCurrentSession()
                        }
                        inSystemUI = true
                        stopActiveSessionTicker()
                        InterventionOverlayManager.getInstance().hideOverlay()
                    }
                    Intent.ACTION_USER_PRESENT, Intent.ACTION_SCREEN_ON -> {
                        // Device turned back on/unlocked — ready for next window state event
                    }
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        try {
            registerReceiver(receiver, filter)
            screenStateReceiver = receiver
        } catch (e: Exception) {
            Log.e("MindGateService", "Failed to register screen state receiver", e)
        }
    }

    private fun unregisterScreenStateReceiver() {
        screenStateReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {}
        }
        screenStateReceiver = null
    }

    // ── Session Hysteresis & Preservation (Phase 12B-3A) ────────────────────────

    /**
     * Schedules a pending close for the active session with a [TRANSIENT_GRACE_MS] grace period.
     * If the user returns to the primary package within this window, the pending close is cancelled
     * and the session continues with its original [sessionStartTime].
     *
     * If the grace period expires without returning, [finalizePendingSession] is called to
     * commit the session to SQLite using the exact time when the app was left.
     */
    private fun schedulePendingSessionClose() {
        val pkg = currentPackage ?: return
        if (pendingCloseRunnable != null) {
            // Already pending closure; preserve the original leave timestamp
            return
        }

        val startTime = sessionStartTime
        val leftTime = System.currentTimeMillis()

        pendingClosePackage = pkg
        pendingCloseStartTime = startTime
        pendingCloseEndTime = leftTime

        val runnable = Runnable {
            finalizePendingSession()
        }
        pendingCloseRunnable = runnable
        sessionHandler.postDelayed(runnable, TRANSIENT_GRACE_MS)
    }

    /**
     * Cancels any pending session closure and restores the active session state.
     * Called when the user returns to the primary user app within the grace period.
     */
    private fun cancelPendingSessionClose() {
        pendingCloseRunnable?.let {
            sessionHandler.removeCallbacks(it)
        }
        pendingCloseRunnable = null

        val restoredPkg = pendingClosePackage
        val restoredStart = pendingCloseStartTime

        if (restoredPkg != null) {
            currentPackage = restoredPkg
        }
        if (restoredStart > 0L) {
            sessionStartTime = restoredStart
        }

        pendingClosePackage = null
        pendingCloseStartTime = 0L
        pendingCloseEndTime = 0L
    }

    /**
     * Finalizes and persists the pending session to SQLite.
     * Called when the 3-second grace period expires or when an actual user-app switch occurs.
     */
    private fun finalizePendingSession() {
        pendingCloseRunnable?.let {
            sessionHandler.removeCallbacks(it)
        }
        pendingCloseRunnable = null

        val pkg = pendingClosePackage ?: currentPackage
        val startTime = if (pendingCloseStartTime > 0L) pendingCloseStartTime else sessionStartTime
        val endTime = if (pendingCloseEndTime > 0L) pendingCloseEndTime else System.currentTimeMillis()

        pendingClosePackage = null
        pendingCloseStartTime = 0L
        pendingCloseEndTime = 0L

        if (pkg != null && startTime > 0L) {
            persistAndEmitSession(pkg, startTime, endTime)
        }

        currentPackage = null
        sessionStartTime = 0L
        inSystemUI = true
        stopActiveSessionTicker()
        InterventionOverlayManager.getInstance().hideOverlay()
    }

    /**
     * Closes the currently active session (if any) and finalizes it with the current timestamp.
     */
    private fun closeCurrentSession() {
        val pkg = currentPackage ?: return
        val startTime = sessionStartTime
        val endTime = System.currentTimeMillis()
        if (startTime > 0L) {
            persistAndEmitSession(pkg, startTime, endTime)
        }
        currentPackage = null
        sessionStartTime = 0L
    }

    /**
     * Persists the record directly to native SQLite (`mindgate.db`), and emits the resulting
     * [AppUsageRecord] through the [eventSink] if Flutter is listening.
     *
     * Sessions with a duration below [MIN_SESSION_DURATION_MS] are silently discarded
     * to avoid noise from rapid window transitions.
     */
    private fun persistAndEmitSession(pkg: String, startTime: Long, endTime: Long) {
        val duration = endTime - startTime

        // Discard extremely short sessions (noise from transient overlays)
        if (duration < MIN_SESSION_DURATION_MS) return

        // 1. Native SQLite Persistence — runs regardless of Flutter engine / UI state
        try {
            val dbHelper = UsageDatabaseHelper.getInstance(applicationContext)
            dbHelper.insertUsageRecord(
                packageName = pkg,
                startTime   = startTime,
                endTime     = endTime,
                duration    = duration,
            )
        } catch (e: Exception) {
            Log.e("MindGateService", "Failed native SQLite persistence for $pkg", e)
        }

        // 2. Real-time emit to Flutter UI if active
        val record = AppUsageRecord(
            packageName = pkg,
            startTime   = startTime,
            endTime     = endTime,
            duration    = duration,
        )
        emitRecord(record)
    }

    // ── Active Session Evaluation Ticker (Phase 12B-3) ─────────────────────────

    private fun startActiveSessionTicker() {
        stopActiveSessionTicker()
        val pkg = currentPackage ?: return
        if (isSystemPackage(pkg)) return

        val handler = Handler(Looper.getMainLooper())
        activeSessionHandler = handler

        val runnable = object : Runnable {
            override fun run() {
                val activePkg = currentPackage
                val startTime = sessionStartTime
                if (activePkg != null && activePkg == pkg && startTime > 0L && !isSystemPackage(activePkg)) {
                    // Do not show overlay while in transient pending close (e.g. user briefly on launcher)
                    if (pendingCloseRunnable == null) {
                        evaluateNativeActiveSessionLimit(activePkg, startTime)
                    }
                    handler.postDelayed(this, ACTIVE_SESSION_TICK_MS)
                } else {
                    stopActiveSessionTicker()
                }
            }
        }
        activeSessionRunnable = runnable
        handler.postDelayed(runnable, ACTIVE_SESSION_TICK_MS)
    }

    private fun stopActiveSessionTicker() {
        activeSessionRunnable?.let { runnable ->
            activeSessionHandler?.removeCallbacks(runnable)
        }
        activeSessionRunnable = null
        activeSessionHandler = null
    }

    private fun evaluateNativeActiveSessionLimit(packageName: String, startTime: Long) {
        try {
            val activeDurationMs = System.currentTimeMillis() - startTime
            if (activeDurationMs < 0L) return

            val dbHelper = UsageDatabaseHelper.getInstance(applicationContext)
            val limitResult = dbHelper.checkLimitForPackage(packageName, activeDurationMs)

            val overlayMgr = InterventionOverlayManager.getInstance()

            if (!limitResult.isLimitReached) {
                if (overlayMgr.isShowing && overlayMgr.getActivePackage() == packageName) {
                    overlayMgr.hideOverlay()
                }
                nativeGraceStartMap.remove(packageName)
                nativeSnoozeStartMap.remove(packageName)
                return
            }

            // Check snooze state
            val snoozeStart = nativeSnoozeStartMap[packageName]
            if (snoozeStart != null) {
                val snoozeMs = limitResult.snoozeDurationMinutes * 60 * 1000L
                if (System.currentTimeMillis() - snoozeStart < snoozeMs) {
                    if (overlayMgr.isShowing && overlayMgr.getActivePackage() == packageName) {
                        overlayMgr.hideOverlay()
                    }
                    return
                } else {
                    nativeSnoozeStartMap.remove(packageName)
                }
            }

            // Grace period calculation
            val now = System.currentTimeMillis()
            var graceStart = nativeGraceStartMap[packageName]
            if (graceStart == null) {
                graceStart = now
                nativeGraceStartMap[packageName] = graceStart
            }

            val graceDurationMs = limitResult.gracePeriodMinutes * 60 * 1000L
            val elapsedGraceMs = now - graceStart
            val remainingGraceSec = maxOf(0, ((graceDurationMs - elapsedGraceMs) / 1000L).toInt())

            val appNameDisplay = if (limitResult.appName.isNotBlank()) {
                limitResult.appName
            } else {
                deriveAppName(packageName)
            }

            val categoryDisplay = limitResult.category.replaceFirstChar {
                if (it.isLowerCase()) it.titlecase() else it.toString()
            }

            overlayMgr.showOverlay(
                context = this,
                packageName = packageName,
                appName = appNameDisplay,
                categoryName = categoryDisplay,
                usedMinutes = (limitResult.usageMs / (60 * 1000L)).toInt(),
                remainingSeconds = remainingGraceSec,
                snoozeEnabled = limitResult.snoozeEnabled,
                snoozeDuration = limitResult.snoozeDurationMinutes,
                onTakeBreak = {
                    nativeGraceStartMap.remove(packageName)
                    nativeSnoozeStartMap.remove(packageName)
                },
                onSnooze = {
                    nativeSnoozeStartMap[packageName] = System.currentTimeMillis()
                }
            )
        } catch (e: Exception) {
            Log.e("MindGateService", "Error evaluating native active-session limit for $packageName", e)
        }
    }

    private fun deriveAppName(packageName: String): String {
        if (packageName.isBlank()) return "App"
        val parts = packageName.split('.')
        if (parts.isNotEmpty()) {
            val last = parts.last()
            if (last.isNotBlank()) {
                return last.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
            }
        }
        return packageName
    }

    // ── Foreground Event & Channel Helpers ─────────────────────────────────────

    /**
     * Checks whether [packageName] has reached its category usage limit in native SQLite
     * and communicates the event to Flutter via the [eventSink].
     *
     * Safe to call — any unexpected exception is caught so the service never crashes
     * and monitoring continues uninterrupted.
     */
    private fun checkAndEmitForegroundEvent(packageName: String, startTime: Long) {
        try {
            val dbHelper = UsageDatabaseHelper.getInstance(applicationContext)
            val limitResult = dbHelper.checkLimitForPackage(packageName)

            val event = mapOf(
                "eventType" to if (limitResult.isLimitReached) "limit_reached" else "foreground_changed",
                "packageName" to packageName,
                "startTime" to startTime,
                "isLimitReached" to limitResult.isLimitReached,
                "category" to limitResult.category,
                "usageMs" to limitResult.usageMs,
                "limitMinutes" to limitResult.limitMinutes,
            )
            emitEvent(event)
        } catch (e: Exception) {
            Log.e("MindGateService", "Error evaluating foreground limit for $packageName", e)
        }
    }

    /**
     * Sends an arbitrary event map to Flutter via the [eventSink].
     */
    private fun emitEvent(event: Map<String, Any>) {
        try {
            eventSink?.success(event)
        } catch (_: Exception) {
            // EventChannel may be detached (e.g. Flutter engine torn down).
            // Swallow the exception — the service must not crash.
        }
    }

    /**
     * Sends [record] to Flutter via the [EventChannel].
     *
     * Safe to call when Flutter is not listening — [eventSink] will be null and
     * the call becomes a no-op. Any unexpected exception is caught to prevent
     * the service from crashing.
     */
    private fun emitRecord(record: AppUsageRecord) {
        try {
            eventSink?.success(record.toMap())
        } catch (_: Exception) {
            // EventChannel may be detached (e.g. Flutter engine torn down).
            // Swallow the exception — the service must not crash.
        }
    }
}
