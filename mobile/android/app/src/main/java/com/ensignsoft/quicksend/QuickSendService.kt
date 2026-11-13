package com.ensignsoft.quicksend

import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import com.ensignsoft.quicksend.core.QuickSendCoreHost
import com.ensignsoft.quicksend.core.QuickSendNotifications

class QuickSendService : Service() {
  override fun onCreate() {
    super.onCreate()
    QuickSendCoreHost.start(this)
    QuickSendNotifications.ensureChannel(this)
    // Signed background updates (rate-limited to every 12 hours; no-op unless configured).
    com.ensignsoft.quicksend.core.QuickSendUpdater.maybeCheck(this)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      startForeground(QuickSendNotifications.RECEIVING_ID, QuickSendNotifications.receiving(this), android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
    } else {
      startForeground(QuickSendNotifications.RECEIVING_ID, QuickSendNotifications.receiving(this))
    }
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    if (intent?.action == ACTION_STOP) {
      getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean(RECEIVER_ENABLED, false).apply()
      stopForeground(STOP_FOREGROUND_REMOVE)
      stopSelf()
      return START_NOT_STICKY
    }
    getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean(RECEIVER_ENABLED, true).apply()
    return START_STICKY
  }

  override fun onDestroy() {
    getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean(RECEIVER_ENABLED, false).apply()
    stopForeground(STOP_FOREGROUND_REMOVE)
    super.onDestroy()
  }

  override fun onBind(intent: Intent?): IBinder? = null

  companion object {
    const val ACTION_START = "com.ensignsoft.quicksend.action.START_RECEIVER"
    const val ACTION_STOP = "com.ensignsoft.quicksend.action.STOP_RECEIVER"
    const val PREFS = "quick_send_settings"
    const val RECEIVER_ENABLED = "receiver_enabled"

    fun start(context: android.content.Context) {
      val intent = Intent(context, QuickSendService::class.java).setAction(ACTION_START)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent) else context.startService(intent)
    }

    fun stop(context: android.content.Context) {
      context.stopService(Intent(context, QuickSendService::class.java).setAction(ACTION_STOP))
    }
  }
}
