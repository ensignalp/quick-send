package com.ensignsoft.quicksend

import android.content.Intent
import com.facebook.react.ReactActivity
import com.facebook.react.ReactActivityDelegate
import com.facebook.react.defaults.DefaultNewArchitectureEntryPoint.fabricEnabled
import com.facebook.react.defaults.DefaultReactActivityDelegate
import com.ensignsoft.quicksend.core.QuickSendEventBus
import com.ensignsoft.quicksend.core.QuickSendFiles
import com.ensignsoft.quicksend.core.QuickSendShare
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : ReactActivity() {
  override fun getMainComponentName(): String = "QuickSendMobile"

  override fun createReactActivityDelegate(): ReactActivityDelegate =
    DefaultReactActivityDelegate(this, mainComponentName, fabricEnabled)

  override fun onCreate(savedInstanceState: android.os.Bundle?) {
    QuickSendShare.capture(intent)
    super.onCreate(savedInstanceState)
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    QuickSendShare.capture(intent)
    val files = QuickSendFiles.fromIntent(this, intent)
    val json = JSONArray()
    files.forEach { file -> json.put(JSONObject().apply {
      put("id", file.id)
      put("uri", file.uri.toString())
      put("name", file.name)
      put("mimeType", file.mimeType)
      put("size", file.size)
    }) }
    QuickSendEventBus.emit(JSONObject().put("type", "sharedFiles").put("files", json).toString())
  }
}
