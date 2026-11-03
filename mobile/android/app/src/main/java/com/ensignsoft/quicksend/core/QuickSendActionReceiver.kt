package com.ensignsoft.quicksend.core

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.ensignsoft.quicksend.QuickSendService

class QuickSendActionReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    when (intent.action) {
      ACTION_ACCEPT, ACTION_DECLINE -> {
        val sessionId = intent.getStringExtra(EXTRA_SESSION_ID) ?: return
        val accepted = intent.action == ACTION_ACCEPT
        runCatching { NativeQuickSend.respond(sessionId, accepted) }
        QuickSendNotifications.removeIncoming(context, sessionId)
      }
      ACTION_STOP -> QuickSendService.stop(context)
    }
  }

  companion object {
    const val ACTION_ACCEPT = "com.ensignsoft.quicksend.action.ACCEPT_TRANSFER"
    const val ACTION_DECLINE = "com.ensignsoft.quicksend.action.DECLINE_TRANSFER"
    const val ACTION_STOP = "com.ensignsoft.quicksend.action.STOP_RECEIVER"
    const val EXTRA_SESSION_ID = "session_id"
    const val EXTRA_ACCEPTED = "accepted"
  }
}
