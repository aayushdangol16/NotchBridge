package com.notchbridge.android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log

/**
 * "Find my phone": plays the alarm sound at full alarm volume (audible even in silent mode),
 * vibrates, and shows a Stop notification. Stops after [RING_MS], from the notification, or from the Mac.
 */
object PhoneFinder {
    private const val TAG = "NotchBridge"
    private const val CHANNEL_ID = "find_phone"
    private const val NOTIFICATION_ID = 2
    private const val RING_MS = 30_000L

    private val main = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var savedAlarmVolume = -1
    private val autoStop = Runnable { appContext?.let { stop(it) } }
    private var appContext: Context? = null

    /** Called with true when ringing starts and false when it stops (any reason). */
    var onRingingChanged: (Boolean) -> Unit = {}

    val isRinging: Boolean get() = player != null

    fun createChannel(ctx: Context) {
        val channel = NotificationChannel(CHANNEL_ID, "Find my phone", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Shown while your Mac is making the phone ring"
            setSound(null, null)
        }
        ctx.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    fun ring(context: Context) {
        main.post { ringNow(context) }
    }

    private fun ringNow(context: Context) {
        val ctx = context.applicationContext
        appContext = ctx
        if (player != null) return
        val audio = ctx.getSystemService(AudioManager::class.java)
        savedAlarmVolume = audio.getStreamVolume(AudioManager.STREAM_ALARM)
        runCatching {
            audio.setStreamVolume(AudioManager.STREAM_ALARM, audio.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0)
        }

        val uri = RingtoneManager.getActualDefaultRingtoneUri(ctx, RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        player = runCatching {
            MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                setDataSource(ctx, uri)
                isLooping = true
                prepare()
                start()
            }
        }.onFailure { Log.w(TAG, "could not play alarm", it) }.getOrNull()

        @Suppress("DEPRECATION")
        ctx.getSystemService(Vibrator::class.java)?.vibrate(
            VibrationEffect.createWaveform(longArrayOf(0, 700, 500), 0),
        )

        showNotification(ctx)
        main.removeCallbacks(autoStop)
        main.postDelayed(autoStop, RING_MS)
        onRingingChanged(true)
    }

    fun stop(context: Context) {
        main.post { stopNow(context) }
    }

    private fun stopNow(context: Context) {
        val ctx = context.applicationContext
        main.removeCallbacks(autoStop)
        val wasRinging = player != null
        player?.runCatching { stop(); release() }
        player = null
        ctx.getSystemService(Vibrator::class.java)?.cancel()
        if (savedAlarmVolume >= 0) {
            runCatching {
                ctx.getSystemService(AudioManager::class.java)
                    .setStreamVolume(AudioManager.STREAM_ALARM, savedAlarmVolume, 0)
            }
            savedAlarmVolume = -1
        }
        ctx.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
        if (wasRinging) onRingingChanged(false)
    }

    private fun showNotification(ctx: Context) {
        val stopIntent = PendingIntent.getBroadcast(
            ctx, 0, Intent(ctx, StopReceiver::class.java), PendingIntent.FLAG_IMMUTABLE,
        )
        val n = Notification.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat)
            .setContentTitle("Your Mac is looking for this phone")
            .setContentText("Tap to stop ringing")
            .setContentIntent(stopIntent)
            .setDeleteIntent(stopIntent)
            .addAction(Notification.Action.Builder(null, "Stop", stopIntent).build())
            .setCategory(Notification.CATEGORY_ALARM)
            .build()
        runCatching { ctx.getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, n) }
    }

    /** Stop button / tap / swipe-away of the ringing notification. */
    class StopReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            stop(context)
        }
    }
}
