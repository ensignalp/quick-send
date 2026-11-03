package com.ensignsoft.quicksend.core

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.net.wifi.WifiManager
import android.provider.MediaStore
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

  @Synchronized fun start(context: Context) {
    val app = context.applicationContext
    appContext = app
    if (started) return
    acquireMulticastLock(app)
    val identity = loadOrCreateIdentity(app)
    val visible = app.getSharedPreferences("quick_send_settings", Context.MODE_PRIVATE).getBoolean("visible", true)
    NativeQuickSend.initialize(this, "Android device", identity, visible)
    started = true
  }

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
    when (event.optString("type")) {
      "transferRequest" -> if (context != null) QuickSendNotifications.incoming(context, event)
      "transferDecision" -> if (context != null) {
        if (event.optBoolean("accepted")) QuickSendNotifications.progress(context, event.optString("sessionId"), 0.0)
        else QuickSendNotifications.removeIncoming(context, event.optString("sessionId"))
      }
      "transferProgress" -> if (context != null) QuickSendNotifications.progress(context, event.optString("sessionId"), event.optDouble("progress"))
      "fileReceived" -> finishReceivedFile(context, event.optString("sessionId"), event.optString("fileId"), event.optBoolean("success"))
      "sessionEnd" -> {
        val sessionId = event.optString("sessionId")
        finishReceivedFiles(context, sessionId)
        if (context != null) QuickSendNotifications.removeIncoming(context, sessionId)
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
