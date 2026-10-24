package com.sayantan.habitloop.habit_loop

import android.accessibilityservice.AccessibilityService
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Counts short videos ("reels") swiped through in the apps the user picked.
 *
 * Two detection paths:
 *
 * - **Scroll-based** (Instagram and most apps): a reel is counted when a
 *   full-screen vertical pager with a reels-style view id moves to a new
 *   item. Feeds are ignored because their container is not full-screen or
 *   has no reels-style id. Containers without a view id are never counted
 *   (except in short-video-only apps): Facebook Lite, for one, draws its feed
 *   and its reels the same way, so they cannot be told apart.
 *
 * - **Page-based** (YouTube): the Shorts pager reports no item indexes, so
 *   on content changes the service looks up the Shorts page currently on
 *   screen and notices when it becomes a different page. Whether that was a
 *   swipe forward or back comes from the pager's scroll deltas, or failing
 *   that from the order of the loaded pages; like Instagram, only reaching a
 *   Short past the furthest one seen in the session counts.
 *
 * Battery: the system only delivers events from the selected packages (see
 * [applySelectedApps]). Content-change events, the noisy kind, are only
 * requested while YouTube is selected, are ignored for every other app, and
 * trigger at most one lookup per [YT_CHECK_INTERVAL_MS] — events in between
 * are folded into one delayed check rather than dropped, so the page a swipe
 * settles on is never missed. Counting is a single SharedPreferences write;
 * Flutter is never woken.
 */
class ReelsCounterService : AccessibilityService() {

    companion object {
        /** Set while the system has the service bound, so the app can push a new selection. */
        @Volatile
        var instance: ReelsCounterService? = null
            private set

        private const val YOUTUBE = "com.google.android.youtube"
        private const val HABIT_ALERT_ID = 0x5EE16

        /** One per Short; the pager keeps neighbours alive, so several may exist off-screen. */
        private const val YT_PAGE_ID = "$YOUTUBE:id/reel_player_page_container"
        private const val YT_CHECK_INTERVAL_MS = 400L

        /** A Short page counts as "the one on screen" once this much of it is visible. */
        private const val YT_VISIBLE_RATIO = 0.75f

        /** Re-check delay and limit while a swipe is still animating (no page fills the screen). */
        private const val YT_SETTLE_DELAY_MS = 250L
        private const val YT_SETTLE_RETRIES = 4

        /**
         * How long after a page change to wait before reading the swipe's
         * direction, so the swipe has finished and its last scroll is in.
         */
        private const val YT_DIRECTION_DELAY_MS = 300L

        /** Short-video-only apps: every full-screen vertical pager is a reels player. */
        private val WHOLE_APP_PACKAGES = setOf(
            "in.mohalla.video",        // Moj
            "com.eterno.shortvideos",  // Josh
        )

        /**
         * Apps that strip their view ids (the log shows "name removed"). Their
         * reels player is told from the feed by shape instead: it fills the
         * screen, scrolls vertically and shows exactly one item at a time,
         * while the feed shows several posts and the tab pager moves sideways.
         */
        private val ID_LESS_PACKAGES = setOf("com.facebook.katana")
        private const val FULL_SCREEN_RATIO = 0.85f

        /** View-id fragments used by reels players (e.g. Instagram `clips_viewer_view_pager`). */
        private val REEL_ID_KEYWORDS = listOf("reel", "clips", "shorts", "spotlight")

        /** Carousels and shelves inside a feed are shorter than this share of the screen. */
        private const val MIN_HEIGHT_RATIO = 0.6f

        /** After this long without reels activity, the next change only sets a new baseline. */
        private const val BASELINE_STALE_MS = 2 * 60 * 1000L

        /** Used only when the app does not report item indexes. */
        private const val FALLBACK_DEBOUNCE_MS = 800L
    }

    /** Index of the reel on screen, and of the furthest reel reached, per app. */
    private val currentIndex = HashMap<String, Int>()
    private val furthestIndex = HashMap<String, Int>()
    private val lastReelsScroll = HashMap<String, Long>()
    private val lastFallbackCount = HashMap<String, Long>()
    private val loggedKeys = HashSet<String>()
    private val reminder = DoomscrollReminder(this)

    private var ytLastCheck = 0L
    private var ytLastSeen = 0L
    private var ytCurrentPage: Int? = null
    private var ytSettleRetries = 0

    /** Position relative to the session's first Short, and the furthest reached. */
    private var ytPosition = 0
    private var ytFurthest = 0

    /** Direction of the Shorts pager's latest scroll: +1 forward, -1 back, 0 none reported. */
    private var ytLastScrollSign = 0

    /** A page change waiting for its direction, and its page-order fallback (0 = unknown). */
    private var ytDirectionPending = false
    private var ytPendingOrderDirection = 0

    private val handler = Handler(Looper.getMainLooper())
    private var ytCheckPending = false
    private val ytCheckRunnable = Runnable {
        ytCheckPending = false
        runYouTubeCheck()
    }
    private val ytDirectionRunnable = Runnable { settleYouTubeChange() }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        applySelectedApps()
    }

    override fun onDestroy() {
        handler.removeCallbacks(ytCheckRunnable)
        handler.removeCallbacks(ytDirectionRunnable)
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onInterrupt() {}

    /**
     * Restricts event delivery to the selected apps. An empty `packageNames`
     * would mean "every app", so an empty selection listens to this app only.
     */
    fun applySelectedApps() {
        val info = serviceInfo ?: return
        val selected = ReelsStore.selectedApps(this)
        info.packageNames = if (selected.isEmpty()) arrayOf(packageName) else selected.toTypedArray()
        info.eventTypes = if (YOUTUBE in selected) {
            AccessibilityEvent.TYPE_VIEW_SCROLLED or AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
        } else {
            AccessibilityEvent.TYPE_VIEW_SCROLLED
        }
        serviceInfo = info
        currentIndex.clear()
        furthestIndex.clear()
        lastReelsScroll.clear()
        lastFallbackCount.clear()
        ytCurrentPage = null
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) return
        // Shows in the log whether an app sends anything at all, which tells
        // "never scrolls" apart from "scrolls, but not recognised as reels".
        logOnce(
            "$pkg|type|${event.eventType}",
            "$pkg · sends ${AccessibilityEvent.eventTypeToString(event.eventType)}",
        )

        // YouTube is counted by page only: its Shorts pager also scrolls, but
        // without item indexes, so the scroll path would count every swipe a
        // second time. A YouTube scroll just prompts an early page check.
        if (pkg == YOUTUBE) {
            if (event.eventType == AccessibilityEvent.TYPE_VIEW_SCROLLED) trackYouTubeScroll(event)
            checkYouTubeShort()
        } else if (event.eventType == AccessibilityEvent.TYPE_VIEW_SCROLLED) {
            onScrolled(pkg, event)
        }
    }

    // ------------------------------------------------------------ scroll-based

    private fun onScrolled(pkg: String, event: AccessibilityEvent) {
        val source = event.source
        if (source == null) {
            logOnce("$pkg|nosource", "$pkg · scroll without view info · ignored")
            return
        }
        val isReels = try {
            isReelsPlayer(pkg, source, event)
        } finally {
            recycle(source)
        }
        if (!isReels) return

        val now = SystemClock.elapsedRealtime()
        val index = event.fromIndex
        if (index >= 0) {
            val stale = now - (lastReelsScroll[pkg] ?: 0L) > BASELINE_STALE_MS
            lastReelsScroll[pkg] = now
            val position = currentIndex[pkg]
            val furthest = furthestIndex[pkg]
            currentIndex[pkg] = index
            when {
                // New session: the first scroll starts on the reel the user
                // opened. Opening sends no event, so that reel is counted now.
                // A jump of more than one reel is a fresh list (left and came
                // back), not a swipe, so it starts a new session too.
                position == null || furthest == null || stale ||
                    kotlin.math.abs(index - position) > 1 -> {
                    furthestIndex[pkg] = index
                    countReel(pkg)
                }
                // Swiped onto a reel not seen yet in this session.
                index > furthest -> {
                    furthestIndex[pkg] = index
                    countReel(pkg)
                }
                // Moving back, or forward again over reels already seen:
                // rewatches don't count.
            }
        } else {
            // No item indexes: count each swipe, plus the opened reel when a
            // session starts. Rewatches can't be told apart here.
            val last = lastFallbackCount[pkg] ?: 0L
            if (now - last >= FALLBACK_DEBOUNCE_MS) {
                lastFallbackCount[pkg] = now
                val sessionStart = now - last > BASELINE_STALE_MS
                countReel(pkg, if (sessionStart) 2 else 1)
            }
        }
    }

    private fun isReelsPlayer(pkg: String, node: AccessibilityNodeInfo, event: AccessibilityEvent): Boolean {
        val id = node.viewIdResourceName?.substringAfter(":id/")?.lowercase(Locale.US) ?: ""
        val ratio = heightRatio(node)
        val className = node.className?.toString()?.substringAfterLast('.') ?: "?"
        val index = event.fromIndex
        // Items on screen; -1 when the app doesn't say.
        val visible = if (index >= 0 && event.toIndex >= index) event.toIndex - index + 1 else -1
        val direction = scrollDirection(event)

        val isReels = when {
            ratio < MIN_HEIGHT_RATIO -> false
            pkg in WHOLE_APP_PACKAGES -> true
            pkg in ID_LESS_PACKAGES ->
                ratio >= FULL_SCREEN_RATIO &&
                    visible == 1 &&
                    direction != Direction.SIDEWAYS &&
                    // Without direction info, a classic ViewPager is a tab pager.
                    (direction == Direction.VERTICAL || className != "ViewPager")
            else -> REEL_ID_KEYWORDS.any { id.contains(it) }
        }

        val heightPct = (ratio * 100).toInt()
        val label = id.ifEmpty { "(no id)" }
        val indexInfo = if (index >= 0) "index" else "no index"
        val items = when {
            visible < 0 -> "items ?"
            visible == 1 -> "1 item"
            else -> "$visible items"
        }
        val verdict = if (isReels) "REELS" else "feed"
        logOnce(
            "$pkg|$id|$className|${heightPct / 5}|${index >= 0}|${visible.coerceAtMost(2)}|$direction|$isReels",
            "$pkg · $label · $className · $heightPct% · $indexInfo · $items · " +
                "${direction.label} · $verdict",
        )
        return isReels
    }

    private enum class Direction(val label: String) {
        VERTICAL("up/down"),
        SIDEWAYS("sideways"),
        UNKNOWN("direction ?"),
    }

    /** Which way the container moved, from the event's scroll deltas (Android 9+). */
    private fun scrollDirection(event: AccessibilityEvent): Direction {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return Direction.UNKNOWN
        // -1 means "not reported".
        val dx = event.scrollDeltaX.takeIf { it != -1 } ?: 0
        val dy = event.scrollDeltaY.takeIf { it != -1 } ?: 0
        return when {
            dx == 0 && dy == 0 -> Direction.UNKNOWN
            kotlin.math.abs(dy) >= kotlin.math.abs(dx) -> Direction.VERTICAL
            else -> Direction.SIDEWAYS
        }
    }

    // -------------------------------------------------------------- page-based

    /** Remembers which way the Shorts pager last moved. */
    private fun trackYouTubeScroll(event: AccessibilityEvent) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return
        val delta = event.scrollDeltaY
        if (delta == 0 || delta == -1) return  // -1 = not reported
        val source = event.source ?: return
        val isShortsPager = try {
            source.viewIdResourceName?.contains("reel") == true
        } finally {
            recycle(source)
        }
        if (isShortsPager) ytLastScrollSign = if (delta > 0) 1 else -1
    }

    private fun checkYouTubeShort() {
        ytSettleRetries = 0
        val wait = YT_CHECK_INTERVAL_MS - (SystemClock.elapsedRealtime() - ytLastCheck)
        if (wait > 0) {
            // Too soon: fold this event into one check at the end of the interval.
            scheduleYouTubeCheck(wait)
            return
        }
        handler.removeCallbacks(ytCheckRunnable)
        ytCheckPending = false
        runYouTubeCheck()
    }

    private fun scheduleYouTubeCheck(delayMs: Long) {
        if (ytCheckPending) return
        ytCheckPending = true
        handler.postDelayed(ytCheckRunnable, delayMs)
    }

    /**
     * Finds the YouTube Short filling the screen and notices when it changes.
     * Pages are told apart by node identity: the pager shows a different
     * page view after every swipe, so the visible page's identity changes.
     */
    private fun runYouTubeCheck() {
        val now = SystemClock.elapsedRealtime()
        ytLastCheck = now

        val root = rootInActiveWindow ?: return
        val pages = try {
            root.findAccessibilityNodeInfosByViewId(YT_PAGE_ID)
        } finally {
            recycle(root)
        }
        if (pages.isNullOrEmpty()) return

        val current = pages.firstOrNull { it.isVisibleToUser && heightRatio(it) >= YT_VISIBLE_RATIO }
        val pageId = current?.hashCode()
        // Tree order is screen order (top to bottom) for the loaded pages.
        val pageOrder = pages.map { it.hashCode() }
        pages.forEach { recycle(it) }
        if (pageId == null) {
            // Mid-swipe: no page fills the screen yet, and the app may send no
            // further event once it settles, so look again shortly.
            if (ytSettleRetries++ < YT_SETTLE_RETRIES) {
                scheduleYouTubeCheck(YT_SETTLE_DELAY_MS)
            }
            return
        }

        logOnce("$YOUTUBE|shorts", "$YOUTUBE · reel_player_page_container · Shorts page · REELS")

        val stale = now - ytLastSeen > BASELINE_STALE_MS
        ytLastSeen = now
        val previous = ytCurrentPage
        ytCurrentPage = pageId

        if (previous == null || stale) {
            // New session: this Short is the baseline.
            handler.removeCallbacks(ytDirectionRunnable)
            ytDirectionPending = false
            ytPosition = 0
            ytFurthest = 0
            ytLastScrollSign = 0
            return
        }
        if (previous == pageId) return

        // A swipe landed on a new page. Settle any earlier change first, then
        // read this one's direction once the swipe has finished moving.
        if (ytDirectionPending) settleYouTubeChange()
        val previousAt = pageOrder.indexOf(previous)
        val currentAt = pageOrder.indexOf(pageId)
        ytPendingOrderDirection = when {
            previousAt < 0 || currentAt < 0 -> 0
            previousAt < currentAt -> 1
            else -> -1
        }
        ytDirectionPending = true
        handler.postDelayed(ytDirectionRunnable, YT_DIRECTION_DELAY_MS)
    }

    /**
     * Applies the pending page change: +1 position for a swipe forward, -1
     * for a swipe back, counting only Shorts past the furthest one reached.
     *
     * The direction is the pager's last scroll movement, since a swipe always
     * ends moving toward the page it lands on. Without scroll info it falls
     * back to page order, and failing that assumes forward, so a new Short is
     * never missed (a rewatch may be counted instead).
     */
    private fun settleYouTubeChange() {
        handler.removeCallbacks(ytDirectionRunnable)
        if (!ytDirectionPending) return
        ytDirectionPending = false

        val (direction, source) = when {
            ytLastScrollSign != 0 -> ytLastScrollSign to "scrolling"
            ytPendingOrderDirection != 0 -> ytPendingOrderDirection to "page order"
            else -> 1 to "unknown"
        }
        ytPosition += direction
        val counted = ytPosition > ytFurthest
        if (counted) {
            ytFurthest = ytPosition
            countReel(YOUTUBE)
        }

        val time = SimpleDateFormat("dd MMM HH:mm:ss", Locale.US).format(Date())
        val way = if (direction > 0) "forward" else "back"
        val result = if (counted) "+1" else "rewatch, not counted"
        ReelsStore.appendLog(this, "$time · YouTube Short · $way (from $source) · $result")
    }

    // ----------------------------------------------------------------- helpers

    /**
     * Records [by] reels for [pkg], reminds the user if they've been scrolling
     * a while, and tells them once a day when they go over their reels habit's
     * target (Flutter marks that day as a slip when the app next opens).
     */
    private fun countReel(pkg: String, by: Int = 1) {
        ReelsStore.increment(this, pkg, by)
        reminder.onCounted(by, SystemClock.elapsedRealtime())

        val target = ReelsStore.habitTarget(this)
        if (target > 0 &&
            ReelsStore.totalToday(this) > target &&
            ReelsStore.claimHabitAlertForToday(this)
        ) {
            ReelsNotifications.post(
                this,
                ReelsNotifications.HABIT_TARGET,
                HABIT_ALERT_ID,
                "Over your $target reels for today",
                "Today counts as a slip on your reels habit. Tomorrow is a fresh start.",
            )
        }
    }

    /** Visible height as a share of the screen (bounds are clipped to what's on screen). */
    private fun heightRatio(node: AccessibilityNodeInfo): Float {
        val bounds = Rect().also { node.getBoundsInScreen(it) }
        val screenHeight = resources.displayMetrics.heightPixels.coerceAtLeast(1)
        return bounds.height().toFloat() / screenHeight
    }

    private fun recycle(node: AccessibilityNodeInfo) {
        @Suppress("DEPRECATION")
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) node.recycle()
    }

    /** Lets every kind of line be logged again, after the user clears the log. */
    fun resetLog() = loggedKeys.clear()

    /** Writes [line] to the detection log once per service run, to help tune detection. */
    private fun logOnce(key: String, line: String) {
        if (!loggedKeys.add(key)) return
        val time = SimpleDateFormat("dd MMM HH:mm", Locale.US).format(Date())
        ReelsStore.appendLog(this, "$time · $line")
    }
}
