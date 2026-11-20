package com.ensignsoft.quicksend.core

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.ensignsoft.quicksend.MainActivity
import org.json.JSONObject

/**
 * Quick Send: nearby devices in the Android share sheet ("Direct Share" sharing shortcuts).
 *
 * The devices the core currently discovers are published as sharing shortcuts (category below, declared in
 * res/xml/shortcuts.xml). Picking one in another app's share sheet opens Quick Send with the shared files and
 * the shortcut id; [targetFor] turns that id back into the device so the files go straight to it.
 */
object QuickSendDirectShare {
  const val CATEGORY = "com.ensignsoft.quicksend.category.DEVICE_SHARE_TARGET"
  private const val PREFS = "quick_send_direct_share"
  private const val MAX = 4
  private val current = LinkedHashMap<String, JSONObject>()

  @Synchronized fun replaceAll(context: Context, devices: List<JSONObject>) {
    current.clear()
    devices.forEach { d -> d.optString("fingerprint").takeIf { it.isNotEmpty() }?.let { current[it] = d } }
    publish(context)
  }

  @Synchronized fun add(context: Context, device: JSONObject) {
    val fingerprint = device.optString("fingerprint").takeIf { it.isNotEmpty() } ?: return
    val changed = current[fingerprint]?.toString() != device.toString()
    current.remove(fingerprint)
    current[fingerprint] = device
    if (changed) publish(context)
  }

  private fun publish(context: Context) {
    val app = context.applicationContext
    val devices = current.values.toList().takeLast(MAX)
    val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
    val shortcuts = devices.mapIndexed { rank, device ->
      val fingerprint = device.optString("fingerprint")
      val alias = device.optString("alias").ifBlank { "Quick Send" }
      prefs.putString(fingerprint, device.toString())
      ShortcutInfoCompat.Builder(app, "device:$fingerprint")
        .setShortLabel(alias)
        .setLongLabel(alias)
        .setIcon(IconCompat.createWithAdaptiveBitmap(letterIcon(alias)))
        .setIntent(Intent(app, MainActivity::class.java).setAction(Intent.ACTION_VIEW))
        .setCategories(setOf(CATEGORY))
        .setLongLived(true)
        .setRank(rank)
        .build()
    }
    prefs.apply()
    runCatching { ShortcutManagerCompat.setDynamicShortcuts(app, shortcuts) }
  }

  /** The device chosen in the share sheet, if the share came from one of our shortcuts. */
  fun targetFor(context: Context, intent: Intent?): JSONObject? {
    val id = intent?.getStringExtra(ShortcutManagerCompat.EXTRA_SHORTCUT_ID) ?: return null
    if (!id.startsWith("device:")) return null
    val json = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(id.removePrefix("device:"), null) ?: return null
    return runCatching { JSONObject(json) }.getOrNull()
  }

  /** A letter on the brand colour, sized for an adaptive icon (safe zone in the middle). */
  private fun letterIcon(alias: String): Bitmap {
    val size = 216
    val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    canvas.drawColor(0xFF3478F6.toInt())
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = 0xFFFFFFFF.toInt()
      textSize = size * 0.32f
      textAlign = Paint.Align.CENTER
      typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }
    val letter = alias.trim().firstOrNull()?.uppercaseChar()?.toString() ?: "?"
    canvas.drawText(letter, size / 2f, size / 2f - (paint.descent() + paint.ascent()) / 2f, paint)
    return bitmap
  }
}
