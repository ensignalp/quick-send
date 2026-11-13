package com.ensignsoft.quicksend.core

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.net.wifi.WifiManager
import android.provider.MediaStore
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.nio.ByteBuffer
import java.security.KeyStore
import java.util.concurrent.ConcurrentHashMap
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONObject

object QuickSendCoreHost : QuickSendCoreCallbacks {
  private const val PREFS = "quick_send_secure_identity"
  private const val IDENTITY_KEY = "identity"
  private const val KEY_ALIAS = "com.ensignsoft.quicksend.identity"
  @Volatile private var appContext: Context? = null
  @Volatile private var started = false
  @Volatile private var multicastLock: WifiManager.MulticastLock? = null
  private val receivedUris = ConcurrentHashMap<String, MutableMap<String, Uri>>()
  private val outgoingCache = ConcurrentHashMap<String, List<String>>()
  /** Accepted receive sessions: sender name and the number of files saved so far. */
  private val acceptedSessions = ConcurrentHashMap<String, AcceptedSession>()
  private val requestSenders = ConcurrentHashMap<String, String>()
  private val decisions = java.util.concurrent.Executors.newSingleThreadExecutor()

  private class AcceptedSession(val sender: String, val auto: Boolean) {
    @Volatile var saved = 0
  }

  @Synchronized fun start(context: Context) {
    val app = context.applicationContext
    appContext = app
    if (started) return
    acquireMulticastLock(app)
    // iroh (internet transfers) resolves DNS through the app context.
    runCatching { NativeQuickSend.initAndroidContext(app) }
    val identity = loadOrCreateIdentity(app)
    val prefs = app.getSharedPreferences("quick_send_settings", Context.MODE_PRIVATE)
    val visible = prefs.getBoolean("visible", true)
    NativeQuickSend.initialize(this, alias(app), identity, visible, prefs.getString(PIN_KEY, null).orEmpty())
    started = true
  }

  /** Name shown to other devices: the user-set device name, falling back to the model. */
  fun alias(context: Context): String {
    context.getSharedPreferences("quick_send_settings", Context.MODE_PRIVATE).getString(ALIAS_KEY, null)
      ?.takeIf { it.isNotBlank() }?.let { return it }
    val name = runCatching { Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME) }.getOrNull()
    return name?.takeIf { it.isNotBlank() } ?: Build.MODEL?.takeIf { it.isNotBlank() } ?: "Android device"
  }

  const val ALIAS_KEY = "alias_override"
  const val PIN_KEY = "receive_pin"

  /** Stores the name and receive PIN; the core reads them when it starts (after an app restart). */
  fun setCoreConfig(context: Context, alias: String?, pin: String?) {
    context.getSharedPreferences("quick_send_settings", Context.MODE_PRIVATE).edit()
      .putString(ALIAS_KEY, alias?.trim()?.takeIf { it.isNotEmpty() })
      .putString(PIN_KEY, pin?.trim()?.takeIf { it.isNotEmpty() })
      .commit()
  }

  fun pin(context: Context): String? =
    context.getSharedPreferences("quick_send_settings", Context.MODE_PRIVATE).getString(PIN_KEY, null)

  fun setVisibility(context: Context, visible: Boolean) {
    context.getSharedPreferences("quick_send_settings", Context.MODE_PRIVATE).edit().putBoolean("visible", visible).apply()
    if (started) NativeQuickSend.setVisibility(visible)
  }

  fun visibility(context: Context) = context.getSharedPreferences("quick_send_settings", Context.MODE_PRIVATE).getBoolean("visible", true)

  fun trackOutgoingCache(transferId: String, paths: List<String>) {
    if (paths.isNotEmpty()) outgoingCache[transferId] = paths
  }

  override fun onCoreEvent(eventJson: String) {
    val event = runCatching { JSONObject(eventJson) }.getOrNull() ?: return
    val context = appContext
    if (event.optString("type") == "internet" && context != null) {
      // Transfers over the internet: publish received files, clean up, then hand the event to the UI.
      QuickSendEventBus.emit(QuickSendInternet.onEvent(context, event).toString())
      return
    }
    when (event.optString("type")) {
      "transferRequest" -> if (context != null) {
        val transfer = event.optJSONObject("transfer")
        val sessionId = transfer?.optString("sessionId").orEmpty()
        val fingerprint = transfer?.optString("fingerprint").orEmpty()
        if (transfer != null && sessionId.isNotEmpty() && QuickSendTrust.shouldAutoAccept(context, fingerprint)) {
          // Trusted device: accept here, so it also works while the UI is not running.
          acceptedSessions[sessionId] = AcceptedSession(transfer.optString("sender"), auto = true)
          event.put("autoAccepted", true)
          QuickSendNotifications.progress(context, sessionId, 0.0)
          decisions.execute { runCatching { NativeQuickSend.respond(sessionId, true) } }
          QuickSendEventBus.emit(event.toString())
          return
        }
        if (sessionId.isNotEmpty()) requestSenders[sessionId] = transfer?.optString("sender").orEmpty()
        QuickSendNotifications.incoming(context, event)
      }
      "transferDecision" -> if (context != null) {
        val sessionId = event.optString("sessionId")
        if (event.optBoolean("accepted")) {
          acceptedSessions.putIfAbsent(sessionId, AcceptedSession(requestSenders.remove(sessionId).orEmpty(), auto = false))
          QuickSendNotifications.progress(context, sessionId, 0.0)
        } else {
          requestSenders.remove(sessionId)
          QuickSendNotifications.removeIncoming(context, sessionId)
        }
      }
      "transferProgress" -> if (context != null) QuickSendNotifications.progress(context, event.optString("sessionId"), event.optDouble("progress"))
      "fileReceived" -> {
        val sessionId = event.optString("sessionId")
        if (event.optBoolean("success")) acceptedSessions[sessionId]?.let { it.saved++ }
        finishReceivedFile(context, sessionId, event.optString("fileId"), event.optBoolean("success"))
      }
      "sessionEnd" -> {
        val sessionId = event.optString("sessionId")
        finishReceivedFiles(context, sessionId)
        if (context != null) {
          QuickSendNotifications.removeIncoming(context, sessionId)
          requestSenders.remove(sessionId)
          val accepted = acceptedSessions.remove(sessionId)
          // "Received" confirmation when nobody is looking at the app (the app shows its own card otherwise).
          if (accepted != null && accepted.saved > 0 && !isAppInForeground(context)) {
            QuickSendNotifications.received(context, sessionId, accepted.sender, accepted.saved)
          }
        }
      }
      "sendComplete", "sendFailed" -> {
        val id = event.optString("transferId")
        outgoingCache.remove(id)?.forEach { path -> runCatching { java.io.File(path).delete() } }
      }
    }
    QuickSendEventBus.emit(eventJson)
  }

  override fun openReceivedFile(sessionId: String, fileId: String, fileName: String, mimeType: String): Int {
    val context = appContext ?: return -1
    val safeName = QuickSendFiles.safeName(fileName)
    val values = ContentValues().apply {
      put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
      put(MediaStore.MediaColumns.MIME_TYPE, mimeType.ifBlank { "application/octet-stream" })
      put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/Quick Send")
      put(MediaStore.MediaColumns.IS_PENDING, 1)
    }
    val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return -1
    return try {
      val descriptor = context.contentResolver.openFileDescriptor(uri, "w") ?: throw IllegalStateException("Unable to open output file")
      receivedUris.compute(sessionId) { _, files -> (files ?: ConcurrentHashMap()).also { it[fileId] = uri } }
      descriptor.detachFd()
    } catch (error: Exception) {
      context.contentResolver.delete(uri, null, null)
      throw error
    }
  }

  private fun finishReceivedFiles(context: Context?, sessionId: String) {
    val app = context ?: return
    receivedUris.remove(sessionId)?.values?.forEach { uri ->
      runCatching { app.contentResolver.delete(uri, null, null) }
    }
  }

  private fun finishReceivedFile(context: Context?, sessionId: String, fileId: String, success: Boolean) {
    val app = context ?: return
    val uri = receivedUris[sessionId]?.remove(fileId) ?: return
    runCatching {
      if (success) {
        val values = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
        app.contentResolver.update(uri, values, null, null)
      } else {
        app.contentResolver.delete(uri, null, null)
      }
    }
  }

  private fun isAppInForeground(context: Context): Boolean {
    val info = android.app.ActivityManager.RunningAppProcessInfo()
    android.app.ActivityManager.getMyMemoryState(info)
    return info.importance <= android.app.ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
  }

  private fun acquireMulticastLock(context: Context) {
    val wifi = context.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return
    multicastLock = wifi.createMulticastLock("quick-send:local-discovery").apply {
      setReferenceCounted(false)
      if (!isHeld) acquire()
    }
  }

  private fun loadOrCreateIdentity(context: Context): String {
    val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    val saved = preferences.getString(IDENTITY_KEY, null)
    if (saved != null) {
      runCatching { decrypt(saved) }.getOrNull()?.let { return it }
    }
    val generated = NativeQuickSend.generateIdentity()
    preferences.edit().putString(IDENTITY_KEY, encrypt(generated)).commit()
    return generated
  }

  private fun key(): SecretKey {
    val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
    val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
    generator.init(
      KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
        .setRandomizedEncryptionRequired(true)
        .build(),
    )
    return generator.generateKey()
  }

  private fun encrypt(value: String): String {
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.ENCRYPT_MODE, key())
    val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
    val result = ByteBuffer.allocate(cipher.iv.size + encrypted.size).put(cipher.iv).put(encrypted).array()
    return Base64.encodeToString(result, Base64.NO_WRAP)
  }

  private fun decrypt(value: String): String {
    val bytes = Base64.decode(value, Base64.NO_WRAP)
    require(bytes.size > 12) { "Stored identity is invalid" }
    val iv = bytes.copyOfRange(0, 12)
    val encrypted = bytes.copyOfRange(12, bytes.size)
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv))
    return cipher.doFinal(encrypted).toString(Charsets.UTF_8)
  }
}
