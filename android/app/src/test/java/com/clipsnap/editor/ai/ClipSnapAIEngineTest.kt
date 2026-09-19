package com.clipsnap.editor.ai

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ClipSnapAIEngineTest {
    @Test
    fun `subject segmentation is disabled on Android 15 and newer`() {
        assertFalse(ClipSnapAIEngine.isSegmentationSupported(35))
        assertFalse(ClipSnapAIEngine.isSegmentationSupported(36))
    }

    @Test
    fun `subject segmentation remains enabled on Android 14 and older`() {
        assertTrue(ClipSnapAIEngine.isSegmentationSupported(34))
        assertTrue(ClipSnapAIEngine.isSegmentationSupported(33))
    }
}
