package com.sayantan.habitloop.habit_loop

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * "10 min left" style alerts for screen-time habits, posted natively so they
 * arrive while the user is in Instagram or YouTube, with Habit Loop closed.
 *
 * There is no background service. Each check reads today's usage, posts any
 * threshold the user has crossed, and sets one alarm for the earliest moment
 * the next threshold could be crossed: foreground time can grow by at most a
 * minute per minute, so a habit with 25 minutes left can't reach "10 min left"
 * sooner than 15 minutes from now. While the user stays off those apps the
 * alarm just keeps getting pushed out, so checks are rare until they matter.
 */
object ScreenTimeAlerts {
    /** Minutes left at which to alert, largest first. */
    private val THRESHOLDS = listOf(10, 5, 1)

    private const val PREFS = "screen_time_alerts"
    private const val KEY_LIMITS = "limits"
    private const val KEY_DAY = "notified_day"
    private const val KEY_NOTIFIED = "notified"
    private const val CHANNEL_ID = "screen_time_alerts"
    private const val ALARM_REQUEST = 7301

    /** Never check more often than this, so a burst of alarms can't spin. */
    private const val MIN_DELAY_MS = 30_000L

    private class Limit(
        val id: String,
        val title: String,
        val minutes: Int,
        val apps: Set<String>,
    )

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /**
     * Replaces the running screen-time habits (`{id, title, limit, apps}`
     * maps from Flutter) and re-checks at once. An empty list stops alerts.
     */
    fun setLimits(context: Context, limits: List<Map<String, Any?>>) {
        val json = JSONArray()
        for (limit in limits) {
            val apps = (limit["apps"] as? List<*>)?.filterIsInstance<String>() ?: continue
            json.put(
                JSONObject()
                    .put("id", limit["id"] as? String ?: continue)
                    .put("title", limit["title"] as? String ?: "")
                    .put("limit", (limit["limit"] as? Number)?.toInt() ?: continue)
                    .put("apps", JSONArray(apps))
            )
        }
        prefs(context).edit().putString(KEY_LIMITS, json.toString()).apply()
        check(context)
    }

    private fun limits(context: Context): List<Limit> {
        val raw = prefs(context).getString(KEY_LIMITS, null) ?: return emptyList()
        val json = try {
            JSONArray(raw)
        } catch (e: Exception) {
            return emptyList()
        }
        return (0 until json.length()).map { i ->
            val o = json.getJSONObject(i)
            val apps = o.getJSONArray("apps")
            Limit(
                id = o.getString("id"),
                title = o.getString("title"),
                minutes = o.getInt("limit"),
                apps = (0 until apps.length()).map { apps.getString(it) }.toSet(),
            )
        }
    }

    /** Posts any crossed threshold, then sets the alarm for the next check. */
    fun check(context: Context) {
        val limits = limits(context)
        if (limits.isEmpty() || !UsageChannel.hasPermission(context)) {
            cancelAlarm(context)
            return
        }

        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        val p = prefs(context)
        // Which "habit|threshold" alerts went out today; reset on a new day.
        val notified = if (p.getString(KEY_DAY, null) == today) {
            p.getStringSet(KEY_NOTIFIED, emptySet())!!.toMutableSet()
        } else {
            mutableSetOf()
        }

        val usage = UsageChannel.usageMillis(
            context, limits.flatMap { it.apps }.toSet(), days = 1,
        )[today] ?: emptyMap()

        var nextDelay = Long.MAX_VALUE
        for (limit in limits) {
            val used = limit.apps.sumOf { usage[it] ?: 0L }
            val leftMs = limit.minutes * 60_000L - used
            // A 5-minute limit starts below "10 min left"; skip what it can't cross.
            val thresholds = THRESHOLDS.filter { it < limit.minutes }
            val crossed = thresholds.filter {
                leftMs <= it * 60_000L && "${limit.id}|$it" !in notified
            }
            if (crossed.isNotEmpty()) {
                // Mark every crossed threshold, but post only once: someone
                // who jumps from 12 to 4 minutes left gets one alert, not two.
                crossed.forEach { notified.add("${limit.id}|$it") }
                if (leftMs > 0) post(context, limit, leftMs)
            }
            // The next threshold this habit hasn't reached yet.
            val next = thresholds.firstOrNull { leftMs > it * 60_000L }
            if (next != null) nextDelay = minOf(nextDelay, leftMs - next * 60_000L)
        }

        p.edit()
            .putString(KEY_DAY, today)
            .putStringSet(KEY_NOTIFIED, notified)
            .apply()

        // Nothing left to alert today: start again just after midnight.
        val delay = if (nextDelay == Long.MAX_VALUE) {
            msUntilMidnight() + 60_000L
        } else {
            minOf(nextDelay, msUntilMidnight() + 60_000L)
        }
        setAlarm(context, maxOf(delay, MIN_DELAY_MS))
    }

    private fun msUntilMidnight(): Long {
        val midnight = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        return midnight.timeInMillis - System.currentTimeMillis()
    }

    private fun alarmIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        ALARM_REQUEST,
        Intent(context, ScreenTimeAlarmReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun setAlarm(context: Context, delayMs: Long) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val at = System.currentTimeMillis() + delayMs
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            alarms.canScheduleExactAlarms()
        if (exact) {
            alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, alarmIntent(context))
        } else {
            // Without exact-alarm access Android may run it a few minutes late.
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, alarmIntent(context))
        }
    }

    private fun cancelAlarm(context: Context) {
        context.getSystemService(AlarmManager::class.java)?.cancel(alarmIntent(context))
    }

    private fun post(context: Context, limit: Limit, leftMs: Long) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return

        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Screen time alerts",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Tells you when a screen-time habit has 10, 5 " +
                        "and 1 minute left for the day"
                }
            )
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
        }

        // Rounded up, so 4 min 10 s left reads "5 min left".
        val minutes = ((leftMs + 59_999L) / 60_000L).toInt()
        val left = if (minutes == 1) "1 minute left" else "$minutes minutes left"
        val notificationId = limit.id.hashCode()
        val openApp = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val tapIntent = openApp?.let {
            PendingIntent.getActivity(
                context, notificationId, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_habit)
            .setContentTitle("$left today")
            .setContentText(limit.title)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .apply { if (tapIntent != null) setContentIntent(tapIntent) }
            .build()

        // One notification per habit, replaced as time runs down.
        manager.notify(notificationId, notification)
    }
}

/** Runs [ScreenTimeAlerts.check] when its alarm fires, after a reboot and after an app update. */
class ScreenTimeAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        Thread {
            try {
                ScreenTimeAlerts.check(context.applicationContext)
            } finally {
                pending.finish()
            }
        }.start()
    }
}
