package com.notchbridge.android

import android.content.Context
import android.net.Uri
import android.util.Base64

data class PairingConfig(
    val macId: String,
    val macName: String,
    val key: ByteArray,
    val lastHost: String?,
    val port: Int,
)

/** Pairing data from the Mac's QR code, kept in app-private SharedPreferences. */
object PairingStore {
    private const val PREFS = "pairing"

    /** Parses `notchbridge://pair?v=1&id=…&name=…&key=…&host=…&port=…`. */
    fun parse(raw: String?): PairingConfig? {
        val uri = runCatching { Uri.parse(raw?.trim()) }.getOrNull() ?: return null
        if (uri.scheme != "notchbridge" || uri.host != "pair") return null
        val id = uri.getQueryParameter("id")?.takeIf { it.isNotBlank() } ?: return null
        val key = runCatching {
            Base64.decode(uri.getQueryParameter("key"), Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
        }.getOrNull()?.takeIf { it.size == 32 } ?: return null
        return PairingConfig(
            macId = id,
            macName = uri.getQueryParameter("name") ?: "Mac",
            key = key,
            lastHost = uri.getQueryParameter("host")?.takeIf { it.isNotBlank() },
            port = uri.getQueryParameter("port")?.toIntOrNull() ?: 47821,
        )
    }

    fun load(ctx: Context): PairingConfig? {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val id = p.getString("id", null) ?: return null
        val key = p.getString("key", null)?.let { Base64.decode(it, Base64.NO_WRAP) } ?: return null
        return PairingConfig(
            macId = id,
            macName = p.getString("name", "Mac")!!,
            key = key,
            lastHost = p.getString("host", null),
            port = p.getInt("port", 47821),
        )
    }

    fun save(ctx: Context, c: PairingConfig) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("id", c.macId)
            .putString("name", c.macName)
            .putString("key", Base64.encodeToString(c.key, Base64.NO_WRAP))
            .putString("host", c.lastHost)
            .putInt("port", c.port)
            .apply()
    }

    fun updateAddress(ctx: Context, host: String, port: Int) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("host", host)
            .putInt("port", port)
            .apply()
    }

    fun clear(ctx: Context) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }
}
