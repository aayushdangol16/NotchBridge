package com.notchbridge.android

import android.app.Notification
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.service.notification.StatusBarNotification
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream

/** Turns a StatusBarNotification into the JSON the Mac expects (see mac/.../Models.swift). */
object NotificationMapper {
    private val labelCache = HashMap<String, String>()

    /** Whether a notification is worth showing on the Mac at all. */
    fun shouldForward(ownPackage: String, sbn: StatusBarNotification): Boolean {
        if (sbn.packageName == ownPackage) return false
        val n = sbn.notification
        if (sbn.isOngoing) return false                                        // music, downloads, navigation…
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return false     // "3 new messages" summaries
        if (n.flags and Notification.FLAG_FOREGROUND_SERVICE != 0) return false
        val e = n.extras
        return !(e.getCharSequence(Notification.EXTRA_TITLE).isNullOrBlank() &&
            e.getCharSequence(Notification.EXTRA_TEXT).isNullOrBlank())
    }

    fun toJson(ctx: Context, sbn: StatusBarNotification, silent: Boolean, includeAppIcon: Boolean): JSONObject {
        val n = sbn.notification
        val e = n.extras
        val title = e.getCharSequence(Notification.EXTRA_TITLE_BIG) ?: e.getCharSequence(Notification.EXTRA_TITLE)
        val text = e.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: e.getCharSequence(Notification.EXTRA_TEXT)
        val sub = e.getCharSequence(Notification.EXTRA_SUB_TEXT)

        val actions = JSONArray()
        n.actions?.forEachIndexed { i, a ->
            val reply = a.remoteInputs?.any { it.allowFreeFormInput } == true
            actions.put(JSONObject().put("i", i).put("title", a.title?.toString() ?: "").put("reply", reply))
        }

        val json = JSONObject()
            .put("key", sbn.key)
            .put("pkg", sbn.packageName)
            .put("app", appLabel(ctx, sbn.packageName))
            .put("title", title?.toString() ?: "")
            .put("text", text?.toString() ?: "")
            .put("time", sbn.postTime)
            .put("actions", actions)
            .put("silent", silent)
            .put("alertOnce", n.flags and Notification.FLAG_ONLY_ALERT_ONCE != 0)
        if (!sub.isNullOrBlank()) json.put("sub", sub.toString())

        if (includeAppIcon) {
            runCatching { ctx.packageManager.getApplicationIcon(sbn.packageName).toPngBase64(96) }
                .getOrNull()?.let { json.put("icon", it) }
        }
        runCatching { n.getLargeIcon()?.loadDrawable(ctx)?.toPngBase64(96) }
            .getOrNull()?.let { json.put("large", it) }
        return json
    }

    fun appLabel(ctx: Context, pkg: String): String = labelCache.getOrPut(pkg) {
        try {
            val pm = ctx.packageManager
            pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
        } catch (_: PackageManager.NameNotFoundException) {
            pkg
        }
    }

    private fun Drawable.toPngBase64(size: Int): String {
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val d = mutate()
        d.setBounds(0, 0, size, size)
        d.draw(Canvas(bmp))
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
        bmp.recycle()
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    }
}
