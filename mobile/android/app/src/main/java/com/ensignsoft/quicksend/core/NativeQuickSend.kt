package com.ensignsoft.quicksend.core

object NativeQuickSend {
  init {
    System.loadLibrary("quicksend_core")
  }

  @JvmStatic external fun generateIdentity(): String
  @JvmStatic external fun initialize(callback: QuickSendCoreCallbacks, alias: String, identityJson: String, visible: Boolean, pin: String)
  @JvmStatic external fun respond(sessionId: String, accepted: Boolean)
  @JvmStatic external fun setVisibility(visible: Boolean)
  @JvmStatic external fun send(deviceJson: String, filesJson: String, descriptors: IntArray, transferId: String)
  @JvmStatic external fun cancel(transferId: String)

  // Quick Send: transfers over the internet (iroh, packages/qs_internet).
  @JvmStatic external fun internetSend(id: String, filesJson: String, dataDir: String)
  @JvmStatic external fun internetReceive(id: String, ticket: String, destDir: String, dataDir: String)
  @JvmStatic external fun internetCancel(id: String)
  @JvmStatic external fun internetIsValidTicket(ticket: String): Boolean
  @JvmStatic external fun initAndroidContext(context: android.content.Context)
}

interface QuickSendCoreCallbacks {
  fun onCoreEvent(eventJson: String)
  fun openReceivedFile(sessionId: String, fileId: String, fileName: String, mimeType: String): Int
}
