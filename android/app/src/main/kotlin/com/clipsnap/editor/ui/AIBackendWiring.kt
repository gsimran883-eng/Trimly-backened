package com.clipsnap.editor.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

interface AIPipelineController {
    fun runLocalSubjectMask()

    fun setMaskTarget(target: String)
    fun setDepthMapping(enabled: Boolean)
    fun setVolumetricLighting(enabled: Boolean)
    fun setEdgeRefining(enabled: Boolean)

    fun setBrushTool(tool: String)
    fun setBrushSize(value: Float)
    fun setBrushHardness(value: Float)
    fun setBrushOpacity(value: Float)
    fun onFlowTap()
    fun onZoomTap()

    fun requestCloudUpscale(multiplier: String)
    fun requestCloudSkyReplacement(preset: String)
    fun onSubjectRefinementToggled(expanded: Boolean)
}

@Composable
fun ConnectedAIPipelinePanels(
    controller: AIPipelineController,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        AIMaskingOverlay(
            modifier = Modifier.fillMaxWidth(),
            onMaskTargetSelected = controller::setMaskTarget,
            onDepthMappingChanged = controller::setDepthMapping,
            onVolumetricLightingChanged = controller::setVolumetricLighting,
            onEdgeRefiningChanged = controller::setEdgeRefining,
        )

        ProBrushToolbar(
            modifier = Modifier.fillMaxWidth(),
            onBrushToolSelected = controller::setBrushTool,
            onSizeChanged = controller::setBrushSize,
            onHardnessChanged = controller::setBrushHardness,
            onOpacityChanged = controller::setBrushOpacity,
            onFlowTap = controller::onFlowTap,
            onZoomTap = controller::onZoomTap,
        )

        AIUpscalingPanel(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 4.dp),
            onApplyUpscale = controller::requestCloudUpscale,
            onApplySkyReplacement = controller::requestCloudSkyReplacement,
            onSubjectRefinementToggled = controller::onSubjectRefinementToggled,
        )
    }
}
