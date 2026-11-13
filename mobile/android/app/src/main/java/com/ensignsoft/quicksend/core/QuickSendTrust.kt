package com.ensignsoft.quicksend.core

import android.content.Context
import org.json.JSONObject

/**
 * Reads the trust settings the React Native UI stores (SharedPreferences "quick_send_ui", key "state",
 * written by QuickSendModule.setSettings). The receiver service uses them to accept requests from trusted
 * devices while the UI is not running (screen off, app in the background or swiped away).
 *
 * Only devices the user explicitly marked as trusted (by certificate fingerprint) are auto-accepted, and only
 * while "Auto-accept from trusted devices" is on. Everyone else still gets the accept/decline prompt.
 */
object QuickSendTrust {
  private const val UI_PREFS = "quick_send_ui"

  private fun state(context: Context): JSONObject? =
    context.getSharedPreferences(UI_PREFS, Context.MODE_PRIVATE).getString("state", null)
      ?.let { runCatching { JSONObject(it) }.getOrNull() }

  fun isTrusted(context: Context, fingerprint: String): Boolean {
    if (fingerprint.isBlank()) return false
    val trusted = state(context)?.optJSONArray("trusted") ?: return false
    for (i in 0 until trusted.length()) {
      if (trusted.optJSONObject(i)?.optString("fingerprint") == fingerprint) return true
    }
    return false
  }

  /** Mirrors the UI default (autoAcceptTrusted = true). */
  fun shouldAutoAccept(context: Context, fingerprint: String): Boolean {
    val autoAccept = state(context)?.optBoolean("autoAcceptTrusted", true) ?: true
    return autoAccept && isTrusted(context, fingerprint)
  }

  /** Mirrors the UI default (autoUpdate = true). */
  fun autoUpdate(context: Context): Boolean = state(context)?.optBoolean("autoUpdate", true) ?: true
}
