package com.ensignsoft.quicksend.core

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.ensignsoft.quicksend.QuickSendService

/**
 * Restarts the receiver service after a reboot or an app update, if it was running before (the user had
 * not turned receiving off). Without this, trusted devices could not send anything until the app is opened.
 * connectedDevice foreground services may be started from BOOT_COMPLETED (Android 15 restricts other types).
 */
class QuickSendBootReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
    val enabled = context.getSharedPreferences(QuickSendService.PREFS, Context.MODE_PRIVATE)
      .getBoolean(QuickSendService.RECEIVER_ENABLED, false)
    if (enabled) runCatching { QuickSendService.start(context) }
  }
}
