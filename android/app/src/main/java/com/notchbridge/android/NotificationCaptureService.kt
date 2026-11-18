package com.notchbridge.android

import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONObject

/**
 * Receives every notification posted on the phone (after the user grants "Notification access")
 * and hands the interesting ones to [Bridge]. Also executes dismiss / action / reply commands from the Mac.
 */
class NotificationCaptureService : NotificationListenerService() {

    override fun onListenerConnected() {
        Bridge.listenerService = this
        Bridge.listenerAttached()
        BridgeService.start(this)
    }

    override fun onListenerDisconnected() {
        if (Bridge.listenerService === this) Bridge.listenerService = null
        // Ask the system to bind us again (it sometimes unbinds after app updates or memory pressure).
        requestRebind(ComponentName(this, NotificationCaptureService::class.java))
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (!NotificationMapper.shouldForward(packageName, sbn)) return
        Bridge.posted(sbn, isSilent(sbn))
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        if (sbn.packageName == packageName) return
        Bridge.removed(sbn.key)
    }

    /** Current notifications worth mirroring, with their "silent" flag. Called on the bridge thread. */
    fun forwardable(): List<Pair<StatusBarNotification, Boolean>> =
        runCatching { activeNotifications.orEmpty() }.getOrDefault(emptyArray())
            .filter { NotificationMapper.shouldForward(packageName, it) }
            .map { it to isSilent(it) }

    private fun isSilent(sbn: StatusBarNotification): Boolean {
        val ranking = Ranking()
        return runCatching {
            currentRanking.getRanking(sbn.key, ranking) && ranking.importance < NotificationManager.IMPORTANCE_DEFAULT
        }.getOrDefault(false)
    }

    /**
     * Runs a command from the Mac. Returns (ok, message) to report back, or null for no report.
     */
    fun perform(cmd: JSONObject): Pair<Boolean, String>? {
        val key = cmd.optString("key")
        return when (cmd.optString("type")) {
            "dismiss" -> {
                runCatching { cancelNotification(key) }
                null
            }
            "action" -> {
                val action = find(key)?.notification?.actions?.getOrNull(cmd.optInt("i", -1))
                    ?: return false to "That notification is gone on the phone"
                try {
                    action.actionIntent.send()
                    true to "Done"
                } catch (e: PendingIntent.CanceledException) {
                    false to "The app cancelled that action"
                }
            }
            "reply" -> reply(key, cmd.optInt("i", -1), cmd.optString("text"))
            else -> null
        }
    }

    private fun reply(key: String, index: Int, text: String): Pair<Boolean, String> {
        val action = find(key)?.notification?.actions?.getOrNull(index)
            ?: return false to "That notification is gone on the phone"
        val inputs = action.remoteInputs?.takeIf { it.isNotEmpty() }
            ?: return false to "This app doesn't accept replies"
        val results = Bundle().apply { inputs.forEach { putCharSequence(it.resultKey, text) } }
        val fillIn = Intent()
        RemoteInput.addResultsToIntent(inputs, fillIn, results)
        return try {
            action.actionIntent.send(this, 0, fillIn)
            true to "Reply sent"
        } catch (e: PendingIntent.CanceledException) {
            Log.w(TAG, "reply failed", e)
            false to "The app rejected the reply"
        }
    }

    private fun find(key: String): StatusBarNotification? =
        runCatching { activeNotifications?.firstOrNull { it.key == key } }.getOrNull()

    private companion object {
        const val TAG = "NotchBridge"
    }
}
