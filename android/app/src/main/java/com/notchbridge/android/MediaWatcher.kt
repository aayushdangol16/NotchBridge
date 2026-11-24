package com.notchbridge.android

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Base64
import android.util.Log
import org.json.JSONObject
import java.io.ByteArrayOutputStream

/**
 * Follows the phone's active media session (Spotify, YouTube Music, …) and reports it to the Mac as
 * "media" messages; executes play/pause/next/previous from the Mac. Allowed because we are an enabled
 * notification listener (MediaSessionManager.getActiveSessions needs that).
 */
object MediaWatcher {
    private const val TAG = "NotchBridge"
    private val main = Handler(Looper.getMainLooper())

    private lateinit var app: Context
    private var manager: MediaSessionManager? = null
    private var listenerComponent: ComponentName? = null
    private var controller: MediaController? = null
    private var lastSignature = ""
    private var lastSentAt = 0L
    private var artCache: Pair<String, String>? = null   // artId -> base64

    private val sessionsListener = MediaSessionManager.OnActiveSessionsChangedListener { list -> pick(list.orEmpty()) }

    private val callback = object : MediaController.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadata?) = report()
        override fun onPlaybackStateChanged(state: PlaybackState?) = report()
        override fun onSessionDestroyed() {
            bind(null)
            refresh()
        }
    }

    fun start(context: Context, component: ComponentName) = main.post {
        app = context.applicationContext
        listenerComponent = component
        val m = app.getSystemService(MediaSessionManager::class.java)
        manager = m
        try {
            m.removeOnActiveSessionsChangedListener(sessionsListener)
            m.addOnActiveSessionsChangedListener(sessionsListener, component, main)
            pick(m.getActiveSessions(component))
        } catch (e: SecurityException) {
            Log.w(TAG, "media sessions unavailable (notification access off?)", e)
        }
    }

    private fun refresh() {
        val m = manager ?: return
        val c = listenerComponent ?: return
        runCatching { pick(m.getActiveSessions(c)) }
    }

    /** Prefer a session that is playing; otherwise the most recent one. */
    private fun pick(sessions: List<MediaController>) {
        val best = sessions.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING } ?: sessions.firstOrNull()
        if (best?.sessionToken != controller?.sessionToken) bind(best)
        report()
    }

    private fun bind(c: MediaController?) {
        controller?.unregisterCallback(callback)
        controller = c
        c?.registerCallback(callback, main)
    }

    fun command(cmd: String, pos: Double = -1.0) = main.post {
        val c = controller ?: return@post
        val t = c.transportControls
        when (cmd) {
            "toggle" -> if (c.playbackState?.state == PlaybackState.STATE_PLAYING) t.pause() else t.play()
            "next" -> t.skipToNext()
            "prev" -> t.skipToPrevious()
            "seek" -> if (pos >= 0) {
                t.seekTo((pos * 1000).toLong())
                lastSignature = ""      // report the new position promptly
            }
        }
    }

    /** Build the payload and hand it to the bridge, skipping no-op position ticks. */
    private fun report() {
        val c = controller
        val meta = c?.metadata
        val title = meta?.getString(MediaMetadata.METADATA_KEY_TITLE)
            ?: meta?.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)
        if (c == null || meta == null || title.isNullOrBlank()) {
            if (lastSignature != "none") {
                lastSignature = "none"
                Bridge.media(JSONObject().put("active", false))
            }
            return
        }
        val state = c.playbackState
        val playing = state?.state == PlaybackState.STATE_PLAYING
        val artist = meta.getString(MediaMetadata.METADATA_KEY_ARTIST)
            ?: meta.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
            ?: meta.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE) ?: ""
        val album = meta.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: ""
        val durationMs = meta.getLong(MediaMetadata.METADATA_KEY_DURATION)

        // Position: PlaybackState gives it at an elapsedRealtime instant; convert to wall-clock.
        val now = System.currentTimeMillis()
        val posMs = state?.position ?: 0L
        val updatedAt = state?.lastPositionUpdateTime ?: SystemClock.elapsedRealtime()
        val positionAt = now - (SystemClock.elapsedRealtime() - updatedAt)
        val speed = state?.playbackSpeed?.takeIf { it > 0f } ?: 1f

        // Only send when something meaningful changed (state/track) or the position jumped (seek).
        val signature = "$title|$artist|$album|$playing|$durationMs"
        val predicted = if (playing) posMs + (now - positionAt) * speed else posMs.toFloat()
        val seeked = kotlin.math.abs(predicted - posMs) > 2_500 && now - lastSentAt > 1_000
        if (signature == lastSignature && !seeked) return
        lastSignature = signature
        lastSentAt = now

        val json = JSONObject()
            .put("active", true)
            .put("title", title)
            .put("artist", artist)
            .put("album", album)
            .put("playing", playing)
            .put("position", posMs / 1000.0)
            .put("positionAt", positionAt / 1000.0)
            .put("rate", speed.toDouble())
            .put("pkg", c.packageName)
            .put("app", label(c.packageName))
        if (durationMs > 0) json.put("duration", durationMs / 1000.0)

        val bmp = meta.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: meta.getBitmap(MediaMetadata.METADATA_KEY_ART)
            ?: meta.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)
        if (bmp != null) {
            val artId = "$title|$artist|$album".hashCode().toString()
            val b64 = artCache?.takeIf { it.first == artId }?.second ?: encode(bmp).also { artCache = artId to it }
            json.put("artId", artId).put("art", b64)
        }
        Bridge.media(json)
    }

    private fun encode(bmp: Bitmap): String {
        val side = 160
        val scaled = Bitmap.createScaledBitmap(bmp, side, side * bmp.height / bmp.width.coerceAtLeast(1), true)
        val out = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, 82, out)
        if (scaled !== bmp) scaled.recycle()
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    }

    private fun label(pkg: String): String = try {
        val pm = app.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (_: PackageManager.NameNotFoundException) {
        pkg
    }
}
