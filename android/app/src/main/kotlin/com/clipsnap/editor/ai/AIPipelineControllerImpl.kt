package com.clipsnap.editor.ai

import android.graphics.Bitmap
import com.clipsnap.editor.ui.AIPipelineController

class AIPipelineControllerImpl(
    private val aiEngine: ClipSnapAIEngine,
    private val listener: Listener,
) : AIPipelineController {

    interface Listener {
        fun onLocalMaskReady(bitmap: Bitmap)
        fun onLocalMaskFailed()

        fun onCloudUpscaleRequested(multiplier: String)
        fun onCloudSkyReplacementRequested(preset: String)

        fun onMaskTargetChanged(target: String)
        fun onDepthMappingChanged(enabled: Boolean)
        fun onVolumetricLightingChanged(enabled: Boolean)
        fun onEdgeRefiningChanged(enabled: Boolean)

        fun onBrushToolChanged(tool: String)
        fun onBrushSizeChanged(value: Float)
        fun onBrushHardnessChanged(value: Float)
        fun onBrushOpacityChanged(value: Float)
        fun onFlowTapped()
        fun onZoomTapped()

        fun onSubjectRefinementToggled(expanded: Boolean)
    }

    private var currentBitmap: Bitmap? = null

    fun setCurrentBitmap(bitmap: Bitmap?) {
        currentBitmap = bitmap
    }

    override fun runLocalSubjectMask() {
        val source = currentBitmap
        if (source == null) {
            listener.onLocalMaskFailed()
            return
        }

        aiEngine.processFrame(source) { result ->
            if (result == null) {
                listener.onLocalMaskFailed()
            } else {
                listener.onLocalMaskReady(result)
            }
        }
    }

    override fun setMaskTarget(target: String) {
        listener.onMaskTargetChanged(target)
    }

    override fun setDepthMapping(enabled: Boolean) {
        listener.onDepthMappingChanged(enabled)
    }

    override fun setVolumetricLighting(enabled: Boolean) {
        listener.onVolumetricLightingChanged(enabled)
    }

    override fun setEdgeRefining(enabled: Boolean) {
        listener.onEdgeRefiningChanged(enabled)
    }

    override fun setBrushTool(tool: String) {
        listener.onBrushToolChanged(tool)
    }

    override fun setBrushSize(value: Float) {
        listener.onBrushSizeChanged(value)
    }

    override fun setBrushHardness(value: Float) {
        listener.onBrushHardnessChanged(value)
    }

    override fun setBrushOpacity(value: Float) {
        listener.onBrushOpacityChanged(value)
    }

    override fun onFlowTap() {
        listener.onFlowTapped()
    }

    override fun onZoomTap() {
        listener.onZoomTapped()
    }

    override fun requestCloudUpscale(multiplier: String) {
        listener.onCloudUpscaleRequested(multiplier)
    }

    override fun requestCloudSkyReplacement(preset: String) {
        listener.onCloudSkyReplacementRequested(preset)
    }

    override fun onSubjectRefinementToggled(expanded: Boolean) {
        listener.onSubjectRefinementToggled(expanded)
    }
}
