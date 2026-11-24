package com.notchbridge.android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.service.notification.StatusBarNotification
import android.util.Log
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.toByteString
import org.json.JSONArray
import org.json.JSONObject
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.TimeUnit

/**
 * Keeps an encrypted WebSocket to the paired Mac and forwards notifications over it.
 *
 * All mutable state lives on one background thread ([handler]); public methods just post to it.
 * Finding the Mac: try the last known IP first, then Bonjour/NSD discovery, then retry with backoff.
 */
object Bridge {
    enum class State { NOT_PAIRED, SEARCHING, CONNECTING, CONNECTED, KEY_REJECTED }
    data class Status(val state: State, val macName: String?)

    private const val TAG = "NotchBridge"
    private const val SERVICE_TYPE = "_notchbridge._tcp."
    private const val BAD_KEY_CODE = 4001
    private const val DISCOVERY_TIMEOUT_MS = 8_000L
    private const val MAX_RETRY_MS = 10_000L
    private const val OUTBOX_LIMIT = 40
    /** Notifications missed while disconnected still pop on the Mac if they are at most this old. */
    private const val MISSED_ALERT_WINDOW_MS = 120_000L

    private lateinit var app: Context
    private val thread = HandlerThread("notchbridge").apply { start() }
    private val handler = Handler(thread.looper)
    private val main = Handler(Looper.getMainLooper())
    private val http = OkHttpClient.Builder()
        .connectTimeout(4, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .pingInterval(15, TimeUnit.SECONDS)
        .build()

    @Volatile var status = Status(State.NOT_PAIRED, null)
        private set
    private val statusListeners = CopyOnWriteArrayList<(Status) -> Unit>()

    @Volatile var listenerService: NotificationCaptureService? = null

    // ---- bridge-thread state ----
    private var initialized = false
    private var socket: WebSocket? = null
    private var generation = 0
    private var retryDelayMs = 2_000L
    private var pendingRetry: Runnable? = null
    private var discovery: NsdManager.DiscoveryListener? = null
    private var discoveryTimeout: Runnable? = null
    private var resolving = false
    private var crypto: Crypto? = null
    private val iconsSent = HashSet<String>()

    /** Notifications posted while the Mac was unreachable, delivered when it comes back (newest copy per key). */
    private class Pending(val sbn: StatusBarNotification, val silent: Boolean, val alert: Boolean, val at: Long)
    private val outbox = LinkedHashMap<String, Pending>()

    private var batteryLevel = -1
    private var batteryCharging = false

    fun init(context: Context) {
        if (initialized) return
        initialized = true
        app = context.applicationContext
        if (PairingStore.load(app) != null) status = Status(State.SEARCHING, PairingStore.load(app)?.macName)
        watchNetwork()
        watchBattery()
        PhoneFinder.onRingingChanged = { on ->
            handler.post { if (status.state == State.CONNECTED) send(JSONObject().put("type", "ringing").put("on", on)) }
        }
    }

    // ---- public API (any thread) ----

    fun addStatusListener(l: (Status) -> Unit) {
        statusListeners.add(l)
        main.post { l(status) }
    }

    fun removeStatusListener(l: (Status) -> Unit) {
        statusListeners.remove(l)
    }

    /** Start or nudge the connection. Safe to call often. */
    fun start() = handler.post {
        if (socket == null && pendingRetry == null && discovery == null && status.state != State.KEY_REJECTED) {
            connectNow()
        }
    }

    /** New pairing saved: drop everything and reconnect with the new key. */
    fun repaired() = handler.post {
        disconnect()
        setStatus(State.SEARCHING, PairingStore.load(app)?.macName)
        retryDelayMs = 2_000L
        connectNow()
    }

    fun unpair() = handler.post {
        disconnect()
        outbox.clear()
        PairingStore.clear(app)
        setStatus(State.NOT_PAIRED, null)
    }

    fun listenerAttached() = handler.post {
        if (status.state == State.CONNECTED) sendSync()
    }

    fun posted(sbn: StatusBarNotification, silent: Boolean, alert: Boolean) = handler.post {
        if (status.state != State.CONNECTED) {
            // Mac asleep / Wi-Fi blip / reconnecting: keep it and deliver after "welcome".
            outbox.remove(sbn.key)
            outbox[sbn.key] = Pending(sbn, silent, alert, SystemClock.elapsedRealtime())
            while (outbox.size > OUTBOX_LIMIT) outbox.remove(outbox.keys.first())
            return@post
        }
        sendPosted(sbn, silent, alert)
    }

    fun removed(key: String) = handler.post {
        outbox.remove(key)
        if (status.state == State.CONNECTED) send(JSONObject().put("type", "removed").put("key", key))
    }

    private fun sendPosted(sbn: StatusBarNotification, silent: Boolean, alert: Boolean) {
        val firstFromApp = iconsSent.add(sbn.packageName)
        val n = runCatching { NotificationMapper.toJson(app, sbn, silent, alert, includeAppIcon = firstFromApp) }
            .onFailure { Log.w(TAG, "map failed", it) }.getOrNull() ?: return
        send(JSONObject().put("type", "posted").put("n", n))
    }

    /** Deliver what arrived while disconnected. Only recent ones may pop; older ones just go in the list. */
    private fun flushOutbox() {
        if (outbox.isEmpty()) return
        val now = SystemClock.elapsedRealtime()
        Log.i(TAG, "delivering ${outbox.size} notifications missed while disconnected")
        for (p in outbox.values) {
            sendPosted(p.sbn, p.silent, p.alert && now - p.at <= MISSED_ALERT_WINDOW_MS)
        }
        outbox.clear()
    }

    fun sendTest() = handler.post {
        if (status.state != State.CONNECTED) return@post
        val n = JSONObject()
            .put("key", "test-${System.currentTimeMillis()}")
            .put("pkg", app.packageName)
            .put("app", "NotchBridge")
            .put("title", "Test from ${Build.MODEL}")
            .put("text", "If you can read this in your Mac's notch, everything works. 🎉")
            .put("time", System.currentTimeMillis())
            .put("actions", JSONArray())
            .put("alert", true)
        send(JSONObject().put("type", "posted").put("n", n))
    }

    // ---- connection logic (bridge thread) ----

    private fun connectNow() {
        cancelRetry()
        val cfg = PairingStore.load(app) ?: run { setStatus(State.NOT_PAIRED, null); return }
        crypto = Crypto(cfg.key)
        val host = cfg.lastHost
        if (host != null) openSocket(host, cfg.port, cfg, discoverOnFailure = true) else discover(cfg)
    }

    private fun openSocket(host: String, port: Int, cfg: PairingConfig, discoverOnFailure: Boolean) {
        stopDiscovery()
        socket?.cancel()
        val gen = ++generation
        setStatus(State.CONNECTING, cfg.macName)
        val hostPart = if (host.contains(':') && !host.startsWith("[")) "[$host]" else host
        val request = Request.Builder().url("ws://$hostPart:$port/").build()
        Log.i(TAG, "connecting to $hostPart:$port")
        socket = http.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) = onBridge(gen) {
                PairingStore.updateAddress(app, host, port)
                send(JSONObject()
                    .put("type", "hello")
                    .put("device", deviceName())
                    .put("model", Build.MODEL))
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) = onBridge(gen) {
                val json = runCatching { JSONObject(String(crypto!!.open(bytes.toByteArray()))) }
                    .getOrNull() ?: return@onBridge
                handleCommand(json)
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(1000, null)
                if (code == BAD_KEY_CODE) onBridge(gen) {
                    Log.w(TAG, "Mac rejected our key")
                    setStatus(State.KEY_REJECTED, cfg.macName)
                }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) =
                onBridge(gen) { connectionLost(cfg, discoverOnFailure) }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) =
                onBridge(gen) {
                    Log.i(TAG, "socket failure: ${t.message}")
                    connectionLost(cfg, discoverOnFailure)
                }
        })
    }

    /** Runs [block] on the bridge thread only if this callback belongs to the current socket. */
    private fun onBridge(gen: Int, block: () -> Unit) {
        handler.post { if (gen == generation) block() }
    }

    private fun connectionLost(cfg: PairingConfig, discoverOnFailure: Boolean) {
        val wasConnected = status.state == State.CONNECTED
        socket = null
        iconsSent.clear()
        if (status.state == State.KEY_REJECTED) return
        when {
            wasConnected -> { retryDelayMs = 1_000L; scheduleRetry(cfg) }
            discoverOnFailure -> discover(cfg)
            else -> scheduleRetry(cfg)
        }
    }

    private fun handleCommand(json: JSONObject) {
        when (json.optString("type")) {
            "welcome" -> {
                retryDelayMs = 2_000L
                setStatus(State.CONNECTED, json.optString("name").ifBlank { status.macName })
                // Missed notifications first (they may pop), then the full list (which never pops).
                flushOutbox()
                sendSync()
                sendBattery()
                if (PhoneFinder.isRinging) send(JSONObject().put("type", "ringing").put("on", true))
            }
            "ring" -> {
                PhoneFinder.ring(app)
                send(JSONObject().put("type", "result").put("ok", true).put("msg", "Ringing your phone"))
            }
            "ring_stop" -> PhoneFinder.stop(app)
            "dismiss", "action", "reply" -> {
                val result = listenerService?.perform(json)
                    ?: if (json.optString("type") == "dismiss") null
                    else (false to "Notification access is off on the phone")
                if (result != null) {
                    send(JSONObject().put("type", "result").put("ok", result.first).put("msg", result.second))
                }
            }
        }
    }

    private fun sendSync() {
        val svc = listenerService ?: return
        val list = JSONArray()
        for ((sbn, silent) in svc.forwardable()) {
            val first = iconsSent.add(sbn.packageName)
            runCatching { NotificationMapper.toJson(app, sbn, silent, alert = false, includeAppIcon = first) }
                .getOrNull()?.let(list::put)
        }
        send(JSONObject().put("type", "sync").put("list", list))
    }

    private fun send(obj: JSONObject) {
        val ws = socket ?: return
        val box = crypto?.seal(obj.toString().toByteArray()) ?: return
        ws.send(box.toByteString())
    }

    private fun disconnect() {
        generation++
        socket?.close(1000, null)
        socket = null
        stopDiscovery()
        cancelRetry()
        iconsSent.clear()
    }

    private fun scheduleRetry(cfg: PairingConfig) {
        cancelRetry()
        setStatus(State.SEARCHING, cfg.macName)
        val r = Runnable { pendingRetry = null; connectNow() }
        pendingRetry = r
        handler.postDelayed(r, retryDelayMs)
        retryDelayMs = (retryDelayMs * 2).coerceAtMost(MAX_RETRY_MS)
    }

    private fun cancelRetry() {
        pendingRetry?.let(handler::removeCallbacks)
        pendingRetry = null
    }

    // ---- Bonjour / NSD discovery ----

    private val nsd: NsdManager get() = app.getSystemService(Context.NSD_SERVICE) as NsdManager

    private fun discover(cfg: PairingConfig) {
        stopDiscovery()
        setStatus(State.SEARCHING, cfg.macName)
        val gen = generation
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onServiceLost(service: NsdServiceInfo) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) = handler.post {
                Log.w(TAG, "discovery failed: $errorCode")
                if (gen == generation) { discovery = null; scheduleRetry(cfg) }
            }.let { }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onServiceFound(service: NsdServiceInfo) = handler.post {
                if (gen == generation && discovery != null) resolve(service, cfg, gen)
            }.let { }
        }
        discovery = listener
        runCatching { nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener) }
            .onFailure { discovery = null; scheduleRetry(cfg); return }
        val timeout = Runnable {
            if (discovery === listener) {
                Log.i(TAG, "Mac not found on this network")
                stopDiscovery()
                scheduleRetry(cfg)
            }
        }
        discoveryTimeout = timeout
        handler.postDelayed(timeout, DISCOVERY_TIMEOUT_MS)
    }

    @Suppress("DEPRECATION")
    private fun resolve(service: NsdServiceInfo, cfg: PairingConfig, gen: Int) {
        if (resolving) return
        resolving = true
        nsd.resolveService(service, object : NsdManager.ResolveListener {
            override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {
                handler.post { resolving = false }
            }

            override fun onServiceResolved(info: NsdServiceInfo) {
                handler.post {
                    resolving = false
                    if (gen != generation || discovery == null) return@post
                    val id = info.attributes["id"]?.let { String(it) }
                    val matches = if (id != null) id == cfg.macId else info.serviceName == cfg.macName
                    val host = hostOf(info)
                    if (matches && host != null) {
                        Log.i(TAG, "found ${info.serviceName} at $host:${info.port}")
                        openSocket(host, info.port, cfg, discoverOnFailure = false)
                    }
                }
            }
        })
    }

    @Suppress("DEPRECATION")
    private fun hostOf(info: NsdServiceInfo): String? {
        val addrs: List<InetAddress> =
            if (Build.VERSION.SDK_INT >= 34) info.hostAddresses else listOfNotNull(info.host)
        val a = addrs.firstOrNull { it is Inet4Address } ?: addrs.firstOrNull() ?: return null
        return if (a is Inet6Address) a.hostAddress?.substringBefore('%') else a.hostAddress
    }

    private fun stopDiscovery() {
        discoveryTimeout?.let(handler::removeCallbacks)
        discoveryTimeout = null
        discovery?.let { runCatching { nsd.stopServiceDiscovery(it) } }
        discovery = null
        resolving = false
    }

    // ---- battery ----

    private fun watchBattery() {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) = onBattery(intent)
        }
        val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        val sticky = if (Build.VERSION.SDK_INT >= 33) {
            app.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            app.registerReceiver(receiver, filter)
        }
        sticky?.let(::onBattery)
    }

    private fun onBattery(i: Intent) {
        val level = i.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = i.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
        if (level < 0 || scale <= 0) return
        val pct = level * 100 / scale
        val st = i.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val charging = st == BatteryManager.BATTERY_STATUS_CHARGING || st == BatteryManager.BATTERY_STATUS_FULL
        handler.post {
            // ACTION_BATTERY_CHANGED also fires for temperature/voltage; only report real changes.
            if (pct == batteryLevel && charging == batteryCharging) return@post
            batteryLevel = pct
            batteryCharging = charging
            sendBattery()
        }
    }

    private fun sendBattery() {
        if (status.state != State.CONNECTED || batteryLevel < 0) return
        send(JSONObject().put("type", "battery").put("level", batteryLevel).put("charging", batteryCharging))
    }

    // ---- misc ----

    /** Reconnect promptly when Wi-Fi comes back instead of waiting for the backoff timer. */
    private fun watchNetwork() {
        val cm = app.getSystemService(ConnectivityManager::class.java)
        val request = NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI).build()
        cm.registerNetworkCallback(request, object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                handler.post {
                    if (socket == null && status.state != State.KEY_REJECTED && PairingStore.load(app) != null) {
                        retryDelayMs = 2_000L
                        connectNow()
                    }
                }
            }
        })
    }

    private fun deviceName(): String =
        android.provider.Settings.Global.getString(app.contentResolver, "device_name")
            ?: "${Build.MANUFACTURER} ${Build.MODEL}"

    private fun setStatus(state: State, macName: String?) {
        val s = Status(state, macName)
        if (s == status) return
        status = s
        main.post { statusListeners.forEach { it(s) } }
    }
}
