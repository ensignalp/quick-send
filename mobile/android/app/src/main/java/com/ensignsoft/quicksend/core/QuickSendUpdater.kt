package com.ensignsoft.quicksend.core

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import android.util.Base64
import androidx.core.content.FileProvider
import com.ensignsoft.quicksend.BuildConfig
import com.ensignsoft.quicksend.R
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import javax.net.ssl.HttpsURLConnection
import org.json.JSONObject

/**
 * Background updates from GitHub Releases (Quick Send addition).
 *
 * Runs only when the build has a releases repository (QS_RELEASES_REPO) and an update signing key
 * (QS_UPDATE_PUBLIC_KEY, base64 SubjectPublicKeyInfo of an ECDSA P-256 key) and the user left
 * "Automatic updates" on. Steps:
 *  1. GET https://api.github.com/repos/<repo>/releases/latest (HTTPS only, at most every 12 hours).
 *  2. Download SHA256SUMS.txt, SHA256SUMS.txt.sig and the APK; every URL must be an https release
 *     download of this repository. HttpURLConnection never follows https -> http redirects.
 *  3. Verify the ECDSA signature of SHA256SUMS.txt, then the APK's SHA-256 against it, then that the APK
 *     is signed with the same certificate as the installed app (Android enforces this again on install).
 *  4. Post a notification; tapping it opens the system installer (Android always asks the user to
 *     confirm an update for apps that were not installed by a store).
 * Anything that fails verification is deleted.
 */
object QuickSendUpdater {
  private const val PREFS = "quick_send_updates"
  private const val LAST_CHECK = "last_check"
  private const val INTERVAL_MS = 12L * 60 * 60 * 1000
  private const val NOTIFICATION_ID = 8400
  private val running = java.util.concurrent.atomic.AtomicBoolean(false)

  private val repo: String get() = BuildConfig.RELEASES_REPO
  private val publicKey: String get() = BuildConfig.UPDATE_PUBLIC_KEY

  fun supported(): Boolean = Regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$").matches(repo) && publicKey.isNotBlank()

  /** Whether Android lets this app open the installer (Settings > Install unknown apps). */
  fun canInstall(context: Context): Boolean =
    Build.VERSION.SDK_INT < Build.VERSION_CODES.O || context.packageManager.canRequestPackageInstalls()

  /** Rate-limited background check; safe to call from app start and the receiver service. */
  fun maybeCheck(context: Context) {
    val app = context.applicationContext
    if (!supported() || !QuickSendTrust.autoUpdate(app)) return
    val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    if (System.currentTimeMillis() - prefs.getLong(LAST_CHECK, 0) < INTERVAL_MS) return
    Thread({ run(app) }, "quick-send-update").start()
  }

  /** Runs a check now (Settings > Check for updates); returns a status keyword. */
  fun run(context: Context): String {
    if (!supported()) return "notConfigured"
    if (!running.compareAndSet(false, true)) return "busy"
    val dir = File(context.cacheDir, "updates").apply { mkdirs() }
    try {
      context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putLong(LAST_CHECK, System.currentTimeMillis()).apply()
      val release = JSONObject(String(get("https://api.github.com/repos/$repo/releases/latest", 2 shl 20), Charsets.UTF_8))
      val tag = release.optString("tag_name")
      if (!isNewer(tag, BuildConfig.VERSION_NAME)) return "upToDate"
      val version = tag.removePrefix("v")

      val assets = release.optJSONArray("assets") ?: return "rejected"
      fun url(match: (String) -> Boolean): String? {
        for (i in 0 until assets.length()) {
          val a = assets.optJSONObject(i) ?: continue
          if (match(a.optString("name"))) return a.optString("browser_download_url")
        }
        return null
      }
      val sumsUrl = url { it == "SHA256SUMS.txt" }
      val sigUrl = url { it == "SHA256SUMS.txt.sig" }
      val apkUrl = url { Regex("^quick[-_]send.*\\.apk$", RegexOption.IGNORE_CASE).matches(it) }
      val prefix = "https://github.com/$repo/releases/download/"
      if (sumsUrl == null || sigUrl == null || apkUrl == null || listOf(sumsUrl, sigUrl, apkUrl).any { !it.startsWith(prefix) }) return "rejected"

      val sums = get(sumsUrl, 64 shl 10)
      val sig = get(sigUrl, 1024)
      if (!verifySignature(sums, sig)) return "rejected"
      val apkName = apkUrl.substringAfterLast('/')
      val expected = String(sums, Charsets.UTF_8).lineSequence()
        .mapNotNull { Regex("^([0-9a-fA-F]{64})\\s+\\*?(.+)$").find(it.trim()) }
        .firstOrNull { it.groupValues[2].trim() == apkName }?.groupValues?.get(1)?.lowercase() ?: return "rejected"

      dir.listFiles()?.forEach { it.delete() }
      val apk = File(dir, "Quick-Send-$version.apk")
      val actual = download(apkUrl, apk)
      if (actual != expected || !sameSigner(context, apk)) {
        apk.delete()
        return "rejected"
      }
      notifyReady(context, apk, version)
      return "ready"
    } catch (e: Exception) {
      android.util.Log.w("QuickSendUpdater", "Update check failed", e)
      return "failed"
    } finally {
      running.set(false)
    }
  }

  private fun isNewer(latest: String, current: String): Boolean {
    fun parse(v: String) = Regex("^v?(\\d+)\\.(\\d+)\\.(\\d+)").find(v.trim())?.groupValues?.drop(1)?.map { it.toInt() }
    val a = parse(latest) ?: return false
    val b = parse(current) ?: return false
    for (i in 0..2) if (a[i] != b[i]) return a[i] > b[i]
    return false
  }

  private fun verifySignature(message: ByteArray, signature: ByteArray): Boolean = runCatching {
    val key = KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(Base64.decode(publicKey, Base64.DEFAULT)))
    Signature.getInstance("SHA256withECDSA").run {
      initVerify(key)
      update(message)
      verify(signature)
    }
  }.getOrDefault(false)

  private fun certificates(info: PackageInfo?): Set<String> {
    val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      info?.signingInfo?.let { if (it.hasMultipleSigners()) it.apkContentsSigners else it.signingCertificateHistory }
    } else {
      @Suppress("DEPRECATION") info?.signatures
    } ?: return emptySet()
    return signatures.map { sha256Hex(it.toByteArray()) }.toSet()
  }

  private fun sameSigner(context: Context, apk: File): Boolean {
    val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) PackageManager.GET_SIGNING_CERTIFICATES else @Suppress("DEPRECATION") PackageManager.GET_SIGNATURES
    val pm = context.packageManager
    val archive = pm.getPackageArchiveInfo(apk.path, flags) ?: return false
    if (archive.packageName != context.packageName) return false
    val installed = certificates(pm.getPackageInfo(context.packageName, flags))
    val incoming = certificates(archive)
    return installed.isNotEmpty() && incoming.isNotEmpty() && incoming.any { it in installed }
  }

  private fun sha256Hex(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

  private fun open(url: String): HttpURLConnection {
    require(url.startsWith("https://")) { "refusing non-https URL" }
    val connection = URL(url).openConnection() as HttpsURLConnection
    connection.connectTimeout = 15_000
    connection.readTimeout = 60_000
    connection.instanceFollowRedirects = true // only https -> https; Android never follows a protocol change
    connection.setRequestProperty("User-Agent", "QuickSend-Updater")
    if (url.startsWith("https://api.github.com/")) connection.setRequestProperty("Accept", "application/vnd.github+json")
    val code = connection.responseCode
    if (code != 200 || connection.url.protocol != "https") throw IllegalStateException("HTTP $code from ${connection.url.host}")
    return connection
  }

  private fun get(url: String, maxBytes: Int): ByteArray {
    val connection = open(url)
    try {
      connection.inputStream.use { input ->
        val out = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(16 shl 10)
        while (true) {
          val n = input.read(buffer)
          if (n < 0) break
          out.write(buffer, 0, n)
          if (out.size() > maxBytes) throw IllegalStateException("response too large")
        }
        return out.toByteArray()
      }
    } finally {
      connection.disconnect()
    }
  }

  /** Streams [url] into [file]; returns the lowercase hex SHA-256 of the written bytes. */
  private fun download(url: String, file: File): String {
    val connection = open(url)
    val digest = MessageDigest.getInstance("SHA-256")
    try {
      connection.inputStream.use { input ->
        file.outputStream().use { output ->
          val buffer = ByteArray(64 shl 10)
          while (true) {
            val n = input.read(buffer)
            if (n < 0) break
            digest.update(buffer, 0, n)
            output.write(buffer, 0, n)
          }
        }
      }
    } finally {
      connection.disconnect()
    }
    return digest.digest().joinToString("") { "%02x".format(it) }
  }

  private fun notifyReady(context: Context, apk: File, version: String) {
    QuickSendNotifications.ensureChannel(context)
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.updates", apk)
    val install = Intent(Intent.ACTION_VIEW)
      .setDataAndType(uri, "application/vnd.android.package-archive")
      .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
    val pending = PendingIntent.getActivity(context, NOTIFICATION_ID, install, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    val tr = context.resources.configuration.locales[0].language == "tr"
    val notification = Notification.Builder(context, QuickSendNotifications.CHANNEL_ID)
      .setSmallIcon(R.drawable.ic_stat_quicksend)
      .setColor(context.getColor(R.color.quick_send_primary))
      .setContentTitle(if (tr) "Quick Send $version hazır" else "Quick Send $version is ready")
      .setContentText(if (tr) "Doğrulandı. Kurmak için dokun." else "Verified. Tap to install.")
      .setContentIntent(pending)
      .setAutoCancel(true)
      .build()
    context.getSystemService(android.app.NotificationManager::class.java).notify(NOTIFICATION_ID, notification)
  }
}
