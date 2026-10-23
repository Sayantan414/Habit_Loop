package com.sayantan.habitloop.habit_loop

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

/**
 * Posts the reels counter's own notifications (doomscrolling reminder, reels
 * habit target) from native code, so they arrive mid-scroll without waking
 * Flutter. Tapping one opens Habit Loop.
 */
object ReelsNotifications {
    class Channel(val id: String, val name: String, val description: String)

    val DOOMSCROLL = Channel(
        "doomscroll_reminder",
        "Doomscrolling reminder",
        "Lets you know when you've been scrolling reels for a while",
    )
    val HABIT_TARGET = Channel(
        "reels_habit_target",
        "Reels habit target",
        "Tells you when you go over your reels habit's daily target",
    )

    fun post(context: Context, channel: Channel, notificationId: Int, title: String, text: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return

        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(channel.id, channel.name, NotificationManager.IMPORTANCE_HIGH)
                    .apply { description = channel.description }
            )
            Notification.Builder(context, channel.id)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
        }

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
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setCategory(Notification.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .apply { if (tapIntent != null) setContentIntent(tapIntent) }
            .build()

        manager.notify(notificationId, notification)
    }
}
