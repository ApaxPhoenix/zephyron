package com.aveloux.zephyron

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps the app running in the background so Tor and the onion service stay
 * up and messages can arrive while Zephyron is locked or out of sight. It
 * holds nothing itself; its quiet ongoing notification is what keeps the
 * system from stopping the app.
 */
class Standby : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Alerts.channels(this)
        val notification = Alerts.standing(this)
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                Alerts.STANDBY,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING,
            )
        } else {
            startForeground(Alerts.STANDBY, notification)
        }
        // Without the app's process, Tor is gone too, so a restarted service
        // would keep nothing reachable.
        return START_NOT_STICKY
    }
}
