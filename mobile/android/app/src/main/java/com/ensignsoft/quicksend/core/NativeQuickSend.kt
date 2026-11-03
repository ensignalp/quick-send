package com.ensignsoft.quicksend.core

object NativeQuickSend {
  init {
    System.loadLibrary("quicksend_core")
  }

  @JvmStatic external fun generateIdentity(): String
  @JvmStatic external fun initialize(callback: QuickSendCoreCallbacks, alias: String, identityJson: String, visible: Boolean)
  @JvmStatic external fun respond(sessionId: String, accepted: Boolean)
  @JvmStatic external fun setVisibility(visible: Boolean)
  @JvmStatic external fun send(deviceJson: String, filesJson: String, descriptors: IntArray, transferId: String)
  @JvmStatic external fun cancel(transferId: String)
}

interface QuickSendCoreCallbacks {
  fun onCoreEvent(eventJson: String)
  fun openReceivedFile(sessionId: String, fileId: String, fileName: String, mimeType: String): Int
}
