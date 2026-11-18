package com.notchbridge.android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.util.Log

/**
 * Foreground service whose only job is to keep the process (and its Wi-Fi socket) alive,
 * so Samsung's battery manager and Doze don't kill the connection to the Mac.
 */
class BridgeService : Service() {
    private val listener: (Bridge.Status) -> Unit = { s ->
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification(s))
    }

    override fun onCreate() {
        super.onCreate()
        startForeground(NOTIFICATION_ID, buildNotification(Bridge.status), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        Bridge.addStatusListener(listener)
        Bridge.start()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Bridge.start()
        return START_STICKY
    }

    override fun onDestroy() {
        Bridge.removeStatusListener(listener)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(s: Bridge.Status): Notification {
        val text = when (s.state) {
            Bridge.State.NOT_PAIRED -> "Not paired — open the app to scan the Mac's QR code"
            Bridge.State.SEARCHING -> "Looking for ${s.macName ?: "your Mac"} on Wi-Fi…"
            Bridge.State.CONNECTING -> "Connecting to ${s.macName ?: "your Mac"}…"
            Bridge.State.CONNECTED -> "Sending notifications to ${s.macName ?: "your Mac"}"
            Bridge.State.KEY_REJECTED -> "The Mac was re-paired — scan its QR code again"
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat)
            .setContentTitle("NotchBridge")
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }

    companion object {
        const val CHANNEL_ID = "bridge_status"
        private const val NOTIFICATION_ID = 1

        fun createChannel(ctx: Context) {
            val channel = NotificationChannel(CHANNEL_ID, "Connection status", NotificationManager.IMPORTANCE_MIN).apply {
                description = "Shows whether the phone is connected to your Mac"
                setShowBadge(false)
            }
            ctx.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }

        fun start(ctx: Context) {
            if (PairingStore.load(ctx) == null) return
            try {
                ctx.startForegroundService(Intent(ctx, BridgeService::class.java))
            } catch (e: Exception) {
                // Android 12+ refuses background FGS starts unless battery optimisation is off.
                // The listener service still keeps the connection going in that case, just less reliably.
                Log.w("NotchBridge", "could not start foreground service", e)
                Bridge.start()
            }
        }
    }
}
