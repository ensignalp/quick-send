package com.ensignsoft.quicksend.core

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File
import java.util.UUID

data class SharedFileData(
  val id: String,
  val uri: Uri,
  val name: String,
  val mimeType: String,
  val size: Long,
)

data class SendFileData(val file: SharedFileData, val cacheFile: File?)

object QuickSendFiles {
  fun fromIntent(context: Context, intent: Intent?): List<SharedFileData> {
    if (intent == null || (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE)) return emptyList()
    val uris = linkedSetOf<Uri>()
    val clip = intent.clipData
    if (clip != null) {
      for (index in 0 until clip.itemCount) clip.getItemAt(index).uri?.let(uris::add)
    }
    @Suppress("DEPRECATION")
    when (intent.action) {
      Intent.ACTION_SEND -> (intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))?.let(uris::add)
      Intent.ACTION_SEND_MULTIPLE -> {
        @Suppress("DEPRECATION")
        val values = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        values?.forEach(uris::add)
      }
    }
    return uris.mapIndexed { index, uri -> describe(context, uri, intent.type, "shared-$index") }
  }

  fun describe(context: Context, uri: Uri, hintedMime: String? = null, id: String = UUID.randomUUID().toString()): SharedFileData {
    var name = uri.lastPathSegment?.substringAfterLast('/')?.takeIf(String::isNotBlank) ?: "shared-file"
    var size = -1L
    runCatching {
      context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) {
          val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
          val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
          if (nameIndex >= 0) cursor.getString(nameIndex)?.takeIf(String::isNotBlank)?.let { name = it }
          if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) size = cursor.getLong(sizeIndex)
        }
      }
    }
    val mime = context.contentResolver.getType(uri) ?: hintedMime ?: "application/octet-stream"
    return SharedFileData(id, uri, safeName(name), mime, size)
  }

  fun resolveForSend(context: Context, value: SharedFileData): SendFileData {
    var file = value
    var cached: File? = null
    if (file.size < 0L) {
      val input = context.contentResolver.openInputStream(file.uri) ?: error("Unable to read ${file.name}")
      val outputFile = File(context.cacheDir, "send-${UUID.randomUUID()}-${safeName(file.name)}")
      input.use { source -> outputFile.outputStream().use(source::copyTo) }
      cached = outputFile
      file = file.copy(uri = Uri.fromFile(outputFile), size = outputFile.length())
    }
    return SendFileData(file, cached)
  }

  fun safeName(input: String): String {
    val cleaned = input
      .replace(Regex("[/\\\\\\u0000-\\u001F\\u007F]"), "_")
      .trim()
      .trim('.')
    return cleaned.ifBlank { "shared-file" }.take(240)
  }
}

object QuickSendShare {
  @Volatile private var pendingIntent: Intent? = null

  fun capture(intent: Intent?) {
    if (intent?.action == Intent.ACTION_SEND || intent?.action == Intent.ACTION_SEND_MULTIPLE) {
      pendingIntent = intent
    }
  }

  @Synchronized fun consume(context: Context): List<SharedFileData> {
    val value = pendingIntent ?: return emptyList()
    pendingIntent = null
    return QuickSendFiles.fromIntent(context, value)
  }
}
