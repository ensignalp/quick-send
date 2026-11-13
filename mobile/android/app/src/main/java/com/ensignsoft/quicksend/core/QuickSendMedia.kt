package com.ensignsoft.quicksend.core

import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import android.util.Base64
import android.util.Size
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest

/**
 * Media library access for the in-app file picker: lists images, videos and
 * documents from MediaStore, renders cached thumbnails, and lists the apps
 * that can provide content (the "Other" tab). Read-only; nothing here touches
 * the LocalSend protocol.
 */
object QuickSendMedia {
  private val documentMimes = listOf(
    "application/pdf", "text/plain", "text/csv", "text/html", "application/rtf", "application/epub+zip",
    "application/msword", "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.ms-excel", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "application/vnd.ms-powerpoint", "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    "application/vnd.oasis.opendocument.text", "application/vnd.oasis.opendocument.spreadsheet",
    "application/zip", "application/x-7z-compressed", "application/x-rar-compressed", "application/vnd.android.package-archive",
  )

  /** [kind] is `images`, `videos` or `documents`; newest first. */
  fun query(context: Context, kind: String, limit: Int, offset: Int): JSONArray {
    val result = JSONArray()
    val (collection, selection, args) = when (kind) {
      "images" -> Triple(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, null, null)
      "videos" -> Triple(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, null, null)
      else -> Triple(
        MediaStore.Files.getContentUri("external"),
        "${MediaStore.Files.FileColumns.MIME_TYPE} IN (${documentMimes.joinToString(",") { "?" }})",
        documentMimes.toTypedArray(),
      )
    }
    val projection = buildList {
      add(MediaStore.MediaColumns._ID)
      add(MediaStore.MediaColumns.DISPLAY_NAME)
      add(MediaStore.MediaColumns.MIME_TYPE)
      add(MediaStore.MediaColumns.SIZE)
      add(MediaStore.MediaColumns.DATE_MODIFIED)
      add(MediaStore.MediaColumns.DATE_TAKEN)
      if (kind == "videos") add(MediaStore.Video.VideoColumns.DURATION)
    }.toTypedArray()
    val queryArgs = Bundle().apply {
      putString(ContentResolver.QUERY_ARG_SQL_SORT_ORDER, "${MediaStore.MediaColumns.DATE_MODIFIED} DESC")
      putInt(ContentResolver.QUERY_ARG_LIMIT, limit)
      putInt(ContentResolver.QUERY_ARG_OFFSET, offset)
      if (selection != null) {
        putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
        putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, args)
      }
    }
    context.contentResolver.query(collection, projection, queryArgs, null)?.use { cursor ->
      val id = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
      val name = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
      val mime = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
      val size = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
      val modified = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
      val taken = cursor.getColumnIndex(MediaStore.MediaColumns.DATE_TAKEN)
      val duration = cursor.getColumnIndex(MediaStore.Video.VideoColumns.DURATION)
      while (cursor.moveToNext()) {
        val rowId = cursor.getLong(id)
        val takenAt = if (taken >= 0 && !cursor.isNull(taken)) cursor.getLong(taken) else 0L
        result.put(JSONObject().apply {
          put("id", "m-$kind-$rowId")
          put("uri", ContentUris.withAppendedId(collection, rowId).toString())
          put("name", cursor.getString(name) ?: "file")
          put("mimeType", cursor.getString(mime) ?: "application/octet-stream")
          put("size", cursor.getLong(size))
          put("date", if (takenAt > 0) takenAt else cursor.getLong(modified) * 1000)
          if (duration >= 0 && !cursor.isNull(duration)) put("duration", cursor.getLong(duration))
        })
      }
    }
    return result
  }

  /** A square JPEG thumbnail cached in the app cache; returns a `file://` URI. */
  fun thumbnail(context: Context, uri: Uri, size: Int): String {
    val dir = File(context.cacheDir, "thumbs").apply { mkdirs() }
    val key = MessageDigest.getInstance("SHA-1").digest("$uri@$size".toByteArray()).joinToString("") { "%02x".format(it) }
    val file = File(dir, "$key.jpg")
    if (!file.exists()) {
      val bitmap = context.contentResolver.loadThumbnail(uri, Size(size, size), null)
      file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 82, it) }
      bitmap.recycle()
    }
    return Uri.fromFile(file).toString()
  }

  /** Copies [source] into app storage as a 384px center-cropped JPEG and returns its `file://` URI. */
  fun saveAvatar(context: Context, source: Uri): String {
    val decoded = ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, source)) { decoder, info, _ ->
      val longest = maxOf(info.size.width, info.size.height)
      if (longest > 1536) decoder.setTargetSampleSize(longest / 1536)
      decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
    }
    val side = minOf(decoded.width, decoded.height)
    val cropped = Bitmap.createBitmap(decoded, (decoded.width - side) / 2, (decoded.height - side) / 2, side, side)
    val scaled = Bitmap.createScaledBitmap(cropped, 384, 384, true)
    File(context.filesDir, "avatar").listFiles()?.forEach { it.delete() }
    val file = File(File(context.filesDir, "avatar").apply { mkdirs() }, "avatar-${System.currentTimeMillis()}.jpg")
    file.outputStream().use { scaled.compress(Bitmap.CompressFormat.JPEG, 90, it) }
    return Uri.fromFile(file).toString()
  }

  fun clearAvatar(context: Context) {
    File(context.filesDir, "avatar").listFiles()?.forEach { it.delete() }
  }

  /** Apps that can hand over files (ACTION_GET_CONTENT), with their icons as PNG data URIs. */
  fun contentApps(context: Context): JSONArray {
    val pm = context.packageManager
    val intent = Intent(Intent.ACTION_GET_CONTENT).setType("*/*").addCategory(Intent.CATEGORY_OPENABLE)
    val result = JSONArray()
    pm.queryIntentActivities(intent, 0)
      .filter { it.activityInfo.packageName != context.packageName }
      .distinctBy { it.activityInfo.packageName }
      .sortedBy { it.loadLabel(pm).toString().lowercase() }
      .forEach { info ->
        result.put(JSONObject().apply {
          put("label", info.loadLabel(pm).toString())
          put("package", info.activityInfo.packageName)
          put("activity", info.activityInfo.name)
          put("icon", iconDataUri(info.loadIcon(pm)))
        })
      }
    return result
  }

  private fun iconDataUri(drawable: android.graphics.drawable.Drawable): String {
    val bitmap = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    drawable.setBounds(0, 0, 96, 96)
    drawable.draw(canvas)
    val bytes = ByteArrayOutputStream().use { out -> bitmap.compress(Bitmap.CompressFormat.PNG, 100, out); out.toByteArray() }
    bitmap.recycle()
    return "data:image/png;base64," + Base64.encodeToString(bytes, Base64.NO_WRAP)
  }

  val documentMimeTypes: Array<String> get() = documentMimes.toTypedArray()
}
