package com.notchbridge.android

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning

/** Setup screen: grant access, keep alive, pair, test. */
class MainActivity : Activity() {
    private lateinit var connection: TextView
    private lateinit var accessStatus: TextView
    private lateinit var batteryStatus: TextView
    private lateinit var pairStatus: TextView

    private val statusListener: (Bridge.Status) -> Unit = { render() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        // Android 15 draws edge-to-edge: keep content clear of the status/navigation bars.
        findViewById<View>(R.id.root).setOnApplyWindowInsetsListener { v, insets ->
            val bars = insets.getInsets(android.view.WindowInsets.Type.systemBars())
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }

        connection = findViewById(R.id.connection)
        accessStatus = findViewById(R.id.accessStatus)
        batteryStatus = findViewById(R.id.batteryStatus)
        pairStatus = findViewById(R.id.pairStatus)

        findViewById<Button>(R.id.grantAccess).setOnClickListener { openNotificationAccess() }
        findViewById<Button>(R.id.battery).setOnClickListener { requestBatteryExemption() }
        findViewById<Button>(R.id.appSettings).setOnClickListener {
            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
        }
        findViewById<Button>(R.id.scan).setOnClickListener { scanQr() }
        findViewById<Button>(R.id.useLink).setOnClickListener {
            pair(findViewById<EditText>(R.id.pasteLink).text.toString())
        }
        findViewById<Button>(R.id.unpair).setOnClickListener {
            Bridge.unpair()
            stopService(Intent(this, BridgeService::class.java))
            render()
        }
        findViewById<Button>(R.id.test).setOnClickListener {
            if (Bridge.status.state == Bridge.State.CONNECTED) {
                Bridge.sendTest()
                toast("Sent — look at your Mac's notch")
            } else {
                toast("Not connected to the Mac yet")
            }
        }

        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }

        handlePairingIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handlePairingIntent(intent)
    }

    override fun onStart() {
        super.onStart()
        Bridge.addStatusListener(statusListener)
        BridgeService.start(this)
    }

    override fun onResume() {
        super.onResume()
        render()
    }

    override fun onStop() {
        Bridge.removeStatusListener(statusListener)
        super.onStop()
    }

    private fun render() {
        val s = Bridge.status
        val mac = s.macName ?: "your Mac"
        connection.text = when (s.state) {
            Bridge.State.NOT_PAIRED -> "⚪  Not paired"
            Bridge.State.SEARCHING -> "🟡  Looking for $mac on this Wi-Fi…"
            Bridge.State.CONNECTING -> "🟡  Connecting to $mac…"
            Bridge.State.CONNECTED -> "🟢  Connected to $mac"
            Bridge.State.KEY_REJECTED -> "🔴  $mac was re-paired. Scan its QR code again."
        }

        accessStatus.text = if (hasNotificationAccess()) "✅  Granted" else "❌  Not granted yet"

        val pm = getSystemService(PowerManager::class.java)
        batteryStatus.text = if (pm.isIgnoringBatteryOptimizations(packageName)) {
            "✅  Battery optimisation is off"
        } else {
            "⚠️  Battery optimisation is on — Android may stop the connection"
        }

        val cfg = PairingStore.load(this)
        pairStatus.text = if (cfg == null) "Not paired" else "Paired with ${cfg.macName}"
        findViewById<Button>(R.id.unpair).visibility = if (cfg == null) View.GONE else View.VISIBLE
    }

    private fun hasNotificationAccess(): Boolean =
        getSystemService(NotificationManager::class.java)
            .isNotificationListenerAccessGranted(ComponentName(this, NotificationCaptureService::class.java))

    private fun openNotificationAccess() {
        val component = ComponentName(this, NotificationCaptureService::class.java)
        val detail = Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
            .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, component.flattenToString())
        try {
            if (Build.VERSION.SDK_INT >= 30) startActivity(detail)
            else startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        } catch (_: Exception) {
            startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        }
    }

    @android.annotation.SuppressLint("BatteryLife")
    private fun requestBatteryExemption() {
        try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")),
            )
        } catch (_: Exception) {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }

    private fun scanQr() {
        val options = GmsBarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .build()
        GmsBarcodeScanning.getClient(this, options).startScan()
            .addOnSuccessListener { pair(it.rawValue) }
            .addOnFailureListener { toast("Scanner unavailable: ${it.message}. Paste the link instead.") }
    }

    private fun handlePairingIntent(intent: Intent?) {
        val data = intent?.data ?: return
        if (data.scheme == "notchbridge") pair(data.toString())
    }

    private fun pair(raw: String?) {
        val cfg = PairingStore.parse(raw)
        if (cfg == null) {
            toast("That isn't a NotchBridge pairing code")
            return
        }
        PairingStore.save(this, cfg)
        Bridge.repaired()
        BridgeService.start(this)
        toast("Paired with ${cfg.macName}")
        render()
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_LONG).show()
}
