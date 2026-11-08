package com.ensignsoft.quicksend.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class QuickSendFilesTest {
  @Test fun removesPathSeparatorsAndTraversal() {
    val names = listOf("../../etc/passwd", "..\\..\\evil.exe", "a/b/c.txt", "/abs/path")
    for (n in names) {
      val safe = QuickSendFiles.safeName(n)
      assertFalse(safe, safe.contains('/'))
      assertFalse(safe, safe.contains('\\'))
      assertFalse(safe, safe.startsWith("."))
    }
    assertEquals("a_b_c.txt", QuickSendFiles.safeName("a/b/c.txt"))
  }

  @Test fun dotOnlyAndBlankNamesFallBack() {
    assertEquals("shared-file", QuickSendFiles.safeName(".."))
    assertEquals("shared-file", QuickSendFiles.safeName("   "))
    assertEquals("shared-file", QuickSendFiles.safeName(""))
  }

  @Test fun stripsControlCharactersAndLimitsLength() {
    assertEquals("a_b", QuickSendFiles.safeName("a\u0000b"))
    assertEquals(240, QuickSendFiles.safeName("x".repeat(500)).length)
  }

  @Test fun keepsUnicodeNames() {
    assertEquals("Gelecek İHH Marşı.mp4", QuickSendFiles.safeName("Gelecek İHH Marşı.mp4"))
  }
}
