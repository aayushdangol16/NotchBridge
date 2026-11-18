package com.notchbridge.android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Restarts the connection after a reboot or an app update. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        BridgeService.start(context)
    }
}
