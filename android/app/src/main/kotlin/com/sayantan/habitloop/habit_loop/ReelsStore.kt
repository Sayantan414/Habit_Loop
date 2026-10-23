package com.sayantan.habitloop.habit_loop

import android.content.Context
import android.content.SharedPreferences
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Plain SharedPreferences storage shared by [ReelsCounterService] and
 * [ReelsChannel]. The service writes here on its own, so counting keeps
 * working while the Flutter engine is not running; Flutter only reads.
 *
 * Counts are stored one key per day and app: `count_<yyyy-MM-dd>|<package>`.
 */
object ReelsStore {
    private const val PREFS = "reels_counter"
    private const val KEY_SELECTED = "selected_apps"
    private const val KEY_LOG = "detection_log"
    private const val KEY_LAST_PRUNE = "last_prune"
    private const val KEY_REMIND_EVERY = "remind_every"
    private const val KEY_HABIT_TARGET = "habit_target"
    private const val KEY_HABIT_ALERT_DAY = "habit_alert_day"
    private const val COUNT_PREFIX = "count_"
    private const val KEEP_DAYS = 60
    private const val LOG_LINES = 40

    /** Reels in a row before the doomscrolling reminder; 0 turns it off. */
    const val DEFAULT_REMIND_EVERY = 10

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun dayKey(date: Date): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(date)

    fun selectedApps(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_SELECTED, emptySet())?.toSet() ?: emptySet()

    fun setSelectedApps(context: Context, packages: Set<String>) {
        prefs(context).edit().putStringSet(KEY_SELECTED, packages.toSet()).apply()
    }

    fun increment(context: Context, packageName: String, by: Int = 1) {
        val p = prefs(context)
        val today = dayKey(Date())
        val key = "$COUNT_PREFIX$today|$packageName"
        val editor = p.edit().putInt(key, p.getInt(key, 0) + by)
        if (p.getString(KEY_LAST_PRUNE, null) != today) {
            pruneOldCounts(p, editor)
            editor.putString(KEY_LAST_PRUNE, today)
        }
        editor.apply()
    }

    /** Today's reels across all tracked apps. */
    fun totalToday(context: Context): Int {
        val todayPrefix = "$COUNT_PREFIX${dayKey(Date())}|"
        return prefs(context).all.entries.sumOf { (key, value) ->
            if (key.startsWith(todayPrefix) && value is Int) value else 0
        }
    }

    /** Daily target of the active reels habit (set from Flutter); 0 = no reels habit. */
    fun habitTarget(context: Context): Int = prefs(context).getInt(KEY_HABIT_TARGET, 0)

    fun setHabitTarget(context: Context, target: Int) {
        prefs(context).edit().putInt(KEY_HABIT_TARGET, target.coerceAtLeast(0)).apply()
    }

    /** True the first time it's called on a day, so the over-target alert shows once a day. */
    fun claimHabitAlertForToday(context: Context): Boolean {
        val p = prefs(context)
        val today = dayKey(Date())
        if (p.getString(KEY_HABIT_ALERT_DAY, null) == today) return false
        p.edit().putString(KEY_HABIT_ALERT_DAY, today).apply()
        return true
    }

    fun remindEvery(context: Context): Int =
        prefs(context).getInt(KEY_REMIND_EVERY, DEFAULT_REMIND_EVERY)

    fun setRemindEvery(context: Context, reels: Int) {
        prefs(context).edit().putInt(KEY_REMIND_EVERY, reels.coerceAtLeast(0)).apply()
    }

    /** Returns `{ "yyyy-MM-dd": { package: count } }` for the last [days] days. */
    fun counts(context: Context, days: Int): Map<String, Map<String, Int>> {
        val wanted = lastDayKeys(days).toSet()
        val result = HashMap<String, HashMap<String, Int>>()
        for ((key, value) in prefs(context).all) {
            if (!key.startsWith(COUNT_PREFIX) || value !is Int) continue
            val (day, pkg) = key.removePrefix(COUNT_PREFIX).split('|', limit = 2)
                .takeIf { it.size == 2 } ?: continue
            if (day !in wanted) continue
            result.getOrPut(day) { HashMap() }[pkg] = value
        }
        return result
    }

    /** One line per newly seen scroll container, newest first, for calibration. */
    fun appendLog(context: Context, line: String) {
        val p = prefs(context)
        val lines = listOf(line) + (p.getString(KEY_LOG, null)?.split('\n') ?: emptyList())
        p.edit().putString(KEY_LOG, lines.take(LOG_LINES).joinToString("\n")).apply()
    }

    fun log(context: Context): List<String> =
        prefs(context).getString(KEY_LOG, null)?.split('\n')?.filter { it.isNotBlank() }
            ?: emptyList()

    fun clearLog(context: Context) {
        prefs(context).edit().remove(KEY_LOG).apply()
    }

    private fun lastDayKeys(days: Int): List<String> {
        val cal = Calendar.getInstance()
        return (0 until days).map {
            dayKey(cal.time).also { cal.add(Calendar.DAY_OF_YEAR, -1) }
        }
    }

    private fun pruneOldCounts(p: SharedPreferences, editor: SharedPreferences.Editor) {
        val keep = lastDayKeys(KEEP_DAYS).toSet()
        for (key in p.all.keys) {
            if (!key.startsWith(COUNT_PREFIX)) continue
            val day = key.removePrefix(COUNT_PREFIX).substringBefore('|')
            if (day !in keep) editor.remove(key)
        }
    }
}
