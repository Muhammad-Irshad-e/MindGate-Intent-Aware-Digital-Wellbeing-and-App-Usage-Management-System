package com.mindgate.mindgate

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        /** Existing permission channel — unchanged from Phase 2. */
        private const val PERMISSIONS_CHANNEL = "com.mindgate/permissions"

        /**
         * EventChannel for streaming completed [AppUsageRecord]s from the
         * [MindGateAccessibilityService] to Flutter in real time.
         * Direction: Android → Flutter (push).
         */
        private const val MONITORING_EVENT_CHANNEL = "com.mindgate/monitoring"

        /**
         * MethodChannel for on-demand historical usage statistics queries
         * against [UsageStatsManager].
         * Direction: Flutter → Android (request/response).
         */
        private const val MONITORING_STATS_CHANNEL = "com.mindgate/monitoring/stats"
        /**
         * MethodChannel for querying installed user applications from Android.
         * Direction: Flutter → Android (request/response).
         */
        private const val APPS_CHANNEL = "com.mindgate/apps"

        /**
         * MethodChannel for system-level intervention overlay controls.
         */
        private const val OVERLAY_CHANNEL = "com.mindgate/overlay"
    }

    private lateinit var permissionHandler: PermissionHandler
    private lateinit var usageMonitoringHandler: UsageMonitoringHandler
    private lateinit var appInfoHandler: AppInfoHandler

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        permissionHandler       = PermissionHandler(context, this)
        usageMonitoringHandler  = UsageMonitoringHandler(context)
        appInfoHandler          = AppInfoHandler(context)

        val overlayChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            OVERLAY_CHANNEL,
        )
        overlayChannel.setMethodCallHandler { call, result ->
            val overlayManager = InterventionOverlayManager.getInstance()
            when (call.method) {
                "showOverlay" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    val appName = call.argument<String>("appName") ?: ""
                    val categoryName = call.argument<String>("categoryName") ?: ""
                    val usedMinutes = call.argument<Int>("usedMinutes") ?: 0
                    val remainingSeconds = call.argument<Int>("remainingSeconds") ?: 0
                    val snoozeEnabled = call.argument<Boolean>("snoozeEnabled") ?: true
                    val snoozeDuration = call.argument<Int>("snoozeDuration") ?: 5

                    overlayManager.showOverlay(
                        context = applicationContext,
                        packageName = packageName,
                        appName = appName,
                        categoryName = categoryName,
                        usedMinutes = usedMinutes,
                        remainingSeconds = remainingSeconds,
                        snoozeEnabled = snoozeEnabled,
                        snoozeDuration = snoozeDuration,
                        onTakeBreak = {
                            runOnUiThread {
                                overlayChannel.invokeMethod("onTakeBreak", null)
                            }
                        },
                        onSnooze = {
                            runOnUiThread {
                                overlayChannel.invokeMethod("onSnooze", null)
                            }
                        }
                    )
                    result.success(true)
                }
                "hideOverlay" -> {
                    overlayManager.hideOverlay()
                    result.success(true)
                }
                "isOverlayShowing" -> {
                    result.success(overlayManager.isShowing)
                }
                else -> result.notImplemented()
            }
        }

        // ── 1. Existing permission MethodChannel (Phase 2 — unchanged) ────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PERMISSIONS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            permissionHandler.setActivity(this)
            permissionHandler.handleMethodCall(call, result)
        }

        // ── 2. Monitoring EventChannel (Phase 3 — unchanged) ──────────────────
        // Wires the MindGateAccessibilityService's static EventSink to Flutter.
        // When Flutter opens the stream, onListen stores the sink on the service companion.
        // When Flutter cancels, onCancel nulls it — the service then suppresses emits.
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MONITORING_EVENT_CHANNEL,
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                MindGateAccessibilityService.eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                MindGateAccessibilityService.eventSink = null
            }
        })

        // ── 3. Monitoring Stats MethodChannel (Phase 3 — unchanged) ───────────
        // Handles on-demand UsageStatsManager queries from Flutter.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MONITORING_STATS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getTodayUsageStats" -> {
                    try {
                        result.success(usageMonitoringHandler.queryTodayUsageStats())
                    } catch (e: Exception) {
                        result.error(
                            "USAGE_STATS_ERROR",
                            e.localizedMessage,
                            e.stackTraceToString(),
                        )
                    }
                }
                "getUsageStats" -> {
                    try {
                        val beginTime = call.argument<Long>("beginTime")
                            ?: 0L
                        val endTime = call.argument<Long>("endTime")
                            ?: System.currentTimeMillis()
                        result.success(
                            usageMonitoringHandler.queryUsageStats(beginTime, endTime),
                        )
                    } catch (e: Exception) {
                        result.error(
                            "USAGE_STATS_ERROR",
                            e.localizedMessage,
                            e.stackTraceToString(),
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }

        // ── 4. Installed App Info MethodChannel (Phase 4 — new) ────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APPS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> {
                    try {
                        result.success(appInfoHandler.getInstalledApps())
                    } catch (e: Exception) {
                        result.error(
                            "APP_INFO_ERROR",
                            e.localizedMessage,
                            e.stackTraceToString(),
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
