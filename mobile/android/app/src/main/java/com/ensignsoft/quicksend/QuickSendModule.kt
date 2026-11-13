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
import com.ensignsoft.quicksend.core.QuickSendMedia
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
      putString("alias", QuickSendCoreHost.alias(context))
    })
  }

  /** UI preferences (language, theme, trusted devices, history…) as one JSON document. */
  @ReactMethod fun getSettings(promise: Promise) {
    promise.resolve(context.getSharedPreferences(UI_PREFS, android.content.Context.MODE_PRIVATE).getString("state", null))
  }

  @ReactMethod fun setSettings(json: String, promise: Promise) {
    context.getSharedPreferences(UI_PREFS, android.content.Context.MODE_PRIVATE).edit().putString("state", json).apply()
    promise.resolve(true)
  }

  /** Device name and receive PIN used by the core. Empty strings reset them. Applied after [restartApp]. */
  @ReactMethod fun setCoreConfig(alias: String, pin: String, promise: Promise) {
    QuickSendCoreHost.setCoreConfig(context, alias, pin)
    promise.resolve(true)
  }

  @ReactMethod fun getCoreConfig(promise: Promise) {
    promise.resolve(Arguments.createMap().apply {
      putString("alias", QuickSendCoreHost.alias(context))
      putString("pin", QuickSendCoreHost.pin(context))
    })
  }

  /** Restarts the process so the core starts again with the new name/PIN. */
  @ReactMethod fun restartApp() {
    val intent = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
    context.startActivity(intent)
    Runtime.getRuntime().exit(0)
  }

  /** Local IPv4 addresses and the LocalSend port, for the info sheet. */
  @ReactMethod fun getNetworkInfo(promise: Promise) {
    val addresses = Arguments.createArray()
    runCatching {
      java.net.NetworkInterface.getNetworkInterfaces()?.toList().orEmpty()
        .filter { it.isUp && !it.isLoopback }
        .flatMap { it.inetAddresses.toList() }
        .filterIsInstance<java.net.Inet4Address>()
        .map { it.hostAddress }
        .distinct()
        .forEach { addresses.pushString(it) }
    }
    promise.resolve(Arguments.createMap().apply {
      putArray("addresses", addresses)
      putInt("port", 53317)
    })
  }

  /** Opens the system Downloads app, where received files are stored (Downloads/Quick Send). */
  @ReactMethod fun openDownloads(promise: Promise) {
    try {
      val intent = Intent(android.app.DownloadManager.ACTION_VIEW_DOWNLOADS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      context.startActivity(intent)
      promise.resolve(true)
    } catch (error: Exception) {
      promise.reject("OPEN_FAILED", error)
    }
  }

  @ReactMethod fun getLanguage(promise: Promise) {
    promise.resolve(Locale.getDefault().language.lowercase(Locale.ROOT).let { if (it == "tr") "tr" else "en" })
  }

  @ReactMethod fun getVisibility(promise: Promise) {
    promise.resolve(if (QuickSendCoreHost.visibility(context)) "everyone" else "off")
  }

  /** Internet transfer (iroh): shares the given files; resolves to the transfer id. Events: type "internet". */
  @ReactMethod fun internetSend(files: ReadableArray, promise: Promise) {
    val id = UUID.randomUUID().toString()
    val list = (0 until files.size()).mapNotNull { i ->
      val f = files.getMap(i) ?: return@mapNotNull null
      val uri = f.getString("uri") ?: return@mapNotNull null
      android.net.Uri.parse(uri) to (f.getString("name") ?: "file")
    }
    Thread({
      runCatching { com.ensignsoft.quicksend.core.QuickSendInternet.send(context, id, list) }
        .onSuccess { promise.resolve(id) }
        .onFailure { promise.reject("internet_send", it.message, it) }
    }, "quick-send-internet").start()
  }

  @ReactMethod fun internetReceive(ticket: String, promise: Promise) {
    if (!com.ensignsoft.quicksend.core.NativeQuickSend.internetIsValidTicket(ticket)) {
      promise.reject("invalid_code", "invalid code")
      return
    }
    val id = UUID.randomUUID().toString()
    runCatching { com.ensignsoft.quicksend.core.QuickSendInternet.receive(context, id, ticket) }
      .onSuccess { promise.resolve(id) }
      .onFailure { promise.reject("internet_receive", it.message, it) }
  }

  @ReactMethod fun internetCancel(id: String, promise: Promise) {
    com.ensignsoft.quicksend.core.QuickSendInternet.cancel(id)
    promise.resolve(true)
  }

  @ReactMethod fun internetIsValidCode(ticket: String, promise: Promise) {
    promise.resolve(runCatching { com.ensignsoft.quicksend.core.NativeQuickSend.internetIsValidTicket(ticket) }.getOrDefault(false))
  }

  /** Background receiving: true when Android battery optimisation does not restrict Quick Send. */
  @ReactMethod fun isBatteryUnrestricted(promise: Promise) {
    val power = context.getSystemService(android.os.PowerManager::class.java)
    promise.resolve(power?.isIgnoringBatteryOptimizations(context.packageName) == true)
  }

  /** Opens the system dialog that exempts Quick Send from battery optimisation (the user decides). */
  @ReactMethod fun requestBatteryUnrestricted(promise: Promise) {
    val intent = Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
      .setData(android.net.Uri.parse("package:${context.packageName}"))
      .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    promise.resolve(runCatching { context.startActivity(intent) }.isSuccess)
  }

  @ReactMethod fun getUpdateSupport(promise: Promise) {
    promise.resolve(Arguments.createMap().apply {
      putBoolean("supported", com.ensignsoft.quicksend.core.QuickSendUpdater.supported())
      putBoolean("canInstall", com.ensignsoft.quicksend.core.QuickSendUpdater.canInstall(context))
    })
  }

  /** Runs a background update check now; resolves to ready / upToDate / rejected / failed / notConfigured / busy. */
  @ReactMethod fun checkUpdateNow(promise: Promise) {
    Thread({ promise.resolve(com.ensignsoft.quicksend.core.QuickSendUpdater.run(context)) }, "quick-send-update").start()
  }

  @ReactMethod fun isReceiverEnabled(promise: Promise) {
    promise.resolve(context.getSharedPreferences(QuickSendService.PREFS, android.content.Context.MODE_PRIVATE)
      .getBoolean(QuickSendService.RECEIVER_ENABLED, false))
  }

  @ReactMethod fun getInitialSharedFiles(promise: Promise) {
    promise.resolve(fileListToWritable(QuickSendShare.consume(context)))
  }

  @ReactMethod fun pickFiles(promise: Promise) {
    launchPicker(openDocumentIntent("*/*"), FILE_PICK_REQUEST, promise)
  }

  /** System document picker limited to document types (the picker's "Documents" fallback). */
  @ReactMethod fun pickDocuments(promise: Promise) {
    launchPicker(openDocumentIntent("*/*").putExtra(Intent.EXTRA_MIME_TYPES, QuickSendMedia.documentMimeTypes), FILE_PICK_REQUEST, promise)
  }

  /** Lets a specific app (from [getContentApps]) provide the files. */
  @ReactMethod fun pickWithApp(packageName: String, activityName: String, promise: Promise) {
    val intent = Intent(Intent.ACTION_GET_CONTENT)
      .setType("*/*")
      .addCategory(Intent.CATEGORY_OPENABLE)
      .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
      .setClassName(packageName, activityName)
    launchPicker(intent, FILE_PICK_REQUEST, promise)
  }

  /** Picks a profile photo; resolves with a `file://` URI of the cropped copy, or null when cancelled. */
  @ReactMethod fun pickAvatar(promise: Promise) {
    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("image/*")
    launchPicker(intent, AVATAR_REQUEST, promise)
  }

  @ReactMethod fun clearAvatar(promise: Promise) {
    QuickSendMedia.clearAvatar(context)
    promise.resolve(true)
  }

  @ReactMethod fun hasMediaPermission(promise: Promise) {
    promise.resolve(mediaPermissions().all { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED } || hasPartialMediaAccess())
  }

  @ReactMethod fun requestMediaPermission(promise: Promise) {
    val missing = mediaPermissions().filter { context.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
    if (missing.isEmpty() || hasPartialMediaAccess() && Build.VERSION.SDK_INT < 34) {
      promise.resolve(true)
      return
    }
    val activity = context.currentActivity as? PermissionAwareActivity
    if (activity == null) {
      promise.resolve(false)
      return
    }
    val request = if (Build.VERSION.SDK_INT >= 34) missing + "android.permission.READ_MEDIA_VISUAL_USER_SELECTED" else missing
    activity.requestPermissions(request.toTypedArray(), MEDIA_PERMISSION_REQUEST, PermissionListener { code, _, _ ->
      if (code != MEDIA_PERMISSION_REQUEST) return@PermissionListener false
      promise.resolve(mediaPermissions().all { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED } || hasPartialMediaAccess())
      true
    })
  }

  /** Lists `images`, `videos` or `documents` from the media library (newest first). */
  @ReactMethod fun queryMedia(kind: String, limit: Int, offset: Int, promise: Promise) {
    Thread {
      runCatching { QuickSendMedia.query(context, kind, limit, offset) }
        .onSuccess { promise.resolve(jsonArrayToWritable(it)) }
        .onFailure { promise.reject("MEDIA_QUERY_FAILED", it) }
    }.start()
  }

  @ReactMethod fun getThumbnail(uri: String, size: Int, promise: Promise) {
    thumbnailExecutor.execute {
      runCatching { QuickSendMedia.thumbnail(context, android.net.Uri.parse(uri), size) }
        .onSuccess { promise.resolve(it) }
        .onFailure { promise.resolve(null) }
    }
  }

  @ReactMethod fun getContentApps(promise: Promise) {
    Thread {
      runCatching { QuickSendMedia.contentApps(context) }
        .onSuccess { promise.resolve(jsonArrayToWritable(it)) }
        .onFailure { promise.reject("APPS_FAILED", it) }
    }.start()
  }

  private fun mediaPermissions(): List<String> =
    if (Build.VERSION.SDK_INT >= 33) listOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO)
    else listOf(Manifest.permission.READ_EXTERNAL_STORAGE)

  private fun hasPartialMediaAccess(): Boolean =
    Build.VERSION.SDK_INT >= 34 && context.checkSelfPermission("android.permission.READ_MEDIA_VISUAL_USER_SELECTED") == PackageManager.PERMISSION_GRANTED

  private fun openDocumentIntent(type: String) = Intent(Intent.ACTION_OPEN_DOCUMENT)
    .addCategory(Intent.CATEGORY_OPENABLE)
    .setType(type)
    .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)

  private fun launchPicker(intent: Intent, requestCode: Int, promise: Promise) {
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
    try {
      activity.startActivityForResult(intent, requestCode)
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
    if (requestCode != FILE_PICK_REQUEST && requestCode != AVATAR_REQUEST) return
    val promise = filePromise ?: return
    filePromise = null
    if (requestCode == AVATAR_REQUEST) {
      val uri = data?.data
      if (resultCode != Activity.RESULT_OK || uri == null) {
        promise.resolve(null)
        return
      }
      Thread {
        runCatching { QuickSendMedia.saveAvatar(context, uri) }
          .onSuccess { promise.resolve(it) }
          .onFailure { promise.reject("AVATAR_FAILED", it) }
      }.start()
      return
    }
    if (resultCode != Activity.RESULT_OK || data == null) {
      promise.resolve(Arguments.createArray())
      return
    }
    runCatching {
      val list = mutableListOf<android.net.Uri>()
      data.clipData?.let { clip -> for (index in 0 until clip.itemCount) list.add(clip.getItemAt(index).uri) }
      if (list.isEmpty()) data.data?.let(list::add)
      val files = list.distinct().mapIndexed { index, uri -> QuickSendFiles.describe(context, uri, data.type, "picked-${UUID.randomUUID()}-$index") }
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
    private const val UI_PREFS = "quick_send_ui"
    private const val AVATAR_REQUEST = 5423
    private const val MEDIA_PERMISSION_REQUEST = 5424
    private val thumbnailExecutor = java.util.concurrent.Executors.newFixedThreadPool(3)
  }
}

private object QuickSendShareIntent {
  fun consume(context: ReactApplicationContext) = com.ensignsoft.quicksend.core.QuickSendShare.consume(context)
}
