package com.sayantan.habitloop.habit_loop

import android.content.Context

/**
 * "You're doomscrolling" reminder.
 *
 * It counts reels in a row — one scrolling session across all tracked apps,
 * ended by a break of [SESSION_BREAK_MS] — and fires on the first reel past
 * the user's number (the 11th with 10), then every that-many reels after
 * (21st, 31st, …) while the session goes on.
 */
class DoomscrollReminder(private val context: Context) {
    private companion object {
        const val NOTIFICATION_ID = 0x5EE15
        const val SESSION_BREAK_MS = 5 * 60 * 1000L
    }

    private var sessionReels = 0
    private var lastReelAt = 0L
    private var remindedAt = 0

    /** Called for every counted reel, with the time it was counted (elapsed realtime). */
    fun onCounted(by: Int, now: Long) {
        if (now - lastReelAt > SESSION_BREAK_MS) {
            sessionReels = 0
            remindedAt = 0
        }
        lastReelAt = now
        sessionReels += by

        val every = ReelsStore.remindEvery(context)
        if (every <= 0 || sessionReels <= every) return
        // Reminders fall on every+1, 2*every+1, … — the latest one reached:
        val threshold = every + 1 + ((sessionReels - every - 1) / every) * every
        if (remindedAt >= threshold) return
        remindedAt = threshold

        // The reel on screen isn't finished yet, so it isn't part of the count.
        val watched = sessionReels - 1
        ReelsNotifications.post(
            context,
            ReelsNotifications.DOOMSCROLL,
            NOTIFICATION_ID,
            "You're doomscrolling",
            "$watched reels in a row. Time for a break?",
        )
    }
}
