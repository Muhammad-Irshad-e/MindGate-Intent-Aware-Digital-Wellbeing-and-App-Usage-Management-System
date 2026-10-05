package com.mindgate.mindgate

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager

/**
 * Native handler to retrieve installed launchable applications.
 *
 * Privacy & Scope Guarantees:
 * - Only queries launchable application package names and display labels.
 * - Does NOT access messages, screen content, contacts, history, personal files, or keyboard input.
 * - Filters out non-launchable system background services and internal OS components.
 */
class AppInfoHandler(private val context: Context) {

    /**
     * Returns a list of maps representing user-accessible installed applications.
     *
     * Each map contains:
     * - `packageName` (String) — Android package identifier (e.g. "com.google.android.youtube")
     * - `appName`     (String) — User-visible application label (e.g. "YouTube")
     */
    fun getInstalledApps(): List<Map<String, String>> {
        val packageManager = context.packageManager
        val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }

        val resolveInfos = try {
            packageManager.queryIntentActivities(mainIntent, 0)
        } catch (_: Exception) {
            emptyList()
        }

        val appsList = mutableListOf<Map<String, String>>()
        val seenPackages = mutableSetOf<String>()

        for (resolveInfo in resolveInfos) {
            val packageName = resolveInfo.activityInfo.packageName
            if (packageName.isNullOrBlank() || seenPackages.contains(packageName)) {
                continue
            }

            seenPackages.add(packageName)

            val appName = try {
                resolveInfo.loadLabel(packageManager).toString()
            } catch (_: Exception) {
                packageName
            }

            appsList.add(
                mapOf(
                    "packageName" to packageName,
                    "appName" to appName,
                )
            )
        }

        return appsList.sortedBy { it["appName"]?.lowercase() }
    }
}
