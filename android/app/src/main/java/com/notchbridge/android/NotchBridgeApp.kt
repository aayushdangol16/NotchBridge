package com.notchbridge.android

import android.app.Application

class NotchBridgeApp : Application() {
    override fun onCreate() {
        super.onCreate()
        BridgeService.createChannel(this)
        PhoneFinder.createChannel(this)
        Bridge.init(this)
        Bridge.start()
    }
}
