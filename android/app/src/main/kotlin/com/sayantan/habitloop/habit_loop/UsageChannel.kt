package com.sayantan.habitloop.habit_loop

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Flutter ↔ native bridge for screen-time habits (`habitloop/usage`).
 *
 * Reads per-app foreground time from [UsageStatsManager]. Needs the Usage
 * access permission, which the user grants in system settings; unlike an
 * accessibility service it can't read the screen, so banking apps don't
 * refuse to open while it is on.
 */
object UsageChannel {
    private const val NAME = "habitloop/usage"
    private const val ICON_SIZE = 96

    /** Usage queries walk days of events, so they run off the main thread. */
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun register(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasPermission(app))

                "openSettings" -> {
                    context.startActivity(
                        Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(null)
                }

                "installedApps" -> background(result) { installedApps(app) }

                "appIcon" -> {
                    val pkg = call.argument<String>("package")
                    if (pkg == null) {
                        result.error("bad_args", "package is required", null)
                    } else {
                        background(result) { appIcon(app, pkg) }
                    }
                }

                "setAlertLimits" -> {
                    val limits = call.argument<List<Map<String, Any?>>>("limits") ?: emptyList()
                    background(result) {
                        ScreenTimeAlerts.setLimits(app, limits)
                        null
                    }
                }

                "dailyUsage" -> {
                    val packages = call.argument<List<String>>("packages")?.toSet() ?: emptySet()
                    val days = (call.argument<Int>("days") ?: 7).coerceIn(1, 31)
                    if (!hasPermission(app)) {
                        result.error("no_permission", "Usage access is not granted", null)
                    } else {
                        background(result) { dailyUsage(app, packages, days) }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("usage_failed", e.message, null) }
            }
        }
    }

    fun hasPermission(context: Context): Boolean {
        val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ops.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName
            )
        } else {
            @Suppress("DEPRECATION")
            ops.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName
            )
        }
        // Some devices report MODE_DEFAULT and leave the answer to the permission itself.
        if (mode == AppOpsManager.MODE_DEFAULT) {
            return context.checkCallingOrSelfPermission(
                android.Manifest.permission.PACKAGE_USAGE_STATS
            ) == PackageManager.PERMISSION_GRANTED
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** Every launchable app except Habit Loop, as `{package, label}`, sorted by label. */
    private fun installedApps(context: Context): List<Map<String, String>> {
        val pm = context.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        // Visibility of other apps is granted by the launcher <queries> entry in the manifest.
        return pm.queryIntentActivities(launcher, 0)
            .map { it.activityInfo.packageName to it.loadLabel(pm).toString() }
            .filter { (pkg, _) -> pkg != context.packageName }
            .distinctBy { (pkg, _) -> pkg }
            .sortedBy { (_, label) -> label.lowercase(Locale.getDefault()) }
            .map { (pkg, label) -> mapOf("package" to pkg, "label" to label) }
    }

    /** The app's launcher icon as PNG bytes, or null if it isn't installed. */
    private fun appIcon(context: Context, pkg: String): ByteArray? {
        val drawable = try {
            context.packageManager.getApplicationIcon(pkg)
        } catch (e: PackageManager.NameNotFoundException) {
            return null
        }
        val bitmap = Bitmap.createBitmap(ICON_SIZE, ICON_SIZE, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, ICON_SIZE, ICON_SIZE)
        drawable.draw(Canvas(bitmap))
        return ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            out.toByteArray()
        }
    }

    /**
     * Foreground minutes per day for [packages] over the last [days] days
     * (today included), as `{ 'yyyy-MM-dd': { package: minutes } }`.
     *
     * Built from raw resume/pause events rather than queryUsageStats(), whose
     * daily buckets don't line up with local midnight. A session spanning
     * midnight is split between the two days, and a session still open now
     * counts up to now. Days with no usage are left out.
     */
    private fun dailyUsage(
        context: Context,
        packages: Set<String>,
        days: Int,
    ): Map<String, Map<String, Int>> =
        usageMillis(context, packages, days).mapValues { (_, perApp) ->
            perApp.mapValues { (_, ms) -> (ms / 60_000L).toInt() }
        }

    /** Like [dailyUsage], in milliseconds: `{ 'yyyy-MM-dd': { package: ms } }`. */
    fun usageMillis(
        context: Context,
        packages: Set<String>,
        days: Int,
    ): Map<String, Map<String, Long>> {
        if (packages.isEmpty()) return emptyMap()
        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val windowStart = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            add(Calendar.DAY_OF_YEAR, -(days - 1))
        }.timeInMillis

        val millis = HashMap<String, HashMap<String, Long>>() // day -> package -> ms
        fun add(pkg: String, from: Long, to: Long) = splitByDay(from, to) { day, ms ->
            val perApp = millis.getOrPut(day) { HashMap() }
            perApp[pkg] = (perApp[pkg] ?: 0L) + ms
        }

        // An app is in the foreground while any of its activities is resumed.
        val resumed = HashMap<String, MutableSet<String>>() // package -> activity classes
        val sessionStart = HashMap<String, Long>()
        val seen = HashSet<String>()

        val events = usm.queryEvents(windowStart, now)
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val pkg = event.packageName ?: continue
            if (pkg !in packages) continue
            val cls = event.className ?: ""
            val firstForApp = seen.add(pkg)
            when {
                isResume(event.eventType) -> {
                    val open = resumed.getOrPut(pkg) { HashSet() }
                    if (open.isEmpty()) sessionStart[pkg] = event.timeStamp
                    open.add(cls)
                }
                isPause(event.eventType) -> {
                    val open = resumed[pkg]
                    when {
                        open != null && open.isNotEmpty() -> {
                            open.remove(cls)
                            if (open.isEmpty()) {
                                add(pkg, sessionStart.remove(pkg) ?: event.timeStamp, event.timeStamp)
                            }
                        }
                        // Already in the foreground when the window opened.
                        firstForApp -> add(pkg, windowStart, event.timeStamp)
                    }
                }
            }
        }
        // Sessions still running right now.
        for ((pkg, start) in sessionStart) add(pkg, start, now)

        return millis
    }

    // ACTIVITY_RESUMED/PAUSED (API 29) share their values with the older
    // MOVE_TO_FOREGROUND/BACKGROUND, so these checks work on every version.
    @Suppress("DEPRECATION")
    private fun isResume(type: Int) = type == UsageEvents.Event.MOVE_TO_FOREGROUND

    @Suppress("DEPRECATION")
    private fun isPause(type: Int) = type == UsageEvents.Event.MOVE_TO_BACKGROUND ||
        (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            type == UsageEvents.Event.ACTIVITY_STOPPED)

    /** Calls [onDay] with (yyyy-MM-dd, ms) for each local day that [from, to) touches. */
    private inline fun splitByDay(from: Long, to: Long, onDay: (String, Long) -> Unit) {
        if (to <= from) return
        val format = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val cal = Calendar.getInstance()
        var start = from
        while (start < to) {
            cal.timeInMillis = start
            cal.set(Calendar.HOUR_OF_DAY, 0)
            cal.set(Calendar.MINUTE, 0)
            cal.set(Calendar.SECOND, 0)
            cal.set(Calendar.MILLISECOND, 0)
            cal.add(Calendar.DAY_OF_YEAR, 1)
            val end = minOf(cal.timeInMillis, to)
            onDay(format.format(start), end - start)
            start = end
        }
    }
}
