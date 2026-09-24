package com.clipsnap.editor.ai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ClipSnapAIEngineTest {
    @Test
    fun `subject segmentation is enabled on every supported app API`() {
        assertTrue(ClipSnapAIEngine.isSegmentationSupported(36))
        assertTrue(ClipSnapAIEngine.isSegmentationSupported(35))
        assertTrue(ClipSnapAIEngine.isSegmentationSupported(34))
        assertTrue(ClipSnapAIEngine.isSegmentationSupported(24))
    }

    @Test
    fun `camera images are sampled below the ML memory ceiling`() {
        assertEquals(4, ClipSnapAIEngine.calculateInSampleSize(4032, 3024, 1280))
        assertEquals(16, ClipSnapAIEngine.calculateInSampleSize(12000, 9000, 1280))
        assertEquals(1, ClipSnapAIEngine.calculateInSampleSize(1080, 1920, 1920))
    }
}
