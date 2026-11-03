package com.ensignsoft.quicksend

import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.ensignsoft.quicksend.core.QuickSendCoreHost

class QuickSendTileService : TileService() {
  override fun onStartListening() {
    super.onStartListening()
    updateTile()
  }

  override fun onClick() {
    super.onClick()
    val prefs = getSharedPreferences(QuickSendService.PREFS, MODE_PRIVATE)
    val enabled = prefs.getBoolean(QuickSendService.RECEIVER_ENABLED, false)
    if (enabled) {
      QuickSendService.stop(this)
    } else if (Build.VERSION.SDK_INT >= 37 && checkSelfPermission(android.Manifest.permission.ACCESS_LOCAL_NETWORK) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
      val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
      startActivityAndCollapse(intent)
    } else if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
      val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
      startActivityAndCollapse(intent)
    } else {
      QuickSendCoreHost.start(this)
      QuickSendService.start(this)
    }
    qsTile?.state = if (enabled) Tile.STATE_INACTIVE else Tile.STATE_ACTIVE
    qsTile?.updateTile()
  }

  private fun updateTile() {
    val enabled = getSharedPreferences(QuickSendService.PREFS, MODE_PRIVATE).getBoolean(QuickSendService.RECEIVER_ENABLED, false)
    qsTile?.label = if (resources.configuration.locales[0].language == "tr") "Quick Send" else "Quick Send"
    qsTile?.state = if (enabled) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
    qsTile?.updateTile()
  }
}
