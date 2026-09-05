package com.aveloux.zephyron

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Notifications with the platform's own manager. They say who wrote and how
 * many messages there are, never what they say, and on the lock screen they
 * hide even the name.
 */
object Alerts {
    const val MESSAGES = "messages"
    const val STANDING = "standing"
    const val STANDBY = 1

    private fun manager(context: Context) =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    fun channels(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = manager(context)
        manager.createNotificationChannel(
            NotificationChannel(MESSAGES, "Messages", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Who sent you messages and how many, never what they say"
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(STANDING, "Staying reachable", NotificationManager.IMPORTANCE_MIN).apply {
                description = "Keeps your address online while Zephyron is locked"
                setShowBadge(false)
            },
        )
    }

    private fun builder(context: Context, channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, channel)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

    private fun opener(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    fun standing(context: Context): Notification =
        builder(context, STANDING)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle("Zephyron")
            .setContentText("Ready to receive messages")
            .setOngoing(true)
            .setContentIntent(opener(context))
            .build()

    fun show(context: Context, id: Int, title: String, text: String) {
        channels(context)
        val hidden = builder(context, MESSAGES)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle("Zephyron")
            .setContentText("New messages")
            .build()
        val notification = builder(context, MESSAGES)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(hidden)
            .setContentIntent(opener(context))
            .build()
        manager(context).notify(id, notification)
    }

    fun cancel(context: Context, id: Int) = manager(context).cancel(id)
}
