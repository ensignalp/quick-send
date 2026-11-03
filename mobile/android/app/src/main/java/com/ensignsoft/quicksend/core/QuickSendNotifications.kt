package com.ensignsoft.quicksend.core

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import com.ensignsoft.quicksend.MainActivity
import com.ensignsoft.quicksend.R
import org.json.JSONObject

object QuickSendNotifications {
  const val CHANNEL_ID = "quick_send_transfers"
  const val RECEIVING_ID = 4100
  private const val REQUEST_ID = 4101

  fun ensureChannel(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = context.getSystemService(NotificationManager::class.java)
    val channel = NotificationChannel(CHANNEL_ID, "Quick Send", NotificationManager.IMPORTANCE_LOW).apply {
      description = if (context.resources.configuration.locales[0].language == "tr") "Yakındaki cihazlardan dosya alımı" else "Receiving files from nearby devices"
      enableLights(false)
      lightColor = Color.BLUE
      setShowBadge(false)
    }
    manager.createNotificationChannel(channel)
  }

  fun receiving(context: Context): Notification {
    ensureChannel(context)
    val tr = context.resources.configuration.locales[0].language == "tr"
    return builder(context)
      .setContentTitle("Quick Send")
      .setContentText(if (tr) "Dosya alımı açık" else "Receiving is on")
      .setOngoing(true)
      .addAction(
        android.R.drawable.ic_media_pause,
        if (tr) "Durdur" else "Stop",
        action(context, QuickSendActionReceiver.ACTION_STOP, "service", false),
      )
      .build()
  }

  fun incoming(context: Context, event: JSONObject) {
    ensureChannel(context)
    val transfer = event.optJSONObject("transfer") ?: return
    val sessionId = transfer.optString("sessionId")
    val sender = transfer.optString("sender", "")
    val files = transfer.optJSONArray("files")
    val count = files?.length() ?: 0
    val tr = context.resources.configuration.locales[0].language == "tr"
    val notification = builder(context)
      .setContentTitle(if (tr) "Gelen aktarım" else "Incoming transfer")
      .setContentText(if (tr) "$sender · $count dosya" else "$sender · $count files")
      .setAutoCancel(false)
      .addAction(android.R.drawable.checkbox_on_background, if (tr) "Kabul et" else "Accept", action(context, QuickSendActionReceiver.ACTION_ACCEPT, sessionId, true))
      .addAction(android.R.drawable.ic_menu_close_clear_cancel, if (tr) "Reddet" else "Decline", action(context, QuickSendActionReceiver.ACTION_DECLINE, sessionId, false))
      .build()
    manager(context).notify(requestNotificationId(sessionId), notification)
  }

  fun removeIncoming(context: Context, sessionId: String) {
    manager(context).cancel(requestNotificationId(sessionId))
  }

  fun progress(context: Context, sessionId: String, progress: Double) {
    val tr = context.resources.configuration.locales[0].language == "tr"
    val notification = builder(context)
      .setContentTitle(if (tr) "Dosya alınıyor" else "Receiving files")
      .setContentText(if (tr) "${(progress * 100).toInt()}% tamamlandı" else "${(progress * 100).toInt()}% complete")
      .setProgress(100, (progress * 100).toInt().coerceIn(0, 100), false)
      .setOngoing(true)
      .build()
    manager(context).notify(requestNotificationId(sessionId), notification)
  }

  private fun requestNotificationId(sessionId: String) = REQUEST_ID + (sessionId.hashCode() and 0x0fff)

  private fun action(context: Context, action: String, sessionId: String, accepted: Boolean): PendingIntent {
    val intent = Intent(context, QuickSendActionReceiver::class.java)
      .setAction(action)
      .putExtra(QuickSendActionReceiver.EXTRA_SESSION_ID, sessionId)
      .putExtra(QuickSendActionReceiver.EXTRA_ACCEPTED, accepted)
    return PendingIntent.getBroadcast(context, requestNotificationId(sessionId), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
  }

  private fun builder(context: Context): Notification.Builder {
    val intent = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    val open = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    return Notification.Builder(context, CHANNEL_ID)
      .setSmallIcon(R.drawable.ic_stat_quicksend)
      .setContentIntent(open)
      .setColor(context.getColor(R.color.quick_send_primary))
      .setCategory(Notification.CATEGORY_SERVICE)
      .setVisibility(Notification.VISIBILITY_PRIVATE)
  }

  private fun manager(context: Context) = context.getSystemService(NotificationManager::class.java)
}
