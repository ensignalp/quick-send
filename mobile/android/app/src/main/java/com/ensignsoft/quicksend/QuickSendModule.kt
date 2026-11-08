package com.ensignsoft.quicksend

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.facebook.react.bridge.ActivityEventListener
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.WritableArray
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.facebook.react.modules.core.PermissionAwareActivity
import com.facebook.react.modules.core.PermissionListener
import com.ensignsoft.quicksend.core.NativeQuickSend
import com.ensignsoft.quicksend.core.QuickSendCoreHost
import com.ensignsoft.quicksend.core.QuickSendEventBus
import com.ensignsoft.quicksend.core.QuickSendFiles
import com.ensignsoft.quicksend.core.QuickSendShare
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import java.util.UUID

class QuickSendModule(private val context: ReactApplicationContext) : ReactContextBaseJavaModule(context), ActivityEventListener {
  private var permissionPromise: Promise? = null
  private var permissionAction: (() -> Unit)? = null
  private var filePromise: Promise? = null
  private val eventListener: (String) -> Unit = { json ->
    runCatching {
      val payload = jsonToWritable(JSONObject(json))
      context.runOnUiQueueThread {
        context.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java).emit(EVENT_NAME, payload)
      }
    }
  }

  init {
    context.addActivityEventListener(this)
    QuickSendEventBus.addListener(eventListener)
  }

  override fun getName() = "QuickSend"

  override fun invalidate() {
    QuickSendEventBus.removeListener(eventListener)
    context.removeActivityEventListener(this)
    super.invalidate()
  }

  @ReactMethod fun addListener(eventName: String) = Unit
  @ReactMethod fun removeListeners(count: Int) = Unit

  @ReactMethod fun initialize(promise: Promise) {
    withPermissions(includeNotifications = false, promise = promise) {
      QuickSendCoreHost.start(context)
    }
  }

  @ReactMethod fun startReceiver(promise: Promise) {
    withPermissions(includeNotifications = true, promise = promise) {
      QuickSendCoreHost.start(context)
      QuickSendService.start(context)
    }
  }

  @ReactMethod fun stopReceiver(promise: Promise) {
    QuickSendService.stop(context)
    promise.resolve(true)
  }

  @ReactMethod fun setVisibility(value: String, promise: Promise) {
    val visible = value == "everyone"
    QuickSendCoreHost.setVisibility(context, visible)
    promise.resolve(true)
  }

  @ReactMethod fun getDynamicColors(promise: Promise) {
    val light = themeColors(dark = false)
    val dark = themeColors(dark = true)
    promise.resolve(Arguments.createMap().apply {
      putMap("light", light)
      putMap("dark", dark)
    })
  }

  @ReactMethod fun getAppInfo(promise: Promise) {
    promise.resolve(Arguments.createMap().apply {
      putString("version", BuildConfig.VERSION_NAME)
      putString("releasesRepo", BuildConfig.RELEASES_REPO)
    })
  }

  @ReactMethod fun getLanguage(promise: Promise) {
    promise.resolve(Locale.getDefault().language.lowercase(Locale.ROOT).let { if (it == "tr") "tr" else "en" })
  }

  @ReactMethod fun getVisibility(promise: Promise) {
    promise.resolve(if (QuickSendCoreHost.visibility(context)) "everyone" else "off")
  }

  @ReactMethod fun isReceiverEnabled(promise: Promise) {
    promise.resolve(context.getSharedPreferences(QuickSendService.PREFS, android.content.Context.MODE_PRIVATE)
      .getBoolean(QuickSendService.RECEIVER_ENABLED, false))
  }

  @ReactMethod fun getInitialSharedFiles(promise: Promise) {
    promise.resolve(fileListToWritable(QuickSendShare.consume(context)))
  }

  @ReactMethod fun pickFiles(promise: Promise) {
    val activity = context.currentActivity
    if (activity == null) {
      promise.reject("NO_ACTIVITY", "The file picker is not available right now")
      return
    }
    if (filePromise != null) {
      promise.reject("PICKER_BUSY", "A file picker is already open")
      return
    }
    filePromise = promise
    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
      .addCategory(Intent.CATEGORY_OPENABLE)
      .setType("*/*")
      .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
      .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
    try {
      activity.startActivityForResult(intent, FILE_PICK_REQUEST)
    } catch (error: Exception) {
      filePromise = null
      promise.reject("PICKER_FAILED", error)
    }
  }

  @ReactMethod fun sendFiles(device: ReadableMap, files: ReadableArray, promise: Promise) {
    val descriptors = mutableListOf<Int>()
    val cacheFiles = mutableListOf<String>()
    try {
      val fileMetadata = JSONArray()
      for (index in 0 until files.size()) {
        val file = files.getMap(index) ?: continue
        val uri = android.net.Uri.parse(file.getString("uri") ?: error("A selected file has no URI"))
        val value = QuickSendFiles.describe(
          context,
          uri,
          file.getString("mimeType"),
          file.getString("id") ?: UUID.randomUUID().toString(),
        )
        val resolved = QuickSendFiles.resolveForSend(context, value)
        resolved.cacheFile?.let { cacheFiles.add(it.absolutePath) }
        val descriptor = context.contentResolver.openFileDescriptor(resolved.file.uri, "r") ?: error("Unable to open ${resolved.file.name}")
        descriptors.add(descriptor.detachFd())
        fileMetadata.put(JSONObject().apply {
          put("id", resolved.file.id)
          put("name", resolved.file.name)
          put("mimeType", resolved.file.mimeType)
          put("size", resolved.file.size)
        })
      }
      if (descriptors.isEmpty()) {
        promise.resolve(null)
        return
      }
      val transferId = UUID.randomUUID().toString()
      val descriptorArray = descriptors.toIntArray()
      NativeQuickSend.send(JSONObject(device.toHashMap()).toString(), fileMetadata.toString(), descriptorArray, transferId)
      QuickSendCoreHost.trackOutgoingCache(transferId, cacheFiles)
      promise.resolve(transferId)
    } catch (error: Exception) {
      descriptors.forEach { fd -> runCatching { android.os.ParcelFileDescriptor.adoptFd(fd).close() } }
      cacheFiles.forEach { path -> runCatching { java.io.File(path).delete() } }
      promise.reject("SEND_FAILED", error)
    }
  }

  @ReactMethod fun respond(sessionId: String, accepted: Boolean, promise: Promise) {
    try {
      NativeQuickSend.respond(sessionId, accepted)
      promise.resolve(true)
    } catch (error: Exception) {
      promise.reject("RESPONSE_FAILED", error)
    }
  }

  @ReactMethod fun cancel(transferId: String, promise: Promise) {
    try {
      NativeQuickSend.cancel(transferId)
      promise.resolve(true)
    } catch (error: Exception) {
      promise.reject("CANCEL_FAILED", error)
    }
  }

  private fun withPermissions(includeNotifications: Boolean, promise: Promise, action: () -> Unit) {
    if (permissionPromise != null) {
      promise.reject("PERMISSION_REQUEST_ACTIVE", "A permission request is already active")
      return
    }
    val missing = buildList {
      if (Build.VERSION.SDK_INT >= 37 && context.checkSelfPermission(Manifest.permission.ACCESS_LOCAL_NETWORK) != PackageManager.PERMISSION_GRANTED) {
        add(Manifest.permission.ACCESS_LOCAL_NETWORK)
      }
      if (includeNotifications && Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
        add(Manifest.permission.POST_NOTIFICATIONS)
      }
    }
    if (missing.isEmpty()) {
      runCatching { action(); promise.resolve(true) }.onFailure { promise.reject("CORE_START_FAILED", it) }
      return
    }
      val activity = context.currentActivity as? PermissionAwareActivity
    if (activity == null) {
      promise.resolve(false)
      return
    }
    permissionPromise = promise
    permissionAction = action
      activity.requestPermissions(
        missing.toTypedArray(),
        PERMISSION_REQUEST,
        PermissionListener { requestCode, _, grantResults -> finishPermissionRequest(requestCode, grantResults) },
      )
  }

  private fun finishPermissionRequest(requestCode: Int, grantResults: IntArray): Boolean {
    if (requestCode != PERMISSION_REQUEST) return false
    val promise = permissionPromise
    val action = permissionAction
    permissionPromise = null
    permissionAction = null
    if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
      runCatching { action?.invoke(); promise?.resolve(true) }.onFailure { promise?.reject("CORE_START_FAILED", it) }
    } else {
      promise?.resolve(false)
    }
    return true
  }

  override fun onActivityResult(activity: Activity, requestCode: Int, resultCode: Int, data: Intent?) {
    if (requestCode != FILE_PICK_REQUEST) return
    val promise = filePromise ?: return
    filePromise = null
    if (resultCode != Activity.RESULT_OK || data == null) {
      promise.resolve(Arguments.createArray())
      return
    }
    runCatching {
      val list = mutableListOf<android.net.Uri>()
      data.clipData?.let { clip -> for (index in 0 until clip.itemCount) list.add(clip.getItemAt(index).uri) }
      if (list.isEmpty()) data.data?.let(list::add)
      val files = list.distinct().mapIndexed { index, uri -> QuickSendFiles.describe(context, uri, data.type, "picked-$index") }
      promise.resolve(fileListToWritable(files))
    }.onFailure { promise.reject("PICKER_FAILED", it) }
  }

  override fun onNewIntent(intent: Intent) = Unit

  private fun themeColors(dark: Boolean): WritableMap {
    fun androidColor(name: String, fallback: Int): String {
      val resource = context.resources.getIdentifier(name, "color", "android")
      val color = if (resource != 0 && Build.VERSION.SDK_INT >= 31) runCatching { context.getColor(resource) }.getOrDefault(fallback) else fallback
      return String.format(Locale.ROOT, "#%06X", 0xFFFFFF and color)
    }
    val suffix = if (dark) "200" else "600"
    return Arguments.createMap().apply {
      putString("primary", androidColor("system_accent1_$suffix", if (dark) 0xFFB7C8FF.toInt() else 0xFF315DA8.toInt()))
      putString("secondary", androidColor("system_accent2_$suffix", if (dark) 0xFFBBC7E5.toInt() else 0xFF52617D.toInt()))
      putString("tertiary", androidColor("system_accent3_$suffix", if (dark) 0xFFDABDE1.toInt() else 0xFF6C4F75.toInt()))
    }
  }

  private fun fileListToWritable(files: List<com.ensignsoft.quicksend.core.SharedFileData>): WritableArray = Arguments.createArray().apply {
    files.forEach { file -> pushMap(Arguments.createMap().apply {
      putString("id", file.id)
      putString("uri", file.uri.toString())
      putString("name", file.name)
      putString("mimeType", file.mimeType)
      putDouble("size", file.size.toDouble())
    }) }
  }

  private fun jsonToWritable(value: JSONObject): WritableMap = Arguments.createMap().apply {
    value.keys().forEach { key ->
      when (val child = value.opt(key)) {
        null, JSONObject.NULL -> putNull(key)
        is JSONObject -> putMap(key, jsonToWritable(child))
        is JSONArray -> putArray(key, jsonArrayToWritable(child))
        is Boolean -> putBoolean(key, child)
        is Int -> putInt(key, child)
        is Number -> putDouble(key, child.toDouble())
        else -> putString(key, child.toString())
      }
    }
  }

  private fun jsonArrayToWritable(value: JSONArray): WritableArray = Arguments.createArray().apply {
    for (index in 0 until value.length()) {
      when (val child = value.opt(index)) {
        null, JSONObject.NULL -> pushNull()
        is JSONObject -> pushMap(jsonToWritable(child))
        is JSONArray -> pushArray(jsonArrayToWritable(child))
        is Boolean -> pushBoolean(child)
        is Int -> pushInt(child)
        is Number -> pushDouble(child.toDouble())
        else -> pushString(child.toString())
      }
    }
  }

  companion object {
    private const val EVENT_NAME = "QuickSendEvent"
    private const val PERMISSION_REQUEST = 5421
    private const val FILE_PICK_REQUEST = 5422
  }
}

private object QuickSendShareIntent {
  fun consume(context: ReactApplicationContext) = com.ensignsoft.quicksend.core.QuickSendShare.consume(context)
}
