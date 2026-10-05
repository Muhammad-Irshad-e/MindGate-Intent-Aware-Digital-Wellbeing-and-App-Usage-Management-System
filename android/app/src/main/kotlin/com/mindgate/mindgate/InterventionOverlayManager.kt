package com.mindgate.mindgate

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Android-native system overlay manager for MindGate's Intervention UI.
 *
 * Renders an accessibility / system-level window overlay above the currently foreground
 * restricted application (e.g. Instagram) without requiring MindGate's Flutter Activity
 * to be in the foreground.
 *
 * Visually mirrors the exact design of [InterventionScreen]:
 * - Warning icon badge (red circle with warning symbol)
 * - "Usage Limit Reached" title
 * - Detailed usage text with app name and category
 * - White grace period countdown card displaying "MM : SS"
 * - "Take a Break" solid button
 * - "Snooze" outlined button (when snooze is enabled)
 */
class InterventionOverlayManager private constructor() {

    companion object {
        @Volatile
        private var instance: InterventionOverlayManager? = null

        fun getInstance(): InterventionOverlayManager {
            return instance ?: synchronized(this) {
                instance ?: InterventionOverlayManager().also { instance = it }
            }
        }
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var currentPackageName: String? = null
    private var handler: Handler = Handler(Looper.getMainLooper())
    private var timerRunnable: Runnable? = null
    private var remainingSecondsState: Int = 0

    var onTakeBreakCallback: (() -> Unit)? = null
    var onSnoozeCallback: (() -> Unit)? = null

    val isShowing: Boolean
        get() = overlayView != null

    fun getActivePackage(): String? = currentPackageName

    /**
     * Shows or updates the system overlay for [packageName].
     */
    fun showOverlay(
        context: Context,
        packageName: String,
        appName: String,
        categoryName: String,
        usedMinutes: Int,
        remainingSeconds: Int,
        snoozeEnabled: Boolean,
        snoozeDuration: Int,
        onTakeBreak: (() -> Unit)? = null,
        onSnooze: (() -> Unit)? = null,
    ) {
        handler.post {
            onTakeBreakCallback = onTakeBreak
            onSnoozeCallback = onSnooze
            remainingSecondsState = remainingSeconds

            if (overlayView != null && currentPackageName == packageName) {
                // Overlay already active for this package — update countdown/text if needed
                updateCountdownText()
                return@post
            }

            // Remove any existing overlay view first
            hideOverlayInternal()

            val wm = context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
                ?: return@post
            windowManager = wm
            currentPackageName = packageName

            val layoutParams = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                        WindowManager.LayoutParams.FLAG_FULLSCREEN,
                PixelFormat.TRANSLUCENT
            )
            layoutParams.gravity = Gravity.CENTER

            val rootLayout = buildOverlayView(
                context = context,
                appName = appName,
                categoryName = categoryName,
                usedMinutes = usedMinutes,
                snoozeEnabled = snoozeEnabled,
                snoozeDuration = snoozeDuration
            )

            overlayView = rootLayout

            try {
                wm.addView(rootLayout, layoutParams)
                startTimer()
            } catch (e: Exception) {
                // Fallback to TYPE_APPLICATION_OVERLAY if TYPE_ACCESSIBILITY_OVERLAY fails
                // (e.g. when called from MainActivity/Flutter context instead of AccessibilityService)
                try {
                    layoutParams.type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                    } else {
                        @Suppress("DEPRECATION")
                        WindowManager.LayoutParams.TYPE_PHONE
                    }
                    wm.addView(rootLayout, layoutParams)
                    startTimer()
                } catch (e2: Exception) {
                    overlayView = null
                    currentPackageName = null
                }
            }
        }
    }

    /**
     * Hides and removes the active overlay from [WindowManager].
     */
    fun hideOverlay() {
        handler.post {
            hideOverlayInternal()
        }
    }

    private fun hideOverlayInternal() {
        stopTimer()
        val view = overlayView
        val wm = windowManager
        if (view != null && wm != null) {
            try {
                wm.removeView(view)
            } catch (_: Exception) {}
        }
        overlayView = null
        windowManager = null
        currentPackageName = null
    }

    private fun startTimer() {
        stopTimer()
        timerRunnable = object : Runnable {
            override fun run() {
                if (remainingSecondsState > 0) {
                    remainingSecondsState--
                    updateCountdownText()
                    handler.postDelayed(this, 1000L)
                } else {
                    updateCountdownText()
                }
            }
        }
        handler.postDelayed(timerRunnable!!, 1000L)
    }

    private fun stopTimer() {
        timerRunnable?.let { handler.removeCallbacks(it) }
        timerRunnable = null
    }

    private fun updateCountdownText() {
        val timerTv = overlayView?.findViewWithTag<TextView>("timer_text_view")
        if (timerTv != null) {
            val mins = String.format("%02d", remainingSecondsState / 60)
            val secs = String.format("%02d", remainingSecondsState % 60)
            timerTv.text = "$mins : $secs"
        }
    }

    private fun buildOverlayView(
        context: Context,
        appName: String,
        categoryName: String,
        usedMinutes: Int,
        snoozeEnabled: Boolean,
        snoozeDuration: Int
    ): View {
        val density = context.resources.displayMetrics.density
        fun dp(value: Float): Int = (value * density + 0.5f).toInt()

        // Root container - background #FFF0F0
        val root = FrameLayout(context).apply {
            setBackgroundColor(Color.parseColor("#FFF0F0"))
            isClickable = true
            isFocusable = true
        }

        val contentLayout = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24f), dp(32f), dp(24f), dp(32f))
        }

        val rootParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
            Gravity.CENTER
        )
        root.addView(contentLayout, rootParams)

        // Spacer / top weight
        val topSpacer = View(context)
        contentLayout.addView(topSpacer, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f
        ))

        // Warning Icon in Red Badge Circle
        val badge = FrameLayout(context).apply {
            val bgDrawable = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#E53935")) // AppColors.negative
            }
            background = bgDrawable
        }
        val iconView = ImageView(context).apply {
            setImageResource(android.R.drawable.ic_dialog_alert)
            setColorFilter(Color.WHITE)
        }
        badge.addView(iconView, FrameLayout.LayoutParams(dp(44f), dp(44f), Gravity.CENTER))
        contentLayout.addView(badge, LinearLayout.LayoutParams(dp(72f), dp(72f)))

        // Spacing
        contentLayout.addView(View(context), LinearLayout.LayoutParams(1, dp(24f)))

        // Title
        val titleTv = TextView(context).apply {
            text = "Usage Limit Reached"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.parseColor("#1E293B")) // AppColors.textPrimary
            gravity = Gravity.CENTER
        }
        contentLayout.addView(titleTv)

        // Spacing
        contentLayout.addView(View(context), LinearLayout.LayoutParams(1, dp(12f)))

        // Explanation text
        val catText = if (categoryName.isNotBlank()) " ($categoryName)" else ""
        val subtitleTv = TextView(context).apply {
            text = "You've used $appName$catText for $usedMinutes minutes today.\nTake a break and focus on what matters!"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTextColor(Color.parseColor("#64748B")) // AppColors.textSecondary
            gravity = Gravity.CENTER
            setLineSpacing(0f, 1.4f)
        }
        contentLayout.addView(subtitleTv)

        // Spacing
        contentLayout.addView(View(context), LinearLayout.LayoutParams(1, dp(36f)))

        // Countdown / Grace Period Display Card
        val cardLayout = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(0, dp(20f), 0, dp(20f))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                setColor(Color.WHITE)
                cornerRadius = dp(20f).toFloat()
                setStroke(dp(1f), Color.parseColor("#FFCDD2"))
            }
        }

        val mins = String.format("%02d", remainingSecondsState / 60)
        val secs = String.format("%02d", remainingSecondsState % 60)
        val timerTv = TextView(context).apply {
            tag = "timer_text_view"
            text = "$mins : $secs"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 36f)
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.parseColor("#1E293B"))
            gravity = Gravity.CENTER
            letterSpacing = 0.05f
        }
        cardLayout.addView(timerTv)

        cardLayout.addView(View(context), LinearLayout.LayoutParams(1, dp(4f)))

        val timerSubTv = TextView(context).apply {
            text = "(Grace Period)"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setTextColor(Color.parseColor("#64748B"))
            gravity = Gravity.CENTER
        }
        cardLayout.addView(timerSubTv)

        contentLayout.addView(cardLayout, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ))

        // Spacer / bottom weight
        val bottomSpacer = View(context)
        contentLayout.addView(bottomSpacer, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f
        ))

        // Action Buttons Row
        val buttonRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
        }

        // Take a Break Button
        val takeBreakBtn = Button(context).apply {
            text = "Take a Break"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTypeface(typeface, Typeface.BOLD)
            isAllCaps = false
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                setColor(Color.parseColor("#E53935"))
                cornerRadius = dp(14f).toFloat()
            }
            setOnClickListener {
                hideOverlayInternal()
                onTakeBreakCallback?.invoke()
                navigateToHome(context)
            }
        }
        val btnParams = LinearLayout.LayoutParams(0, dp(48f), 1f)
        buttonRow.addView(takeBreakBtn, btnParams)

        if (snoozeEnabled) {
            buttonRow.addView(View(context), LinearLayout.LayoutParams(dp(12f), 1))

            // Snooze Button
            val snoozeBtn = Button(context).apply {
                text = "Snooze ($snoozeDuration minutes)"
                setTextColor(Color.parseColor("#E53935"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                setTypeface(typeface, Typeface.BOLD)
                isAllCaps = false
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    setColor(Color.TRANSPARENT)
                    cornerRadius = dp(14f).toFloat()
                    setStroke(dp(1.5f), Color.parseColor("#E53935"))
                }
                setOnClickListener {
                    hideOverlayInternal()
                    onSnoozeCallback?.invoke()
                }
            }
            buttonRow.addView(snoozeBtn, LinearLayout.LayoutParams(0, dp(48f), 1f))
        }

        contentLayout.addView(buttonRow, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ))

        contentLayout.addView(View(context), LinearLayout.LayoutParams(1, dp(16f)))

        root.isFocusableInTouchMode = true
        root.requestFocus()
        root.setOnKeyListener { _, keyCode, event ->
            if (keyCode == android.view.KeyEvent.KEYCODE_BACK && event.action == android.view.KeyEvent.ACTION_UP) {
                hideOverlayInternal()
                onTakeBreakCallback?.invoke()
                navigateToHome(context)
                true
            } else false
        }

        return root
    }

    private fun navigateToHome(context: Context) {
        try {
            val homeIntent = android.content.Intent(android.content.Intent.ACTION_MAIN).apply {
                addCategory(android.content.Intent.CATEGORY_HOME)
                flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(homeIntent)
        } catch (_: Exception) {}
    }
}
