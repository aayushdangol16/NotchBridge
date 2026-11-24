package com.notchbridge.android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import android.util.Base64
import android.util.Log
import android.webkit.MimeTypeMap
import org.json.JSONObject
import java.io.OutputStream

/**
 * Receives files sent from the Mac's Shelf ("file_begin" / "file_chunk" / "file_end") and saves them to
 * Downloads/NotchBridge through MediaStore (no storage permission needed on Android 10+).
 * All calls happen on the Bridge thread.
 */
object FileReceiver {
    private const val TAG = "NotchBridge"
    private const val CHANNEL_ID = "files"
    private const val FOLDER = "NotchBridge"

    private class Incoming(
        val id: String,
        val name: String,
        val mime: String,
        val size: Long,
        val uri: Uri,
        val out: OutputStream,
        var received: Long = 0,
        var nextSeq: Int = 0,
    )

    private val active = HashMap<String, Incoming>()
    private var notificationId = 100

    fun createChannel(ctx: Context) {
        val channel = NotificationChannel(CHANNEL_ID, "Files from your Mac", NotificationManager.IMPORTANCE_DEFAULT)
        ctx.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    /** Returns an error result to send back, or null when the transfer started. */
    fun begin(ctx: Context, json: JSONObject): JSONObject? {
        val id = json.optString("id")
        val name = sanitize(json.optString("name").ifBlank { "file" })
        val mime = json.optString("mime").takeIf { it.isNotBlank() && it != "application/octet-stream" }
            ?: MimeTypeMap.getSingleton().getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase())
            ?: "application/octet-stream"
        abort(ctx, id)
        return try {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/$FOLDER")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val resolver = ctx.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: return result(id, false, "Couldn't create the file on the phone", name)
            val out = resolver.openOutputStream(uri)
                ?: return result(id, false, "Couldn't open the file on the phone", name)
            active[id] = Incoming(id, name, mime, json.optLong("size"), uri, out)
            null
        } catch (e: Exception) {
            Log.w(TAG, "file_begin failed", e)
            result(id, false, "Couldn't save on the phone: ${e.message}", name)
        }
    }

    /** Returns an error result if the chunk could not be written. */
    fun chunk(ctx: Context, json: JSONObject): JSONObject? {
        val f = active[json.optString("id")] ?: return null
        return try {
            if (json.optInt("seq", -1) != f.nextSeq) throw IllegalStateException("chunk out of order")
            val bytes = Base64.decode(json.optString("data"), Base64.DEFAULT)
            f.out.write(bytes)
            f.received += bytes.size
            f.nextSeq++
            null
        } catch (e: Exception) {
            Log.w(TAG, "file_chunk failed", e)
            abort(ctx, f.id)
            result(f.id, false, "Transfer failed on the phone: ${e.message}", f.name)
        }
    }

    fun end(ctx: Context, json: JSONObject): JSONObject {
        val f = active.remove(json.optString("id"))
            ?: return result(json.optString("id"), false, "The phone lost track of that file")
        return try {
            f.out.close()
            ctx.contentResolver.update(f.uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
            notifySaved(ctx, f)
            result(f.id, true, "Saved to Downloads/$FOLDER on the phone", f.name)
        } catch (e: Exception) {
            Log.w(TAG, "file_end failed", e)
            runCatching { ctx.contentResolver.delete(f.uri, null, null) }
            result(f.id, false, "Couldn't finish saving: ${e.message}", f.name)
        }
    }

    /** Connection dropped: delete half-written files. */
    fun abortAll(ctx: Context) {
        active.keys.toList().forEach { abort(ctx, it) }
    }

    private fun abort(ctx: Context, id: String) {
        val f = active.remove(id) ?: return
        runCatching { f.out.close() }
        runCatching { ctx.contentResolver.delete(f.uri, null, null) }
    }

    private fun notifySaved(ctx: Context, f: Incoming) {
        val open = Intent(Intent.ACTION_VIEW)
            .setDataAndType(f.uri, f.mime)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        val pi = PendingIntent.getActivity(ctx, notificationId, open, PendingIntent.FLAG_IMMUTABLE)
        val n = Notification.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat)
            .setContentTitle("Received from your Mac")
            .setContentText(f.name)
            .setContentIntent(pi)
            .setAutoCancel(true)
            .build()
        runCatching { ctx.getSystemService(NotificationManager::class.java).notify(notificationId++, n) }
    }

    private fun sanitize(name: String): String =
        name.replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"), "_").take(120).ifBlank { "file" }

    private fun result(id: String, ok: Boolean, msg: String, name: String? = null): JSONObject =
        JSONObject().put("type", "file_result").put("id", id).put("ok", ok).put("msg", msg).apply {
            if (name != null) put("name", name)
        }
}
