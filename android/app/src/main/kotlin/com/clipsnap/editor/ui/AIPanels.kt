package com.clipsnap.editor.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoFixHigh
import androidx.compose.material.icons.outlined.Brush
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.FilterHdr
import androidx.compose.material.icons.outlined.Landscape
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.material.icons.outlined.ViewInAr
import androidx.compose.material.icons.outlined.ZoomIn
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.Divider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val Sapphire500 = Color(0xFF3B82F6)
private val Sapphire600 = Color(0xFF2563EB)
private val PanelBg = Color(0xFF171B22)
private val PanelBgSoft = Color(0xFF1E2530)
private val PanelStroke = Color(0xFF2A3342)
private val MutedText = Color(0xFF9CA7BA)
private val HeadingText = Color(0xFFE7EDF8)

@Composable
fun AIMaskingOverlay(
    modifier: Modifier = Modifier,
    onMaskTargetSelected: (String) -> Unit = {},
    onDepthMappingChanged: (Boolean) -> Unit = {},
    onVolumetricLightingChanged: (Boolean) -> Unit = {},
    onEdgeRefiningChanged: (Boolean) -> Unit = {},
) {
    var selectedTarget by remember { mutableIntStateOf(0) }
    var depthMapping by remember { mutableStateOf(true) }
    var volumetricLighting by remember { mutableStateOf(false) }
    var edgeRefining by remember { mutableStateOf(true) }

    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(20.dp),
        color = PanelBg,
        tonalElevation = 8.dp,
        shadowElevation = 20.dp,
    ) {
        Column(modifier = Modifier.padding(18.dp)) {
            Text(
                text = "AI-Powered Object Masking",
                color = HeadingText,
                fontSize = 18.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "Intelligent mask generation for subjects, background, and objects",
                color = MutedText,
                style = MaterialTheme.typography.bodySmall,
            )

            Spacer(modifier = Modifier.height(16.dp))

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(modifier = Modifier.weight(1f)) {
                    MaskSelectChip(
                        label = "Subject",
                        icon = Icons.Outlined.Layers,
                        selected = selectedTarget == 0,
                        onClick = {
                            selectedTarget = 0
                            onMaskTargetSelected("subject")
                        },
                    )
                }
                Box(modifier = Modifier.weight(1f)) {
                    MaskSelectChip(
                        label = "Background",
                        icon = Icons.Outlined.Landscape,
                        selected = selectedTarget == 1,
                        onClick = {
                            selectedTarget = 1
                            onMaskTargetSelected("background")
                        },
                    )
                }
                Box(modifier = Modifier.weight(1f)) {
                    MaskSelectChip(
                        label = "Add Depth Mask",
                        icon = Icons.Outlined.ViewInAr,
                        selected = selectedTarget == 2,
                        onClick = {
                            selectedTarget = 2
                            onMaskTargetSelected("depth")
                        },
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))
            Divider(color = PanelStroke)
            Spacer(modifier = Modifier.height(12.dp))

            ToggleRow(
                title = "Depth Mapping",
                checked = depthMapping,
                onCheckedChange = {
                    depthMapping = it
                    onDepthMappingChanged(it)
                },
            )
            ToggleRow(
                title = "Volumetric Lighting",
                checked = volumetricLighting,
                onCheckedChange = {
                    volumetricLighting = it
                    onVolumetricLightingChanged(it)
                },
            )
            ToggleRow(
                title = "Edge Refining",
                checked = edgeRefining,
                onCheckedChange = {
                    edgeRefining = it
                    onEdgeRefiningChanged(it)
                },
            )
        }
    }
}

@Composable
private fun MaskSelectChip(
    label: String,
    icon: ImageVector,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val bg = if (selected) {
        Brush.linearGradient(listOf(Sapphire600, Sapphire500))
    } else {
        Brush.linearGradient(listOf(PanelBgSoft, PanelBgSoft))
    }
    val textColor = if (selected) Color.White else HeadingText

    Card(
        modifier = Modifier
            .clip(RoundedCornerShape(14.dp))
            .clickable(onClick = onClick),
        colors = CardDefaults.cardColors(containerColor = Color.Transparent),
        border = androidx.compose.foundation.BorderStroke(1.dp, if (selected) Sapphire500 else PanelStroke),
    ) {
        Row(
            modifier = Modifier
                .background(bg)
                .padding(horizontal = 10.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center,
        ) {
            Icon(icon, contentDescription = label, tint = textColor, modifier = Modifier.size(16.dp))
            Spacer(modifier = Modifier.width(6.dp))
            Text(text = label, color = textColor, fontSize = 12.sp, fontWeight = FontWeight.Medium)
        }
    }
}

@Composable
private fun ToggleRow(title: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text = title, color = HeadingText, fontSize = 14.sp)
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

@Composable
fun ProBrushToolbar(
    modifier: Modifier = Modifier,
    onBrushToolSelected: (String) -> Unit = {},
    onSizeChanged: (Float) -> Unit = {},
    onHardnessChanged: (Float) -> Unit = {},
    onOpacityChanged: (Float) -> Unit = {},
    onFlowTap: () -> Unit = {},
    onZoomTap: () -> Unit = {},
) {
    var selectedTool by remember { mutableIntStateOf(0) }
    var size by remember { mutableFloatStateOf(38f) }
    var hardness by remember { mutableFloatStateOf(64f) }
    var opacity by remember { mutableFloatStateOf(78f) }

    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(24.dp),
        color = PanelBg,
        tonalElevation = 8.dp,
        shadowElevation = 18.dp,
    ) {
        Column(modifier = Modifier.padding(14.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Box(modifier = Modifier.weight(1f)) {
                    ToolButton(
                        label = "Selection Brush",
                        icon = Icons.Outlined.Brush,
                        selected = selectedTool == 0,
                        onClick = {
                            selectedTool = 0
                            onBrushToolSelected("selection_brush")
                        },
                    )
                }
                Box(modifier = Modifier.weight(1f)) {
                    ToolButton(
                        label = "Heal Brush",
                        icon = Icons.Outlined.AutoFixHigh,
                        selected = selectedTool == 1,
                        onClick = {
                            selectedTool = 1
                            onBrushToolSelected("heal_brush")
                        },
                    )
                }
                Box(modifier = Modifier.weight(1f)) {
                    ToolButton(
                        label = "Clone Stamp",
                        icon = Icons.Outlined.FilterHdr,
                        selected = selectedTool == 2,
                        onClick = {
                            selectedTool = 2
                            onBrushToolSelected("clone_stamp")
                        },
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))
            BrushSlider("Size", size) {
                size = it
                onSizeChanged(it)
            }
            BrushSlider("Hardness", hardness) {
                hardness = it
                onHardnessChanged(it)
            }
            BrushSlider("Opacity", opacity) {
                opacity = it
                onOpacityChanged(it)
            }

            Spacer(modifier = Modifier.height(6.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                MiniIconControl("Flow", Icons.Outlined.Cloud, onClick = onFlowTap)
                MiniIconControl("Zoom", Icons.Outlined.ZoomIn, onClick = onZoomTap)
            }
        }
    }
}

@Composable
private fun ToolButton(
    label: String,
    icon: ImageVector,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val tint = if (selected) Sapphire500 else MutedText
    val border = if (selected) Sapphire500 else PanelStroke

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(14.dp),
        color = PanelBgSoft,
        border = androidx.compose.foundation.BorderStroke(1.dp, border),
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(icon, contentDescription = label, tint = tint, modifier = Modifier.size(18.dp))
            Spacer(modifier = Modifier.height(4.dp))
            Text(text = label, color = HeadingText, fontSize = 11.sp, maxLines = 1)
        }
    }
}

@Composable
private fun BrushSlider(title: String, value: Float, onValueChange: (Float) -> Unit) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(text = title, color = HeadingText, fontSize = 13.sp)
            Text(text = value.toInt().toString(), color = MutedText, fontSize = 12.sp)
        }
        Slider(
            value = value,
            onValueChange = onValueChange,
            valueRange = 0f..100f,
        )
    }
}

@Composable
private fun MiniIconControl(label: String, icon: ImageVector, onClick: () -> Unit) {
    Surface(
        modifier = Modifier
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(12.dp),
        color = PanelBgSoft,
        border = androidx.compose.foundation.BorderStroke(1.dp, PanelStroke),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(icon, contentDescription = label, tint = Sapphire500, modifier = Modifier.size(16.dp))
            Spacer(modifier = Modifier.width(6.dp))
            Text(text = label, color = HeadingText, fontSize = 12.sp)
        }
    }
}

@Composable
fun AIUpscalingPanel(
    modifier: Modifier = Modifier,
    onScaleSelected: (String) -> Unit = {},
    onApplyUpscale: (String) -> Unit = {},
    onSkyPresetSelected: (String) -> Unit = {},
    onApplySkyReplacement: (String) -> Unit = {},
    onSubjectRefinementToggled: (Boolean) -> Unit = {},
) {
    var selectedScale by remember { mutableIntStateOf(0) }
    var selectedSkyPreset by remember { mutableStateOf("Sunny") }
    var skyExpanded by remember { mutableStateOf(true) }
    var subjectExpanded by remember { mutableStateOf(false) }

    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(20.dp),
        color = PanelBg,
        tonalElevation = 8.dp,
        shadowElevation = 18.dp,
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "AI-Powered Generative Image Enhancement",
                color = HeadingText,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
            )

            Spacer(modifier = Modifier.height(14.dp))
            val labels = listOf("2x", "4x", "8x", "Ultra")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                labels.forEachIndexed { index, label ->
                    val selected = selectedScale == index
                    Surface(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(12.dp))
                            .clickable {
                                selectedScale = index
                                onScaleSelected(label)
                            },
                        shape = RoundedCornerShape(12.dp),
                        color = if (selected) Sapphire600 else PanelBgSoft,
                        border = androidx.compose.foundation.BorderStroke(1.dp, if (selected) Sapphire500 else PanelStroke),
                    ) {
                        Box(modifier = Modifier.padding(vertical = 10.dp), contentAlignment = Alignment.Center) {
                            Text(
                                text = label,
                                color = if (selected) Color.White else HeadingText,
                                fontWeight = FontWeight.Medium,
                                fontSize = 13.sp,
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(10.dp))
            Button(onClick = { onApplyUpscale(labels[selectedScale]) }) {
                Text("Apply ${labels[selectedScale]}")
            }

            Spacer(modifier = Modifier.height(16.dp))
            AccordionHeader("Smart Sky Replacement", skyExpanded) { skyExpanded = !skyExpanded }
            AnimatedVisibility(visible = skyExpanded) {
                Column {
                    Spacer(modifier = Modifier.height(8.dp))
                    Row(
                        modifier = Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        listOf("Sunny", "Sunset", "Starry").forEach { title ->
                            SkyThumb(
                                title = title,
                                selected = selectedSkyPreset == title,
                                onClick = {
                                    selectedSkyPreset = title
                                    onSkyPresetSelected(title)
                                },
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(8.dp))
                    Button(onClick = { onApplySkyReplacement(selectedSkyPreset) }) {
                        Text("Apply $selectedSkyPreset Sky")
                    }
                }
            }

            Spacer(modifier = Modifier.height(12.dp))
            AccordionHeader("Subject Refinement", subjectExpanded) {
                subjectExpanded = !subjectExpanded
                onSubjectRefinementToggled(subjectExpanded)
            }
            AnimatedVisibility(visible = subjectExpanded) {
                Column(modifier = Modifier.padding(top = 8.dp)) {
                    Text(
                        text = "Face clarity, edge cleanup, and skin tone balancing are ready.",
                        color = MutedText,
                        fontSize = 13.sp,
                    )
                }
            }
        }
    }
}

@Composable
private fun AccordionHeader(title: String, expanded: Boolean, onClick: () -> Unit) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onClick),
        color = PanelBgSoft,
        border = androidx.compose.foundation.BorderStroke(1.dp, PanelStroke),
        shape = RoundedCornerShape(12.dp),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(text = title, color = HeadingText, fontSize = 14.sp)
            Box(
                modifier = Modifier
                    .size(20.dp)
                    .background(if (expanded) Sapphire600 else Color(0xFF273141), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Text(text = if (expanded) "−" else "+", color = Color.White, fontSize = 14.sp)
            }
        }
    }
}

@Composable
private fun SkyThumb(title: String, selected: Boolean, onClick: () -> Unit) {
    val gradient = when (title) {
        "Sunny" -> Brush.linearGradient(listOf(Color(0xFF87CEFA), Color(0xFFFCD34D)))
        "Sunset" -> Brush.linearGradient(listOf(Color(0xFFF97316), Color(0xFF7C3AED)))
        else -> Brush.linearGradient(listOf(Color(0xFF111827), Color(0xFF334155)))
    }

    Surface(
        modifier = Modifier
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(12.dp),
        border = androidx.compose.foundation.BorderStroke(1.dp, if (selected) Sapphire500 else PanelStroke),
        color = PanelBgSoft,
    ) {
        Column(modifier = Modifier.padding(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(
                modifier = Modifier
                    .width(94.dp)
                    .height(62.dp)
                    .background(gradient, RoundedCornerShape(10.dp)),
            )
            Spacer(modifier = Modifier.height(6.dp))
            Text(title, color = HeadingText, fontSize = 12.sp)
        }
    }
}
