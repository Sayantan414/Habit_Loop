package com.sayantan.habitloop.habit_loop

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Flutter ↔ native bridge for the reels counter (`habitloop/reels`). */
object ReelsChannel {
    private const val NAME = "habitloop/reels"

    fun register(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "isServiceEnabled" -> result.success(isServiceEnabled(app))

                "openAccessibilitySettings" -> {
                    context.startActivity(
                        Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(null)
                }

                "installedApps" -> {
                    val packages = call.argument<List<String>>("packages") ?: emptyList()
                    // Visibility of these packages is granted by <queries> in the manifest.
                    result.success(packages.filter {
                        app.packageManager.getLaunchIntentForPackage(it) != null
                    })
                }

                "getSelectedApps" -> result.success(ReelsStore.selectedApps(app).toList())

                "setSelectedApps" -> {
                    val packages = call.argument<List<String>>("packages") ?: emptyList()
                    ReelsStore.setSelectedApps(app, packages.toSet())
                    ReelsCounterService.instance?.applySelectedApps()
                    result.success(null)
                }

                "getCounts" -> {
                    val days = call.argument<Int>("days") ?: 7
                    result.success(ReelsStore.counts(app, days))
                }

                "setHabitTarget" -> {
                    ReelsStore.setHabitTarget(app, call.argument<Int>("target") ?: 0)
                    result.success(null)
                }

                "getRemindEvery" -> result.success(ReelsStore.remindEvery(app))

                "setRemindEvery" -> {
                    ReelsStore.setRemindEvery(app, call.argument<Int>("reels") ?: 0)
                    result.success(null)
                }

                "getDetectionLog" -> result.success(ReelsStore.log(app))

                "clearDetectionLog" -> {
                    ReelsStore.clearLog(app)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun isServiceEnabled(context: Context): Boolean {
        val expected = ComponentName(context, ReelsCounterService::class.java)
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabled.split(':').any { ComponentName.unflattenFromString(it) == expected }
    }
}
