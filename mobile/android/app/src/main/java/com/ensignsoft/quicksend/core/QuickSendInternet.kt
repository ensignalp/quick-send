package com.ensignsoft.quicksend.core

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import org.json.JSONArray
import org.json.JSONObject

/**
 * Quick Send: Android side of transfers over the internet (iroh, packages/qs_internet).
 *
 * iroh reads and writes plain files, so outgoing content:// files are copied into the app cache first and
 * incoming files are written to the cache and then published to Downloads/Quick Send through MediaStore.
 * The temporary copies are removed when a transfer ends. The LocalSend (local network) path is untouched.
 */
object QuickSendInternet {
  private fun root(context: Context) = File(context.cacheDir, "internet")
  private fun outDir(context: Context, id: String) = File(root(context), "out-$id")
  private fun inDir(context: Context, id: String) = File(root(context), "in-$id")
  private fun storeDir(context: Context, id: String) = File(root(context), "store-$id")

  /** Copies the picked files into the cache and starts sharing; events arrive as "internet" core events. */
  fun send(context: Context, id: String, files: List<Pair<Uri, String>>) {
    val dir = outDir(context, id).apply { deleteRecursively(); mkdirs() }
    val list = JSONArray()
    val used = HashSet<String>()
    for ((uri, name) in files) {
      var safe = QuickSendFiles.safeName(name)
      var n = 2
      while (!used.add(safe)) safe = numbered(QuickSendFiles.safeName(name), n++)
      val target = File(dir, safe)
      context.contentResolver.openInputStream(uri)?.use { input -> target.outputStream().use { input.copyTo(it) } }
        ?: throw IllegalStateException("Cannot read $name")
      list.put(JSONObject().put("name", safe).put("path", target.absolutePath))
    }
    NativeQuickSend.internetSend(id, list.toString(), storeDir(context, id).absolutePath)
  }

  fun receive(context: Context, id: String, ticket: String) {
    inDir(context, id).deleteRecursively()
    // A store left over from an interrupted download of the same code resumes it.
    NativeQuickSend.internetReceive(id, ticket.trim(), inDir(context, id).absolutePath, storeDirFor(context, ticket).absolutePath)
  }

  /** The receive store is keyed by the code, so retrying the same code resumes the download. */
  private fun storeDirFor(context: Context, ticket: String) =
    File(root(context), "recv-" + Integer.toHexString(ticket.trim().hashCode()))

  fun cancel(id: String) = runCatching { NativeQuickSend.internetCancel(id) }

  /**
   * Called for every "internet" core event. Publishes received files to Downloads/Quick Send and returns the
   * event to forward to the UI (with the saved file names), and removes temporary copies when a transfer ends.
   */
  fun onEvent(context: Context, envelope: JSONObject): JSONObject {
    val id = envelope.optString("id")
    val event = envelope.optJSONObject("event") ?: return envelope
    when (event.optString("type")) {
      "received" -> {
        val saved = JSONArray()
        val paths = event.optJSONArray("files") ?: JSONArray()
        for (i in 0 until paths.length()) {
          val file = File(paths.optString(i))
          if (file.isFile && publish(context, file)) saved.put(file.name)
        }
        event.put("files", saved)
        inDir(context, id).deleteRecursively()
      }
      "ended" -> {
        outDir(context, id).deleteRecursively()
        inDir(context, id).deleteRecursively()
        storeDir(context, id).deleteRecursively()
      }
    }
    return envelope
  }

  private fun publish(context: Context, file: File): Boolean = runCatching {
    val values = ContentValues().apply {
      put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
      put(MediaStore.MediaColumns.MIME_TYPE, android.webkit.MimeTypeMap.getSingleton()
        .getMimeTypeFromExtension(file.extension.lowercase()) ?: "application/octet-stream")
      put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/Quick Send")
      put(MediaStore.MediaColumns.IS_PENDING, 1)
    }
    val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return false
    context.contentResolver.openOutputStream(uri)?.use { out -> file.inputStream().use { it.copyTo(out) } }
    context.contentResolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
    file.delete()
    true
  }.getOrDefault(false)

  private fun numbered(name: String, n: Int): String {
    val dot = name.lastIndexOf('.')
    return if (dot > 0) "${name.substring(0, dot)} ($n)${name.substring(dot)}" else "$name ($n)"
  }
}
