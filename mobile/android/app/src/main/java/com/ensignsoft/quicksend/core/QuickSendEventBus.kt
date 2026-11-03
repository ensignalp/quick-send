package com.ensignsoft.quicksend.core

import java.util.concurrent.CopyOnWriteArraySet

object QuickSendEventBus {
  private val listeners = CopyOnWriteArraySet<(String) -> Unit>()

  fun addListener(listener: (String) -> Unit) {
    listeners.add(listener)
  }

  fun removeListener(listener: (String) -> Unit) {
    listeners.remove(listener)
  }

  fun emit(eventJson: String) {
    listeners.forEach { listener -> runCatching { listener(eventJson) } }
  }
}
