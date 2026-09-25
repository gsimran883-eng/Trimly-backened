import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/template_presets.dart';
import '../models/template_model.dart';
import '../services/ai_generative_template_service.dart';
import '../services/ai_image_cloud_service.dart';
import '../services/ai_local_segmentation_service.dart';
import '../services/api_service.dart';
import '../services/export_status_service.dart';
import '../services/monetization_service.dart';
import '../services/point_service.dart';
import '../theme/motion_spec.dart';

class ClipSnapProEditor extends StatefulWidget {
  final File? imageFile;
  final String? initialAiTool;
  final Map<String, Object?>? initialAiConfig;

  const ClipSnapProEditor({
    super.key,
    this.imageFile,
    this.initialAiTool,
    this.initialAiConfig,
  });

  @override
  State<ClipSnapProEditor> createState() => _ClipSnapProEditorState();
}

class _ClipSnapProEditorState extends State<ClipSnapProEditor>
    with TickerProviderStateMixin {
  static const String _settingsCompactControlsKey = 'settings.compact_controls';

  final GlobalKey _canvasKey = GlobalKey();
  final List<_EditorSnapshot> _undoStack = <_EditorSnapshot>[];
  final List<_EditorSnapshot> _redoStack = <_EditorSnapshot>[];

  String _activeTool = 'AI';
  String _activeAdjustSubTool = 'Brightness';
  bool _isExporting = false;
  bool _showOriginalPreview = false;
  bool _compactControls = false;
  bool _aiCutoutEnabled = false;
  bool _objectEraserMode = false;
  bool _templateLibraryOpen = true;
  double _exportPixelRatio = 3.0;
  double _eraserBrushSize = 34;
  bool _isAiProcessing = false;
  bool _ramboPointsCharged = false;
  late final AnimationController _generationProgressController;
  String _selectedUpscalePreset = '2x';
  String _selectedSkyPreset = 'Sunny';
  String _selectedMaskTarget = 'Subject';
  bool _depthMapping = true;
  bool _volumetricLighting = false;
  bool _edgeRefining = true;

  Uint8List? _aiRenderedImageBytes;
  Uint8List? _lastSubjectMaskBytes;

  final AIImageCloudService _cloudAiService = AIImageCloudService();
  final AIGenerativeTemplateService _generativeTemplateService =
      AIGenerativeTemplateService();
  final AILocalSegmentationService _localSegmentationService =
      AILocalSegmentationService();

  bool get _isRamboGenerativeTemplate =>
      widget.initialAiConfig?['templateId'] == 'rambo_action' ||
      widget.initialAiConfig?['template'] == 'rambo_action';

  double _brightness = 0.0;
  double _contrast = 1.0;
  double _saturation = 1.0;
  double _temperature = 0.0;
  double _highlights = 0.0;
  double _shadows = 0.0;
  double _clarity = 0.0;
  double _sharpen = 0.0;
  double _vignette = 0.0;

  int _rotationQuarterTurns = 0;
  bool _flipHorizontal = false;
  double _selectedAspectRatio = 0.0;
  String _selectedFrame = 'None';

  Color _filterColor = Colors.transparent;
  double _filterOpacity = 0.0;

  final List<Map<String, dynamic>> _textLayers = [];
  final List<_ErasePatch> _erasePatches = <_ErasePatch>[];

  final List<Map<String, dynamic>> _tools = [
    {'id': 'AI', 'label': 'AI Tools', 'icon': Icons.smart_toy_outlined},
    {'id': 'Adjust', 'label': 'Adjust', 'icon': Icons.tune},
    {'id': 'Filters', 'label': 'Filters', 'icon': Icons.auto_awesome},
    {'id': 'Crop', 'label': 'Crop/Rotate', 'icon': Icons.crop},
    {'id': 'Text', 'label': 'Text', 'icon': Icons.text_fields},
    {'id': 'Vignette', 'label': 'Vignette', 'icon': Icons.vignette},
    {'id': 'Warmth', 'label': 'Warmth', 'icon': Icons.wb_sunny},
    {'id': 'Ratio', 'label': 'Canvas Ratio', 'icon': Icons.aspect_ratio},
    {'id': 'Presets', 'label': 'Presets', 'icon': Icons.auto_fix_high},
    {'id': 'Stickers', 'label': 'Stickers', 'icon': Icons.emoji_emotions},
    {'id': 'Frames', 'label': 'Frames', 'icon': Icons.photo_size_select_large},
    {'id': 'Effects', 'label': 'Effects', 'icon': Icons.blur_on},
    {'id': 'Reset', 'label': 'Reset All', 'icon': Icons.restore},
  ];

  late final AnimationController _entryController;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: MotionSpec.entryDuration,
    )..forward();
    _generationProgressController = AnimationController(
      vsync: this,
      duration: const Duration(minutes: 4),
    );
    _ramboPointsCharged =
        widget.initialAiConfig?['pointsCharged'] as bool? ?? false;
    _applyInitialAiFocus();
    _loadEditorPreferences();
  }

  void _applyInitialAiFocus() {
    final aiTool = widget.initialAiTool;
    final aiConfig = widget.initialAiConfig;
    if (aiTool == null || aiTool.isEmpty) {
      return;
    }

    _activeTool = 'AI';

    final preset = aiConfig?['preset'] as String?;
    final strength = (aiConfig?['refinementStrength'] as num?)?.toDouble();

    switch (aiTool) {
      case 'smart_cutout':
        _selectedMaskTarget = _mapMaskTarget(preset);
        _edgeRefining =
            aiConfig?['preserveHairEdges'] as bool? ?? _edgeRefining;
        final edgeFeather = (aiConfig?['edgeFeather'] as num?)?.toDouble();
        final spillSuppression =
            (aiConfig?['spillSuppression'] as num?)?.toDouble();
        if (edgeFeather != null) {
          _eraserBrushSize = 20 + (edgeFeather * 60);
        }
        if (spillSuppression != null) {
          _shadows = (spillSuppression * 2 - 1).clamp(-1.0, 1.0);
        }
        if (strength != null) {
          _clarity = strength.clamp(0.0, 1.0);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _applyAiCutout();
          }
        });
        break;
      case 'ai_upscale':
        _selectedUpscalePreset = _mapUpscalePreset(aiConfig);
        _volumetricLighting = aiConfig?['denoisePass'] as bool? ?? false;
        if (strength != null) {
          _clarity = strength.clamp(0.0, 1.0);
        }
        break;
      case 'sky_replace':
        _selectedSkyPreset = _mapSkyPreset(aiConfig?['skyPack'] as String?);
        _depthMapping = aiConfig?['horizonBlend'] as bool? ?? _depthMapping;
        final relight = (aiConfig?['relightIntensity'] as num?)?.toDouble();
        if (relight != null) {
          _temperature = ((relight * 2) - 1).clamp(-1.0, 1.0);
        }
        if (strength != null) {
          _clarity = strength.clamp(0.0, 1.0);
        }
        break;
      case 'generative_template':
        if (_isRamboGenerativeTemplate) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _runRamboGenerativeEdit();
            }
          });
        }
        break;
      default:
        break;
    }
  }

  String _mapMaskTarget(String? preset) {
    switch (preset) {
      case 'Product Focus':
        return 'Background';
      case 'Clean BG':
        return 'Add Depth Mask';
      default:
        return 'Subject';
    }
  }

  String _mapSkyPreset(String? skyPack) {
    switch (skyPack) {
      case 'Golden Hour':
        return 'Sunset';
      case 'Dramatic Clouds':
        return 'Starry';
      case 'Night Glow':
        return 'Starry';
      default:
        return 'Sunny';
    }
  }

  String _mapUpscalePreset(Map<String, Object?>? aiConfig) {
    final output = aiConfig?['outputSize'] as String?;
    switch (output) {
      case '2K':
        return '2x';
      case '4K':
        return '4x';
      case '8K Preview':
        return '8x';
      default:
        return '8x';
    }
  }

  @override
  void dispose() {
    _entryController.dispose();
    _generationProgressController.dispose();
    _generativeTemplateService.dispose();
    super.dispose();
  }

  Future<void> _loadEditorPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final compact = prefs.getBool(_settingsCompactControlsKey);
    if (!mounted || compact == null) {
      return;
    }
    setState(() => _compactControls = compact);
  }

  Future<void> _persistEditorPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_settingsCompactControlsKey, _compactControls);
  }

  @override
  Widget build(BuildContext context) {
    final isTallDisplay = MediaQuery.of(context).size.height >= 860;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0E),
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF10101A), Color(0xFF08080D)],
            ),
          ),
          child: Stack(
            children: [
              Column(
                children: [
                  _buildReveal(order: 0, child: _buildTopNavBar()),
                  _buildReveal(
                    order: 1,
                    child: _buildQuickActionsBar(isTallDisplay: isTallDisplay),
                  ),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                        child: _buildImageCanvas(),
                      ),
                    ),
                  ),
                  _buildPanelReveal(_buildBottomPanel()),
                ],
              ),
              if (_showPhotoworksReferenceUi)
                _buildPhotoworksReferenceOverlay(),
              if (_isExporting) _buildExportOverlay(),
              if (_isAiProcessing)
                Positioned.fill(
                  child: ColoredBox(
                    color: Color(0xB8000000),
                    child: Center(
                      child: _isRamboGenerativeTemplate
                          ? _buildRamboProgressOverlay()
                          : const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                    color: Colors.cyanAccent),
                                SizedBox(height: 16),
                                Text(
                                  'Processing image...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRamboProgressOverlay() {
    return AnimatedBuilder(
      animation: _generationProgressController,
      builder: (context, child) {
        final progress = (_generationProgressController.value * 0.92)
            .clamp(0.0, 0.92)
            .toDouble();
        final percentage = (progress * 100).round();
        final status = percentage < 12
            ? 'Preparing your photo...'
            : percentage < 28
                ? 'Preserving your face...'
                : percentage < 92
                    ? 'Generating the Rambo transformation...'
                    : 'Finishing the HD image...';
        return SizedBox(
          width: 270,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 92,
                    height: 92,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 7,
                      backgroundColor: Colors.white24,
                      color: Colors.cyanAccent,
                    ),
                  ),
                  Text(
                    '$percentage%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                status,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Local generation can take a few minutes. Keep the app open.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: Colors.white24,
                  color: Colors.cyanAccent,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReveal({required int order, required Widget child}) {
    final begin = MotionSpec.revealBeginForOrder(order);
    final animation = CurvedAnimation(
      parent: _entryController,
      curve: Interval(begin, 1.0, curve: MotionSpec.revealCurve),
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, MotionSpec.revealOffsetY),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  Widget _buildPanelReveal(Widget child) {
    final panelAnimation = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(
        MotionSpec.panelEntranceBegin,
        1.0,
        curve: MotionSpec.panelEntranceCurve,
      ),
    );

    return FadeTransition(
      opacity: panelAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, MotionSpec.panelOffsetY),
          end: Offset.zero,
        ).animate(panelAnimation),
        child: child,
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12121A).withValues(alpha: 0.92),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(22),
        ),
        border: Border.all(color: Colors.white10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: _compactControls ? 126 : 158,
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            child: AnimatedSwitcher(
              duration: MotionSpec.panelSwitchDuration,
              switchInCurve: MotionSpec.switchInCurve,
              switchOutCurve: MotionSpec.switchOutCurve,
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(0, MotionSpec.revealOffsetY),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: KeyedSubtree(
                key: ValueKey(_activeTool),
                child: _buildActiveSubToolControls(),
              ),
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          _buildScrollableToolBar(),
        ],
      ),
    );
  }

  Widget _buildExportOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.5),
        alignment: Alignment.center,
        child: Container(
          width: 260,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF171723),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF4F8CFF)),
              SizedBox(height: 14),
              Text(
                'Rendering high-resolution image...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Please keep the editor open until export completes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopNavBar() {
    final isNarrow = MediaQuery.of(context).size.width < 390;
    final actionButtonSize = isNarrow ? 36.0 : 40.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF191925).withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            IconButton(
              constraints: BoxConstraints.tightFor(
                width: actionButtonSize,
                height: actionButtonSize,
              ),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ClipSnap Studio',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                      fontSize: isNarrow ? 15 : 16,
                    ),
                  ),
                  Text(
                    'Export scale ${_exportPixelRatio.toStringAsFixed(1)}x',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              constraints: BoxConstraints.tightFor(
                width: actionButtonSize,
                height: actionButtonSize,
              ),
              padding: EdgeInsets.zero,
              tooltip: _compactControls
                  ? 'Switch to comfortable controls'
                  : 'Switch to compact controls',
              icon: Icon(
                _compactControls
                    ? Icons.open_in_full_rounded
                    : Icons.view_compact_alt_outlined,
                color: Colors.white,
                size: isNarrow ? 20 : 22,
              ),
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() => _compactControls = !_compactControls);
                _persistEditorPreferences();
              },
            ),
            IconButton(
              constraints: BoxConstraints.tightFor(
                width: actionButtonSize,
                height: actionButtonSize,
              ),
              padding: EdgeInsets.zero,
              tooltip: 'Export resolution settings',
              icon: Icon(
                Icons.hd_outlined,
                color: Colors.white,
                size: isNarrow ? 20 : 22,
              ),
              onPressed: _isExporting ? null : _showExportOptionsSheet,
            ),
            const SizedBox(width: 4),
            SizedBox(
              height: actionButtonSize,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(isNarrow ? 84 : 96, actionButtonSize),
                  padding: EdgeInsets.symmetric(horizontal: isNarrow ? 10 : 14),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: const Color(0xFF2563EB),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: _isExporting ? null : _exportHighResImage,
                child: Text(
                  _isExporting ? 'Rendering' : 'Export',
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: isNarrow ? 13 : 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsBar({required bool isTallDisplay}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, isTallDisplay ? 12 : 4, 16, 4),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: _undoStack.isEmpty ? null : _undo,
            style: OutlinedButton.styleFrom(
              minimumSize: Size(84, _compactControls ? 38 : 44),
              padding: EdgeInsets.symmetric(
                horizontal: _compactControls ? 10 : 12,
                vertical: _compactControls ? 8 : 10,
              ),
              side: const BorderSide(color: Colors.white24),
            ),
            icon: const Icon(Icons.undo, size: 16),
            label: const Text('Undo'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _redoStack.isEmpty ? null : _redo,
            style: OutlinedButton.styleFrom(
              minimumSize: Size(84, _compactControls ? 38 : 44),
              padding: EdgeInsets.symmetric(
                horizontal: _compactControls ? 10 : 12,
                vertical: _compactControls ? 8 : 10,
              ),
              side: const BorderSide(color: Colors.white24),
            ),
            icon: const Icon(Icons.redo, size: 16),
            label: const Text('Redo'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onLongPressStart: (_) =>
                  setState(() => _showOriginalPreview = true),
              onLongPressEnd: (_) =>
                  setState(() => _showOriginalPreview = false),
              child: OutlinedButton.icon(
                onPressed: () => setState(
                  () => _showOriginalPreview = !_showOriginalPreview,
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(112, _compactControls ? 38 : 44),
                  padding: EdgeInsets.symmetric(
                    horizontal: _compactControls ? 10 : 12,
                    vertical: _compactControls ? 8 : 10,
                  ),
                  side: BorderSide(
                    color: _showOriginalPreview
                        ? const Color(0xFF4F8CFF)
                        : Colors.white24,
                  ),
                ),
                icon: Icon(
                  _showOriginalPreview
                      ? Icons.visibility
                      : Icons.compare_outlined,
                  size: 16,
                ),
                label: Text(_showOriginalPreview ? 'Original' : 'Compare'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showExportOptionsSheet() async {
    final selected = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: const Color(0xFF171723),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        var localRatio = _exportPixelRatio;
        final presets = <double>[1.5, 2.0, 3.0, 4.0];

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Export Quality',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Higher scale produces sharper output, but can be slower on some phones.',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: presets.map((ratio) {
                        final selected = localRatio == ratio;
                        return ChoiceChip(
                          selected: selected,
                          selectedColor: const Color(0xFF2563EB),
                          backgroundColor: const Color(0xFF1F1F2C),
                          label: Text('${ratio.toStringAsFixed(1)}x'),
                          labelStyle: TextStyle(
                            color: selected ? Colors.white : Colors.white70,
                          ),
                          onSelected: (_) =>
                              setModalState(() => localRatio = ratio),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(localRatio),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                        ),
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (selected == null || !mounted) {
      return;
    }

    setState(() => _exportPixelRatio = selected);
  }

  Widget _buildImageCanvas() {
    Widget imageWidget;
    if (_aiRenderedImageBytes != null) {
      imageWidget = Image.memory(_aiRenderedImageBytes!, fit: BoxFit.contain);
    } else if (widget.imageFile != null) {
      imageWidget = Image.file(widget.imageFile!, fit: BoxFit.contain);
    } else {
      imageWidget =
          Image.network('https://picsum.photos/800/1200', fit: BoxFit.contain);
    }

    if (_selectedAspectRatio > 0) {
      imageWidget = AspectRatio(
        aspectRatio: _selectedAspectRatio,
        child: ClipRect(child: imageWidget),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF161622),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: RepaintBoundary(
        key: _canvasKey,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_showOriginalPreview)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: imageWidget,
              )
            else
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(
                    _flipHorizontal ? -1.0 : 1.0, 1.0, 1.0)
                  ..rotateZ(_rotationQuarterTurns * (math.pi / 2)),
                child: ColorFiltered(
                  colorFilter: ColorFilter.matrix(_buildComprehensiveMatrix()),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: imageWidget,
                      ),
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color:
                                _filterColor.withValues(alpha: _filterOpacity),
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      if (_vignette > 0)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: RadialGradient(
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(
                                    alpha: _vignette.clamp(0.0, 0.9),
                                  ),
                                ],
                                stops: const [0.5, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ..._textLayers.map(_buildDraggableText),
                    ],
                  ),
                ),
              ),
            if (_selectedFrame != 'None')
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _frameColorFor(_selectedFrame),
                        width: _frameWidthFor(_selectedFrame),
                      ),
                    ),
                  ),
                ),
              ),
            if (_aiCutoutEnabled && !_showOriginalPreview)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.1),
                        radius: 1.0,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.28),
                        ],
                        stops: const [0.48, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            ..._erasePatches.map(
              (patch) => Positioned(
                left: patch.offset.dx - patch.radius,
                top: patch.offset.dy - patch.radius,
                child: IgnorePointer(
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                      child: Container(
                        width: patch.radius * 2,
                        height: patch.radius * 2,
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF171723).withValues(alpha: 0.30),
                          border: Border.all(
                            color: Colors.white12,
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_objectEraserMode)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: (details) {
                    _addErasePatch(details.localPosition);
                  },
                ),
              ),
            if (_showOriginalPreview)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'ORIGINAL',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportHighResImage() async {
    if (_isExporting) {
      return;
    }

    setState(() => _isExporting = true);
    ExportStatusService.instance.start('Exporting high-res image');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Rendering high-res output...')),
    );

    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) {
        return;
      }

      final boundary = _canvasKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Canvas render target not available.');
      }

      final exportResult = await _capturePngWithFallback(boundary);
      final bytes = exportResult.bytes;
      final usedRatio = exportResult.pixelRatio;
      final exportDir = await getApplicationDocumentsDirectory();
      final exportPath =
          '${exportDir.path}/ClipSnap_Image_${DateTime.now().millisecondsSinceEpoch}.png';
      final outputFile = File(exportPath);
      await outputFile.writeAsBytes(bytes, flush: true);
      ExportStatusService.instance.finish(success: true);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Image exported (${usedRatio.toStringAsFixed(1)}x): ${outputFile.path}',
          ),
          action: SnackBarAction(
            label: 'SHARE',
            onPressed: () {
              Share.shareXFiles(
                [XFile(outputFile.path)],
                text: 'ClipSnap export',
              );
            },
          ),
        ),
      );
    } catch (error) {
      ExportStatusService.instance.finish(success: false);
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<({Uint8List bytes, double pixelRatio})> _capturePngWithFallback(
    RenderRepaintBoundary boundary,
  ) async {
    final ratiosToTry = <double>[
      _exportPixelRatio,
      if (_exportPixelRatio > 2.0) 2.0,
      1.5,
      1.0,
    ];

    Object? lastError;
    for (final ratio in ratiosToTry.toSet()) {
      try {
        final image = await boundary.toImage(pixelRatio: ratio);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (byteData == null) {
          continue;
        }
        return (bytes: byteData.buffer.asUint8List(), pixelRatio: ratio);
      } catch (error) {
        lastError = error;
      }
    }

    throw Exception(lastError ?? 'Failed to render output image.');
  }

  bool get _showPhotoworksReferenceUi {
    final width = MediaQuery.of(context).size.width;
    return _activeTool == 'AI' && width >= 900;
  }

  Widget _buildPhotoworksReferenceOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 78, 18, 84),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: _buildTemplateLibraryCard(),
              ),
              Align(
                alignment: const Alignment(0.72, 0.12),
                child: _buildGenerativeEnhancementCard(),
              ),
              Align(
                alignment: const Alignment(-0.5, 0.54),
                child: _buildMaskingCard(),
              ),
              Align(
                alignment: const Alignment(-0.5, 0.88),
                child: _buildBrushToolbarCard(),
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8DBDFF),
                      foregroundColor: const Color(0xFF0A1931),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _isAiProcessing ? null : _runCloudUpscale,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text(
                      'AI Enhance\nGenerate',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTemplateLibraryCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: _templateLibraryOpen ? 280 : 54,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xE8212530),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: _templateLibraryOpen
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Template Library',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () =>
                          setState(() => _templateLibraryOpen = false),
                      icon: const Icon(Icons.close, color: Colors.white60),
                    ),
                  ],
                ),
                Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A3040),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const TextField(
                    enabled: false,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Search',
                      hintStyle: TextStyle(color: Colors.white54),
                      prefixIcon: Icon(Icons.search, color: Colors.white54),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _templateTile(
                  title: 'AI Restoration',
                  subtitle: 'Restore old & damaged photos',
                  action: 'Restored',
                ),
                const SizedBox(height: 10),
                _templateTile(
                  title: 'Generative Landscapes',
                  subtitle: 'Transform environments',
                  action: 'Generate',
                ),
                const SizedBox(height: 10),
                ...clipSnapTemplates.map(
                  (template) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _videoTemplateTile(template),
                  ),
                ),
              ],
            )
          : IconButton(
              onPressed: () => setState(() => _templateLibraryOpen = true),
              icon: const Icon(Icons.menu_open, color: Colors.white70),
            ),
    );
  }

  Widget _templateTile({
    required String title,
    required String subtitle,
    required String action,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF262B37),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 92,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF475569), Color(0xFF1E293B)],
              ),
            ),
            child: const Center(
              child:
                  Icon(Icons.image_outlined, color: Colors.white70, size: 28),
            ),
          ),
          const SizedBox(height: 8),
          Text(title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              )),
          Text(subtitle,
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                _applyAutoEnhance();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$title template applied')),
                );
              },
              icon: const Icon(Icons.auto_awesome, size: 14),
              label: Text(action),
            ),
          ),
        ],
      ),
    );
  }

  Widget _videoTemplateTile(VideoTemplate template) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF262B37),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 92,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(8)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFEC4899), Color(0xFF172554)],
              ),
            ),
            child: Center(
              child: Icon(
                template.isPremium
                    ? Icons.lock_outline_rounded
                    : Icons.auto_awesome,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            template.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            template.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _selectVideoTemplate(template),
              icon: Icon(
                template.isPremium
                    ? Icons.ondemand_video_rounded
                    : Icons.play_arrow_rounded,
                size: 14,
              ),
              label: Text(template.isPremium ? 'Watch to unlock' : 'Use'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectVideoTemplate(VideoTemplate template) async {
    final unlocked = await MonetizationService.instance
        .unlockTemplateForSession(context, template: template);
    if (!mounted || !unlocked) {
      return;
    }

    debugPrint('Applied template recipe: ${template.resolvedActionPayload}');
    _applyAutoEnhance();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${template.name} template applied: ${template.resolvedActionPayload}',
        ),
      ),
    );
  }

  Widget _buildGenerativeEnhancementCard() {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xE81F2430),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AI-Powered Generative Image\nEnhancement',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          const Text('AI Upscaling & Detail Recovery',
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: ['2x', '4x', '8x', 'Ultra'].map((preset) {
              final selected = _selectedUpscalePreset == preset;
              return ChoiceChip(
                label: Text(preset),
                selected: selected,
                selectedColor: const Color(0xFF4D78C7),
                backgroundColor: const Color(0xFF2A3040),
                labelStyle:
                    TextStyle(color: selected ? Colors.white : Colors.white70),
                onSelected: (_) =>
                    setState(() => _selectedUpscalePreset = preset),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          const Text('Sky Sky Replacement',
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: ['Sunny', 'Sunset', 'Starry'].map((preset) {
              final selected = _selectedSkyPreset == preset;
              return ChoiceChip(
                label: Text(preset),
                selected: selected,
                selectedColor: const Color(0xFF4D78C7),
                backgroundColor: const Color(0xFF2A3040),
                labelStyle:
                    TextStyle(color: selected ? Colors.white : Colors.white70),
                onSelected: (_) => setState(() => _selectedSkyPreset = preset),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          const Text('Subject Refinement',
              style: TextStyle(color: Colors.white70)),
          Slider(
            value: _clarity.clamp(0.0, 1.0),
            min: 0,
            max: 1,
            activeColor: const Color(0xFF6EA4FF),
            onChanged: (value) => setState(() => _clarity = value),
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Text('Texture',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              Text('Lighting',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              Text('Color',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMaskingCard() {
    return Container(
      width: 370,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xE81F2430),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AI-Powered Subject Masking &\nDepth',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _maskTargetChip('Subject'),
              const SizedBox(width: 8),
              _maskTargetChip('Background'),
              const SizedBox(width: 8),
              _maskTargetChip('Add Depth Mask'),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Depth Mapping',
                style: TextStyle(color: Colors.white)),
            value: _depthMapping,
            onChanged: (v) => setState(() => _depthMapping = v),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Volumetric Lighting',
                style: TextStyle(color: Colors.white)),
            value: _volumetricLighting,
            onChanged: (v) => setState(() => _volumetricLighting = v),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Edge Refining',
                style: TextStyle(color: Colors.white)),
            value: _edgeRefining,
            onChanged: (v) => setState(() => _edgeRefining = v),
          ),
        ],
      ),
    );
  }

  Widget _maskTargetChip(String label) {
    final selected = _selectedMaskTarget == label;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: const Color(0xFF355EA1),
      backgroundColor: const Color(0xFF2A3040),
      labelStyle: TextStyle(color: selected ? Colors.white : Colors.white70),
      onSelected: (_) {
        setState(() => _selectedMaskTarget = label);
        _applyAiCutout();
      },
    );
  }

  Widget _buildBrushToolbarCard() {
    return Container(
      width: 370,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xE81F2430),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.brush, color: Color(0xFF78AFFF)),
              SizedBox(width: 8),
              Text('Selection Brush', style: TextStyle(color: Colors.white)),
              Spacer(),
              Icon(Icons.healing, color: Colors.white70),
              SizedBox(width: 12),
              Icon(Icons.copy, color: Colors.white70),
            ],
          ),
          const SizedBox(height: 10),
          Text('Size ${_eraserBrushSize.toStringAsFixed(0)}',
              style: const TextStyle(color: Colors.white70)),
          Slider(
            value: _eraserBrushSize,
            min: 12,
            max: 80,
            activeColor: const Color(0xFF6EA4FF),
            onChanged: (value) => setState(() => _eraserBrushSize = value),
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Hardness', style: TextStyle(color: Colors.white60)),
              Text('Opacity', style: TextStyle(color: Colors.white60)),
              Text('Flow', style: TextStyle(color: Colors.white60)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSubToolControls() {
    switch (_activeTool) {
      case 'Adjust':
        return Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildSubToolChip('Brightness'),
                  const SizedBox(width: 8),
                  _buildSubToolChip('Contrast'),
                  const SizedBox(width: 8),
                  _buildSubToolChip('Saturation'),
                  const SizedBox(width: 8),
                  _buildSubToolChip('Highlights'),
                  const SizedBox(width: 8),
                  _buildSubToolChip('Shadows'),
                  const SizedBox(width: 8),
                  _buildSubToolChip('Clarity'),
                  const SizedBox(width: 8),
                  _buildSubToolChip('Sharpen'),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$_activeAdjustSubTool: ${_formatAdjustValue(_activeAdjustSubTool)}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4.5,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 10),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 18),
                ),
                child: Slider(
                  value: _getAdjustValue(),
                  min: _getAdjustMin(),
                  max: _getAdjustMax(),
                  divisions: 100,
                  label: _formatAdjustValue(_activeAdjustSubTool),
                  activeColor: const Color(0xFF2563EB),
                  onChangeStart: (_) => _pushUndoSnapshot(),
                  onChanged: (val) => setState(() => _setAdjustValue(val)),
                ),
              ),
            ),
          ],
        );
      case 'Filters':
        return ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _buildFilterTile('Original', Colors.transparent, 0.0),
            _buildFilterTile('Warm Vintage', Colors.amber, 0.25),
            _buildFilterTile('Cyberpunk', Colors.cyan, 0.3),
            _buildFilterTile('Cinematic', Colors.deepOrange, 0.2),
            _buildFilterTile('Moody Blue', Colors.indigo, 0.35),
            _buildFilterTile('BW Film', Colors.grey, 0.5),
          ],
        );
      case 'Crop':
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.rotate_right),
              label: const Text('Rotate 90deg'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(150, 44),
                backgroundColor: const Color(0xFF1E1E2A),
              ),
              onPressed: () {
                _pushUndoSnapshot();
                setState(
                  () => _rotationQuarterTurns = (_rotationQuarterTurns + 1) % 4,
                );
              },
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.flip),
              label: const Text('Flip Horiz'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(150, 44),
                backgroundColor: const Color(0xFF1E1E2A),
              ),
              onPressed: () {
                _pushUndoSnapshot();
                setState(() => _flipHorizontal = !_flipHorizontal);
              },
            ),
          ],
        );
      case 'Text':
        return Row(
          children: [
            Expanded(
              child: TextField(
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Type overlay text...',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                ),
                onSubmitted: (val) {
                  if (val.isNotEmpty) {
                    _pushUndoSnapshot();
                    setState(
                      () => _textLayers
                          .add({'text': val, 'offset': const Offset(80, 100)}),
                    );
                  }
                },
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(94, 44),
                backgroundColor: const Color(0xFF2563EB),
              ),
              onPressed: _showAddTextDialog,
              child: const Text('Add Text'),
            ),
          ],
        );
      case 'Vignette':
        return Column(
          children: [
            Text(
              'Vignette Intensity: ${(_vignette * 100).toInt()}%',
              style: const TextStyle(color: Colors.white70),
            ),
            Slider(
              value: _vignette,
              min: 0.0,
              max: 1.0,
              divisions: 100,
              activeColor: const Color(0xFF2563EB),
              onChangeStart: (_) => _pushUndoSnapshot(),
              onChanged: (val) => setState(() => _vignette = val),
            ),
          ],
        );
      case 'Warmth':
        return Column(
          children: [
            const Text(
              'Temperature Offset',
              style: TextStyle(color: Colors.white70),
            ),
            Slider(
              value: _temperature,
              min: -0.5,
              max: 0.5,
              divisions: 100,
              activeColor: const Color(0xFF2563EB),
              onChangeStart: (_) => _pushUndoSnapshot(),
              onChanged: (val) => setState(() => _temperature = val),
            ),
          ],
        );
      case 'Ratio':
        return ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _buildRatioChip('Free', 0.0),
            _buildRatioChip('1:1 (Insta)', 1.0),
            _buildRatioChip('4:5 (Portrait)', 0.8),
            _buildRatioChip('9:16 (Story/TikTok)', 0.5625),
            _buildRatioChip('16:9 (Youtube)', 1.777),
          ],
        );
      case 'Presets':
        return ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _buildPresetButton('Auto Enhance', _applyAutoEnhance),
            _buildPresetButton('Portrait Pop', () {
              _pushUndoSnapshot();
              setState(() {
                _brightness = 0.06;
                _contrast = 1.12;
                _saturation = 1.1;
                _clarity = 0.18;
                _sharpen = 0.22;
                _temperature = 0.04;
              });
            }),
            _buildPresetButton('Moody', () {
              _pushUndoSnapshot();
              setState(() {
                _brightness = -0.08;
                _contrast = 1.2;
                _saturation = 0.9;
                _highlights = -0.2;
                _shadows = 0.14;
                _vignette = 0.2;
              });
            }),
          ],
        );
      case 'Stickers':
        final stickers = ['🔥', '✨', '🎬', '😎', '💯', '❤️'];
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: stickers.map((sticker) {
            return ActionChip(
              label: Text(sticker, style: const TextStyle(fontSize: 18)),
              backgroundColor: const Color(0xFF1E1E2A),
              side: const BorderSide(color: Colors.white12),
              onPressed: () {
                _pushUndoSnapshot();
                setState(
                  () => _textLayers.add({
                    'text': sticker,
                    'offset': const Offset(90, 120),
                  }),
                );
              },
            );
          }).toList(),
        );
      case 'Frames':
        return ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _buildFrameChip('None'),
            _buildFrameChip('Clean'),
            _buildFrameChip('Neon'),
            _buildFrameChip('Film'),
          ],
        );
      case 'AI':
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            if (_isRamboGenerativeTemplate) ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB45309),
                ),
                onPressed: _isAiProcessing ? null : _runRamboGenerativeEdit,
                icon: const Icon(Icons.auto_awesome, color: Colors.white),
                label: Text(
                  _isAiProcessing
                      ? 'Generating Rambo transformation...'
                      : 'Generate HD Rambo Look (Face Preserve)',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Face-preserving pixel generation using ${_generativeTemplateService.modelName}.',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
            ] else ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                ),
                onPressed: _isAiProcessing ? null : _applyAiCutout,
                icon: const Icon(Icons.content_cut, color: Colors.white),
                label: Text(
                  _isAiProcessing
                      ? 'Processing...'
                      : (_aiCutoutEnabled
                          ? 'Re-Apply Subject Mask (Local)'
                          : 'Subject Mask (Local ML Kit)'),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(height: 8),
            ],
            const Text(
              'Generative cloud tasks (4x/8x and sky replacement)',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['2x', '4x', '8x', 'Ultra'].map((preset) {
                return ChoiceChip(
                  label: Text(preset),
                  selected: _selectedUpscalePreset == preset,
                  selectedColor: const Color(0xFF2563EB),
                  backgroundColor: const Color(0xFF1E1E2A),
                  labelStyle: TextStyle(
                    color: _selectedUpscalePreset == preset
                        ? Colors.white
                        : Colors.white70,
                  ),
                  onSelected: _isAiProcessing
                      ? null
                      : (_) => setState(() => _selectedUpscalePreset = preset),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E1E2A),
                ),
                onPressed: _isAiProcessing ? null : _runCloudUpscale,
                icon: const Icon(Icons.hd, color: Colors.white),
                label: Text(
                  'Run $_selectedUpscalePreset Cloud Upscale',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['Sunny', 'Sunset', 'Starry'].map((preset) {
                return ChoiceChip(
                  label: Text(preset),
                  selected: _selectedSkyPreset == preset,
                  selectedColor: const Color(0xFF2563EB),
                  backgroundColor: const Color(0xFF1E1E2A),
                  labelStyle: TextStyle(
                    color: _selectedSkyPreset == preset
                        ? Colors.white
                        : Colors.white70,
                  ),
                  onSelected: _isAiProcessing
                      ? null
                      : (_) => setState(() => _selectedSkyPreset = preset),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E1E2A),
                ),
                onPressed: _isAiProcessing ? null : _runSkyReplacement,
                icon: const Icon(Icons.wb_sunny_outlined, color: Colors.white),
                label: Text(
                  'Apply $_selectedSkyPreset Sky (Cloud)',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
            if (!_cloudAiService.isConfigured)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Set AI_IMAGE_API_KEY, AI_IMAGE_UPSCALE_ENDPOINT, and AI_IMAGE_SKY_ENDPOINT via --dart-define to enable cloud generation.',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              dense: true,
              visualDensity: const VisualDensity(vertical: -3),
              contentPadding: EdgeInsets.zero,
              activeThumbColor: const Color(0xFF2563EB),
              title: const Text(
                'Object Eraser Mode',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
              subtitle: Text(
                _objectEraserMode
                    ? 'Tap image to add erase patches.'
                    : 'Enable to tap objects and hide them.',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              value: _objectEraserMode,
              onChanged: (value) {
                HapticFeedback.selectionClick();
                setState(() => _objectEraserMode = value);
              },
            ),
            if (_objectEraserMode) ...[
              const SizedBox(height: 4),
              Text(
                'Brush Size: ${_eraserBrushSize.round()} px',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 9),
                ),
                child: Slider(
                  value: _eraserBrushSize,
                  min: 16,
                  max: 72,
                  divisions: 14,
                  activeColor: const Color(0xFF2563EB),
                  onChanged: (value) =>
                      setState(() => _eraserBrushSize = value),
                ),
              ),
            ],
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E1E2A),
                    ),
                    onPressed: _erasePatches.isEmpty
                        ? null
                        : () {
                            _pushUndoSnapshot();
                            setState(() => _erasePatches.clear());
                          },
                    icon: const Icon(Icons.layers_clear, color: Colors.white),
                    label: const Text(
                      'Clear Patches',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E1E2A),
                    ),
                    onPressed: _objectEraserMode
                        ? () => setState(() => _objectEraserMode = false)
                        : null,
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: const Text(
                      'Done',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      case 'Effects':
        return const Center(
          child: Text(
            'Glitch, grain, and light leak effects coming next.',
            style: TextStyle(color: Colors.white54),
          ),
        );
      case 'Reset':
        return Center(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.restart_alt, color: Colors.white),
            label: const Text(
              'Reset All Edits',
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: _resetAll,
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildScrollableToolBar() {
    return SizedBox(
      height: _compactControls ? 78 : 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: _compactControls ? 7 : 10,
        ),
        itemCount: _tools.length,
        itemBuilder: (context, index) {
          final tool = _tools[index];
          final isSelected = _activeTool == tool['id'];

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _activeTool = tool['id'] as String);
            },
            child: AnimatedScale(
              duration: MotionSpec.selectionDuration,
              curve: MotionSpec.emphasisCurve,
              scale: isSelected ? 1.04 : 1.0,
              child: AnimatedContainer(
                duration: MotionSpec.selectionDuration,
                width: _compactControls ? 86 : 96,
                margin: const EdgeInsets.only(right: 8),
                padding: EdgeInsets.symmetric(
                  vertical: _compactControls ? 8 : 10,
                  horizontal: 6,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF213D7A).withValues(alpha: 0.42)
                      : const Color(0xFF171723),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        isSelected ? const Color(0xFF4F8CFF) : Colors.white10,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      tool['icon'] as IconData,
                      color:
                          isSelected ? const Color(0xFF66A0FF) : Colors.white60,
                      size: _compactControls ? 20 : 22,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tool['label'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isSelected
                            ? const Color(0xFFCEE2FF)
                            : Colors.white60,
                        fontSize: _compactControls ? 10 : 11,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<double> _buildComprehensiveMatrix() {
    final b = _brightness * 255;
    final c = _contrast * (1 + (_clarity * 0.25) + (_sharpen * 0.2));
    final s = _saturation * (1 + (_clarity * 0.15));
    final t = _temperature * 50;
    final shadowOffset = _shadows * 45;
    final highlightOffset = _highlights * 25;

    return [
      (c * s) + (t > 0 ? t / 100 : 0),
      0,
      0,
      0,
      b + t + shadowOffset + highlightOffset,
      0,
      c * s,
      0,
      0,
      b + shadowOffset,
      0,
      0,
      (c * s) - (t < 0 ? t / 100 : 0),
      0,
      b - t + shadowOffset - highlightOffset,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  Widget _buildSubToolChip(String label) {
    final isSelected = _activeAdjustSubTool == label;
    return ChoiceChip(
      materialTapTargetSize: MaterialTapTargetSize.padded,
      padding: EdgeInsets.symmetric(
        horizontal: _compactControls ? 8 : 10,
        vertical: _compactControls ? 7 : 8,
      ),
      label: Text(
        label,
        style: TextStyle(fontSize: _compactControls ? 11 : 12),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFF2563EB),
      backgroundColor: const Color(0xFF1E1E2A),
      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white60),
      onSelected: (_) {
        HapticFeedback.selectionClick();
        setState(() => _activeAdjustSubTool = label);
      },
    );
  }

  Widget _buildFilterTile(String name, Color color, double opacity) {
    final isSelected = _filterColor == color;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _pushUndoSnapshot();
        setState(() {
          _filterColor = color;
          _filterOpacity = opacity;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF1E1E2A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            name,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ),
    );
  }

  Widget _buildRatioChip(String label, double ratio) {
    final isSelected = _selectedAspectRatio == ratio;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        materialTapTargetSize: MaterialTapTargetSize.padded,
        padding: EdgeInsets.symmetric(
          horizontal: _compactControls ? 8 : 10,
          vertical: _compactControls ? 7 : 8,
        ),
        label: Text(label),
        selected: isSelected,
        selectedColor: const Color(0xFF2563EB),
        backgroundColor: const Color(0xFF1E1E2A),
        labelStyle:
            TextStyle(color: isSelected ? Colors.white : Colors.white70),
        onSelected: (_) {
          HapticFeedback.selectionClick();
          _pushUndoSnapshot();
          setState(() => _selectedAspectRatio = ratio);
        },
      ),
    );
  }

  Widget _buildDraggableText(Map<String, dynamic> layer) {
    final offset = layer['offset'] as Offset;
    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: GestureDetector(
        onPanStart: (_) => _pushUndoSnapshot(),
        onPanUpdate: (details) {
          setState(() {
            layer['offset'] = offset + details.delta;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            layer['text'] as String,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  double _getAdjustValue() {
    if (_activeAdjustSubTool == 'Brightness') {
      return _brightness;
    }
    if (_activeAdjustSubTool == 'Contrast') {
      return _contrast;
    }
    if (_activeAdjustSubTool == 'Saturation') {
      return _saturation;
    }
    if (_activeAdjustSubTool == 'Highlights') {
      return _highlights;
    }
    if (_activeAdjustSubTool == 'Shadows') {
      return _shadows;
    }
    if (_activeAdjustSubTool == 'Clarity') {
      return _clarity;
    }
    return _sharpen;
  }

  double _getAdjustMin() {
    if (_activeAdjustSubTool == 'Brightness' ||
        _activeAdjustSubTool == 'Highlights' ||
        _activeAdjustSubTool == 'Shadows') {
      return -0.5;
    }
    if (_activeAdjustSubTool == 'Contrast' ||
        _activeAdjustSubTool == 'Saturation') {
      return 0.5;
    }
    return 0.0;
  }

  double _getAdjustMax() {
    if (_activeAdjustSubTool == 'Brightness' ||
        _activeAdjustSubTool == 'Highlights' ||
        _activeAdjustSubTool == 'Shadows') {
      return 0.5;
    }
    if (_activeAdjustSubTool == 'Contrast' ||
        _activeAdjustSubTool == 'Saturation') {
      return 1.5;
    }
    return 1.0;
  }

  void _setAdjustValue(double val) {
    if (_activeAdjustSubTool == 'Brightness') {
      _brightness = val;
    }
    if (_activeAdjustSubTool == 'Contrast') {
      _contrast = val;
    }
    if (_activeAdjustSubTool == 'Saturation') {
      _saturation = val;
    }
    if (_activeAdjustSubTool == 'Highlights') {
      _highlights = val;
    }
    if (_activeAdjustSubTool == 'Shadows') {
      _shadows = val;
    }
    if (_activeAdjustSubTool == 'Clarity') {
      _clarity = val;
    }
    if (_activeAdjustSubTool == 'Sharpen') {
      _sharpen = val;
    }
  }

  void _showAddTextDialog() {
    var input = '';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2A),
        title: const Text(
          'Add Text Overlay',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Enter text...'),
          onChanged: (v) => input = v,
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              if (input.isNotEmpty) {
                _pushUndoSnapshot();
                setState(() {
                  _textLayers
                      .add({'text': input, 'offset': const Offset(80, 100)});
                });
              }
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetButton(String label, VoidCallback onPressed) {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          minimumSize: Size(120, _compactControls ? 40 : 44),
          backgroundColor: const Color(0xFF1E1E2A),
        ),
        onPressed: () {
          HapticFeedback.selectionClick();
          onPressed();
        },
        child: Text(label),
      ),
    );
  }

  Widget _buildFrameChip(String label) {
    final selected = _selectedFrame == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        materialTapTargetSize: MaterialTapTargetSize.padded,
        padding: EdgeInsets.symmetric(
          horizontal: _compactControls ? 8 : 10,
          vertical: _compactControls ? 7 : 8,
        ),
        label: Text(label),
        selected: selected,
        selectedColor: const Color(0xFF2563EB),
        backgroundColor: const Color(0xFF1E1E2A),
        labelStyle: TextStyle(color: selected ? Colors.white : Colors.white70),
        onSelected: (_) {
          HapticFeedback.selectionClick();
          _pushUndoSnapshot();
          setState(() => _selectedFrame = label);
        },
      ),
    );
  }

  String _formatAdjustValue(String tool) {
    final value = _getAdjustValue();
    if (tool == 'Brightness' || tool == 'Highlights' || tool == 'Shadows') {
      return '${(value * 100).round()}';
    }
    if (tool == 'Contrast' || tool == 'Saturation') {
      return '${((value - 1) * 100).round()}';
    }
    return '${(value * 100).round()}';
  }

  void _applyAutoEnhance() {
    _pushUndoSnapshot();
    setState(() {
      _brightness = 0.08;
      _contrast = 1.12;
      _saturation = 1.08;
      _highlights = -0.08;
      _shadows = 0.12;
      _clarity = 0.18;
      _sharpen = 0.2;
      _temperature = 0.03;
    });
  }

  Future<void> _applyAiCutout() async {
    if (_isAiProcessing) {
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isAiProcessing = true);

    try {
      final sourceBytes = await _currentImageBytesForAi();
      final subjectBytes = await _localSegmentationService.segmentSubject(
        sourceBytes,
      );
      _pushUndoSnapshot();
      setState(() {
        _aiCutoutEnabled = true;
        _aiRenderedImageBytes = subjectBytes;
        _lastSubjectMaskBytes = subjectBytes;
      });

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Local AI mask applied using ML Kit segmentation.'),
        ),
      );
    } catch (_) {
      _pushUndoSnapshot();
      setState(() {
        _aiCutoutEnabled = true;
        _brightness = (_brightness + 0.03).clamp(-0.5, 0.5);
        _contrast = (_contrast * 1.06).clamp(0.5, 1.5);
        _saturation = (_saturation * 1.04).clamp(0.5, 1.5);
        _highlights = (_highlights - 0.05).clamp(-0.5, 0.5);
        _shadows = (_shadows + 0.08).clamp(-0.5, 0.5);
        _clarity = (_clarity + 0.12).clamp(0.0, 1.0);
      });

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Local segmentation unavailable. Applied visual cutout fallback.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isAiProcessing = false);
      }
    }
  }

  Future<void> _runCloudUpscale() async {
    if (_isAiProcessing) {
      return;
    }
    if (!_cloudAiService.isConfigured) {
      _showAiError(
        'Cloud AI is not configured. Add AI_IMAGE_API_KEY and endpoint dart-defines.',
      );
      return;
    }

    setState(() => _isAiProcessing = true);
    try {
      final sourceBytes = await _currentImageBytesForAi();
      final enhancedBytes = await _cloudAiService.upscaleImage(
        imageBytes: sourceBytes,
        multiplier: _selectedUpscalePreset,
        maskBytes: _lastSubjectMaskBytes,
      );

      _pushUndoSnapshot();
      setState(() => _aiRenderedImageBytes = enhancedBytes);

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cloud upscale complete: $_selectedUpscalePreset.'),
        ),
      );
    } catch (error) {
      _showAiError('Cloud upscale failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isAiProcessing = false);
      }
    }
  }

  Future<void> _runRamboGenerativeEdit() async {
    if (_isAiProcessing) {
      return;
    }

    final sourceFile = widget.imageFile;
    if (sourceFile == null) {
      _showAiError('Select a source photo before generating the template.');
      return;
    }

    final backendAvailable = await ApiService.checkHealth();
    if (!backendAvailable) {
      _showAiError(
        'Render backend is offline. Check https://trimly-backened-1.onrender.com and try again.',
      );
      return;
    }

    _generationProgressController.forward(from: 0);
    setState(() => _isAiProcessing = true);
    try {
      final sourceBytes = await sourceFile.readAsBytes();
      final faceMask =
          await _localSegmentationService.createFacePreserveMask(sourceBytes);
      final generatedBytes =
          await _generativeTemplateService.generateRamboPortrait(
        imageBytes: sourceBytes,
        maskBytes: faceMask,
        fileName: sourceFile.path.split(Platform.pathSeparator).last,
      );

      _pushUndoSnapshot();
      setState(() {
        _aiRenderedImageBytes = generatedBytes;
        _brightness = 0;
        _contrast = 1;
        _saturation = 1;
        _temperature = 0;
        _clarity = 0;
        _sharpen = 0;
      });

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('HD Rambo transformation generated with face preservation.'),
        ),
      );
    } catch (error) {
      if (_ramboPointsCharged) {
        await PointService.addPoints(PointService.ramboGenerationCost);
        _ramboPointsCharged = false;
      }
      _showAiError('Rambo generation failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isAiProcessing = false);
      }
      _generationProgressController.stop();
    }
  }

  Future<void> _runSkyReplacement() async {
    if (_isAiProcessing) {
      return;
    }
    if (!_cloudAiService.isConfigured) {
      _showAiError(
        'Cloud AI is not configured. Add AI_IMAGE_API_KEY and endpoint dart-defines.',
      );
      return;
    }

    setState(() => _isAiProcessing = true);
    try {
      final sourceBytes = await _currentImageBytesForAi();
      final replacedBytes = await _cloudAiService.replaceSky(
        imageBytes: sourceBytes,
        preset: _selectedSkyPreset.toLowerCase(),
        subjectMaskBytes: _lastSubjectMaskBytes,
      );

      _pushUndoSnapshot();
      setState(() => _aiRenderedImageBytes = replacedBytes);

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cloud sky replacement applied: $_selectedSkyPreset.'),
        ),
      );
    } catch (error) {
      _showAiError('Cloud sky replacement failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isAiProcessing = false);
      }
    }
  }

  Future<Uint8List> _currentImageBytesForAi() async {
    if (_aiRenderedImageBytes != null) {
      return _aiRenderedImageBytes!;
    }
    final sourceFile = widget.imageFile;
    if (sourceFile != null) {
      return sourceFile.readAsBytes();
    }
    throw StateError('No source image selected for AI processing.');
  }

  void _showAiError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _addErasePatch(Offset localPosition) {
    HapticFeedback.selectionClick();
    _pushUndoSnapshot();
    setState(() {
      _erasePatches.add(
        _ErasePatch(offset: localPosition, radius: _eraserBrushSize / 2),
      );
    });
  }

  Color _frameColorFor(String frame) {
    switch (frame) {
      case 'Neon':
        return const Color(0xFF4F8CFF);
      case 'Film':
        return const Color(0xFFE8D9B0);
      case 'Clean':
        return Colors.white;
      default:
        return Colors.transparent;
    }
  }

  double _frameWidthFor(String frame) {
    switch (frame) {
      case 'Film':
        return 14;
      case 'Neon':
        return 6;
      case 'Clean':
        return 4;
      default:
        return 0;
    }
  }

  _EditorSnapshot _captureSnapshot() {
    return _EditorSnapshot(
      activeTool: _activeTool,
      activeAdjustSubTool: _activeAdjustSubTool,
      aiCutoutEnabled: _aiCutoutEnabled,
      objectEraserMode: _objectEraserMode,
      eraserBrushSize: _eraserBrushSize,
      brightness: _brightness,
      contrast: _contrast,
      saturation: _saturation,
      temperature: _temperature,
      highlights: _highlights,
      shadows: _shadows,
      clarity: _clarity,
      sharpen: _sharpen,
      vignette: _vignette,
      rotationQuarterTurns: _rotationQuarterTurns,
      flipHorizontal: _flipHorizontal,
      selectedAspectRatio: _selectedAspectRatio,
      selectedFrame: _selectedFrame,
      filterColorValue: _filterColor.toARGB32(),
      filterOpacity: _filterOpacity,
      textLayers:
          _textLayers.map((layer) => Map<String, dynamic>.from(layer)).toList(),
      erasePatches: _erasePatches
          .map(
            (patch) => {
              'dx': patch.offset.dx,
              'dy': patch.offset.dy,
              'radius': patch.radius,
            },
          )
          .toList(),
    );
  }

  void _restoreSnapshot(_EditorSnapshot snapshot) {
    _activeTool = snapshot.activeTool;
    _activeAdjustSubTool = snapshot.activeAdjustSubTool;
    _aiCutoutEnabled = snapshot.aiCutoutEnabled;
    _objectEraserMode = snapshot.objectEraserMode;
    _eraserBrushSize = snapshot.eraserBrushSize;
    _brightness = snapshot.brightness;
    _contrast = snapshot.contrast;
    _saturation = snapshot.saturation;
    _temperature = snapshot.temperature;
    _highlights = snapshot.highlights;
    _shadows = snapshot.shadows;
    _clarity = snapshot.clarity;
    _sharpen = snapshot.sharpen;
    _vignette = snapshot.vignette;
    _rotationQuarterTurns = snapshot.rotationQuarterTurns;
    _flipHorizontal = snapshot.flipHorizontal;
    _selectedAspectRatio = snapshot.selectedAspectRatio;
    _selectedFrame = snapshot.selectedFrame;
    _filterColor = Color(snapshot.filterColorValue);
    _filterOpacity = snapshot.filterOpacity;
    _textLayers
      ..clear()
      ..addAll(
        snapshot.textLayers
            .map((layer) => Map<String, dynamic>.from(layer))
            .toList(),
      );
    _erasePatches
      ..clear()
      ..addAll(
        snapshot.erasePatches.map(
          (patch) => _ErasePatch(
            offset: Offset(
              (patch['dx'] as num).toDouble(),
              (patch['dy'] as num).toDouble(),
            ),
            radius: (patch['radius'] as num).toDouble(),
          ),
        ),
      );
  }

  void _pushUndoSnapshot() {
    _undoStack.add(_captureSnapshot());
    if (_undoStack.length > 80) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) {
      return;
    }
    final previous = _undoStack.removeLast();
    _redoStack.add(_captureSnapshot());
    setState(() => _restoreSnapshot(previous));
  }

  void _redo() {
    if (_redoStack.isEmpty) {
      return;
    }
    final next = _redoStack.removeLast();
    _undoStack.add(_captureSnapshot());
    setState(() => _restoreSnapshot(next));
  }

  void _resetAll() {
    _pushUndoSnapshot();
    setState(() {
      _brightness = 0.0;
      _contrast = 1.0;
      _saturation = 1.0;
      _aiCutoutEnabled = false;
      _objectEraserMode = false;
      _eraserBrushSize = 34;
      _temperature = 0.0;
      _highlights = 0.0;
      _shadows = 0.0;
      _clarity = 0.0;
      _sharpen = 0.0;
      _vignette = 0.0;
      _rotationQuarterTurns = 0;
      _flipHorizontal = false;
      _selectedAspectRatio = 0.0;
      _selectedFrame = 'None';
      _filterColor = Colors.transparent;
      _filterOpacity = 0.0;
      _aiRenderedImageBytes = null;
      _lastSubjectMaskBytes = null;
      _textLayers.clear();
      _erasePatches.clear();
    });
  }
}

class _EditorSnapshot {
  final String activeTool;
  final String activeAdjustSubTool;
  final bool aiCutoutEnabled;
  final bool objectEraserMode;
  final double eraserBrushSize;
  final double brightness;
  final double contrast;
  final double saturation;
  final double temperature;
  final double highlights;
  final double shadows;
  final double clarity;
  final double sharpen;
  final double vignette;
  final int rotationQuarterTurns;
  final bool flipHorizontal;
  final double selectedAspectRatio;
  final String selectedFrame;
  final int filterColorValue;
  final double filterOpacity;
  final List<Map<String, dynamic>> textLayers;
  final List<Map<String, dynamic>> erasePatches;

  const _EditorSnapshot({
    required this.activeTool,
    required this.activeAdjustSubTool,
    required this.aiCutoutEnabled,
    required this.objectEraserMode,
    required this.eraserBrushSize,
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.temperature,
    required this.highlights,
    required this.shadows,
    required this.clarity,
    required this.sharpen,
    required this.vignette,
    required this.rotationQuarterTurns,
    required this.flipHorizontal,
    required this.selectedAspectRatio,
    required this.selectedFrame,
    required this.filterColorValue,
    required this.filterOpacity,
    required this.textLayers,
    required this.erasePatches,
  });
}

class _ErasePatch {
  final Offset offset;
  final double radius;

  const _ErasePatch({required this.offset, required this.radius});
}
