import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:my_app/media_picker_handler.dart';
import 'package:video_player/video_player.dart';

import '../data/template_presets.dart';
import '../models/template_model.dart';
import '../services/monetization_service.dart';
import '../services/template_render_service.dart';

class ClipSnapEditorLaunchConfig {
  final String mode;
  final String aspectRatio;
  final String source;
  final String? workflow;
  final String? templateId;
  final String? initialAiTool;
  final Map<String, Object?>? initialAiConfig;
  final bool autoOpenPicker;
  final File? initialVideoFile;

  const ClipSnapEditorLaunchConfig({
    this.mode = 'Video',
    this.aspectRatio = '9:16 Reels/Shorts',
    this.source = 'Quick Dock',
    this.workflow,
    this.templateId,
    this.initialAiTool,
    this.initialAiConfig,
    this.autoOpenPicker = false,
    this.initialVideoFile,
  });
}

class ClipSnapEditorScreen extends StatefulWidget {
  final ClipSnapEditorLaunchConfig launchConfig;

  const ClipSnapEditorScreen({
    super.key,
    this.launchConfig = const ClipSnapEditorLaunchConfig(),
  });

  @override
  State<ClipSnapEditorScreen> createState() => _ClipSnapEditorScreenState();
}

class _ClipSnapEditorScreenState extends State<ClipSnapEditorScreen> {
  final SafeMediaPicker _mediaPicker = SafeMediaPicker();

  bool _isPlaying = false;

  VideoTemplate? get _activeTemplate {
    final templateId = widget.launchConfig.templateId ?? 'cyberpunk_tokyo';
    for (final template in clipSnapTemplates) {
      if (template.id == templateId) {
        return template;
      }
    }
    return null;
  }

  String? get _activeTemplateOverlayAsset => _activeTemplate?.overlayAssetPath;

  bool get _hasActiveTemplateOverlay =>
      _activeTemplateOverlayAsset != null &&
      _activeTemplateOverlayAsset!.isNotEmpty;
  bool _showGuide = false;
  int _selectedToolIndex = -1;
  late String _activeAspectPreset;
  bool _isImporting = false;
  bool _didAutoOpenPicker = false;
  String? _mediaLabel;
  Uint8List? _imageBytes;
  File? _selectedMediaFile;
  VideoPlayerController? _videoController;

  final List<String> _editorAspectPresets = const [
    '9:16 Reels/Shorts',
    '16:9 YouTube',
    '1:1 Square',
    '4:5 Feed',
  ];

  // Primary tool row items shown as a smooth horizontal ribbon.
  final List<Map<String, dynamic>> _tools = [
    {'icon': Icons.aspect_ratio, 'label': 'Canvas'},
    {'icon': Icons.music_note, 'label': 'Audio'},
    {'icon': Icons.emoji_emotions_outlined, 'label': 'Sticker'},
    {'icon': Icons.text_fields, 'label': 'Text'},
    {'icon': Icons.auto_awesome, 'label': 'Effect'},
    {'icon': Icons.color_lens_outlined, 'label': 'Filter'},
    {'icon': Icons.picture_in_picture_alt, 'label': 'PIP'},
    {'icon': Icons.timer, 'label': 'Duration'},
    {'icon': Icons.content_cut, 'label': 'Split'},
    {'icon': Icons.delete_outline, 'label': 'Delete'},
    {'icon': Icons.volume_up_outlined, 'label': 'Volume'},
    {'icon': Icons.texture, 'label': 'Background'},
    {'icon': Icons.speed, 'label': 'Speed'},
    {'icon': Icons.auto_fix_high, 'label': 'AI Cut'},
    {'icon': Icons.record_voice_over, 'label': 'Voice Enhance'},
    {'icon': Icons.crop, 'label': 'Crop'},
    {'icon': Icons.sync_alt, 'label': 'Switch'},
    {'icon': Icons.hd, 'label': 'Enhance'},
    {'icon': Icons.grid_view, 'label': 'Mask'},
    {'icon': Icons.content_copy, 'label': 'Duplicate'},
    {'icon': Icons.rotate_right, 'label': 'Rotate'},
    {'icon': Icons.ac_unit, 'label': 'Freeze'},
    {'icon': Icons.camera_alt_outlined, 'label': 'Capture'},
    {'icon': Icons.fast_rewind, 'label': 'Reverse'},
  ];

  @override
  void initState() {
    super.initState();
    unawaited(MonetizationService.instance.initialize());
    _activeAspectPreset = _editorAspectPresets.contains(
      widget.launchConfig.aspectRatio,
    )
        ? widget.launchConfig.aspectRatio
        : _editorAspectPresets.first;

    final workflow = widget.launchConfig.workflow;
    if (workflow != null) {
      _showGuide = false;
      _selectedToolIndex = _toolIndexForWorkflow(workflow);
    }

    if (widget.launchConfig.initialVideoFile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_loadInitialVideoFile(widget.launchConfig.initialVideoFile!));
      });
    } else if (widget.launchConfig.autoOpenPicker) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _didAutoOpenPicker) {
          return;
        }
        _didAutoOpenPicker = true;
        unawaited(_pickMedia());
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final previewAspectRatio = _aspectRatioFromPreset(_activeAspectPreset);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0F),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildTopBar(),
                _buildLaunchSummary(),
                _buildAspectPresetStrip(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final maxWidth = constraints.maxWidth.clamp(0.0, 360.0);
                        final maxHeight =
                            constraints.maxHeight.clamp(0.0, 640.0);
                        final heightFromWidth = maxWidth / previewAspectRatio;
                        final fitsByWidth = heightFromWidth <= maxHeight;
                        final canvasWidth = fitsByWidth
                            ? maxWidth
                            : maxHeight * previewAspectRatio;
                        final canvasHeight =
                            fitsByWidth ? heightFromWidth : maxHeight;

                        return Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            width: canvasWidth,
                            height: canvasHeight,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.cyanAccent.withValues(alpha: 0.4),
                                width: 1.5,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                fit: StackFit.expand,
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    color: const Color(0xFF16161E),
                                    child: _buildCanvasPreview(),
                                  ),
                                  if (_hasActiveTemplateOverlay)
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: Opacity(
                                          opacity: 0.92,
                                          child: Image.asset(
                                            _activeTemplateOverlayAsset!,
                                            fit: BoxFit.fill,
                                          ),
                                        ),
                                      ),
                                    ),
                                  _buildHudOverlayLabels(),
                                  if (!_isPlaying)
                                    GestureDetector(
                                      onTap: _togglePlayback,
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF6366F1)
                                              .withValues(alpha: 0.85),
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF6366F1)
                                                  .withValues(alpha: 0.4),
                                              blurRadius: 20,
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 36,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.undo,
                          color: Colors.white38,
                          size: 20,
                        ),
                        onPressed: () => _showEditorNotice('Undo applied.'),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.redo,
                          color: Colors.white38,
                          size: 20,
                        ),
                        onPressed: () => _showEditorNotice('Redo applied.'),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 26,
                        ),
                        onPressed: () =>
                            setState(() => _isPlaying = !_isPlaying),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(
                          Icons.fullscreen,
                          color: Colors.white38,
                          size: 22,
                        ),
                        onPressed: () => _showEditorNotice(
                            'Fullscreen preview coming next.'),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 68,
                  decoration: const BoxDecoration(
                    color: Color(0xFF121218),
                    border: Border(
                      top: BorderSide(color: Colors.white10),
                      bottom: BorderSide(color: Colors.white10),
                    ),
                  ),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _tools.length,
                    itemBuilder: (context, index) {
                      final tool = _tools[index];
                      final isSelected = _selectedToolIndex == index;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedToolIndex = index),
                        child: Container(
                          width: 64,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF6366F1).withValues(alpha: 0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                tool['icon'] as IconData,
                                color: isSelected
                                    ? const Color(0xFF6366F1)
                                    : Colors.white.withValues(alpha: 0.8),
                                size: 20,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                tool['label'] as String,
                                style: TextStyle(
                                  color: isSelected
                                      ? const Color(0xFF6366F1)
                                      : Colors.white60,
                                  fontSize: 10,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  height: 120,
                  color: const Color(0xFF0D0D12),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 24,
                            horizontal: 16,
                          ),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: _pickMedia,
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF2A6D),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E1E2A),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFF6366F1),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Row(
                                      children: List.generate(
                                        5,
                                        (i) => Expanded(
                                          child: Container(
                                            margin: const EdgeInsets.all(1),
                                            color: Colors.white10,
                                            child: const Icon(
                                              Icons.image,
                                              size: 16,
                                              color: Colors.white24,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: 3,
                        height: 90,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 10,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Color(0xFF6366F1),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const Positioned(
                        bottom: 4,
                        child: Text(
                          '00:00.0 / 00:05.0',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_showGuide) _buildGuideOverlay(),
            if (_isImporting)
              Container(
                color: Colors.black.withValues(alpha: 0.45),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new,
              color: Colors.white,
              size: 18,
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          IconButton(
            icon:
                const Icon(Icons.help_outline, color: Colors.white60, size: 20),
            onPressed: () => setState(() => _showGuide = true),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Export video',
            icon: const Icon(
              Icons.download_done,
              color: Colors.cyanAccent,
            ),
            onPressed: () => _exportFinalVideo(context),
          ),
        ],
      ),
    );
  }

  Widget _buildLaunchSummary() {
    final workflow = widget.launchConfig.workflow;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildMetaChip(widget.launchConfig.mode, const Color(0xFF6366F1)),
          _buildMetaChip(
            _activeAspectPreset,
            const Color(0xFF0EA5E9),
          ),
          _buildMetaChip(widget.launchConfig.source, const Color(0xFF10B981)),
          if (workflow != null)
            _buildMetaChip('AI: $workflow', const Color(0xFFF59E0B)),
        ],
      ),
    );
  }

  Widget _buildAspectPresetStrip() {
    return SizedBox(
      height: 42,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _editorAspectPresets.length,
        itemBuilder: (context, index) {
          final preset = _editorAspectPresets[index];
          final isSelected = preset == _activeAspectPreset;
          return GestureDetector(
            key: ValueKey('editor-aspect-chip-$preset'),
            onTap: () => _setAspectPreset(preset),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF6366F1).withValues(alpha: 0.28)
                    : const Color(0xFF161622),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF6366F1)
                      : Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Text(
                preset,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white60,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetaChip(String text, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: accent,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  int _toolIndexForWorkflow(String workflow) {
    switch (workflow) {
      case 'Auto-Cap Cut':
        return 8; // Split
      case 'Background Remover':
        return 0; // Canvas
      case 'Highlight Reel':
        return 4; // Effect
      case 'Voice Sync':
        return 1; // Audio
      default:
        return -1;
    }
  }

  double _aspectRatioFromPreset(String preset) {
    if (preset.startsWith('9:16')) {
      return 9 / 16;
    }
    if (preset.startsWith('16:9')) {
      return 16 / 9;
    }
    if (preset.startsWith('1:1')) {
      return 1;
    }
    if (preset.startsWith('4:5')) {
      return 4 / 5;
    }
    return 9 / 16;
  }

  void _setAspectPreset(String preset) {
    setState(() => _activeAspectPreset = preset);
    _showEditorNotice('Format set to $preset');
  }

  Future<void> _exportTemplateVideo() async {
    final sourceFile = _selectedMediaFile ?? widget.launchConfig.initialVideoFile;
    if (sourceFile == null) {
      _showEditorNotice('Import a video before exporting.');
      return;
    }

    final templateId = widget.launchConfig.templateId ?? 'cyberpunk_tokyo';
    final template = clipSnapTemplates.firstWhere(
      (item) => item.id == templateId,
      orElse: () => clipSnapTemplates.first,
    );

    try {
      final tempDir = await getTemporaryDirectory();
      final outputPath =
          '${tempDir.path}/clip_snap_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final success = await exportVideoWithTemplate(
        inputPath: sourceFile.path,
        outputPath: outputPath,
        selectedTemplate: template,
      );

      if (!mounted) {
        return;
      }

      if (success) {
        final result = await ImageGallerySaverPlus.saveFile(outputPath);
        final savedToGallery = result is Map && result['isSuccess'] == true;
        if (savedToGallery) {
          _showEditorNotice('Saved to Gallery successfully!');
        } else {
          _showEditorNotice('Rendered, but failed to save to gallery.');
        }
      } else {
        _showEditorNotice('Export failed. Please try again.');
      }
    } catch (error) {
      if (mounted) {
        _showEditorNotice('Export failed: $error');
      }
    }
  }

  Future<void> _exportFinalVideo(BuildContext context) async {
    if (!context.mounted) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const AlertDialog(
        backgroundColor: Color(0xFF16161A),
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.cyanAccent),
            SizedBox(width: 20),
            Flexible(
              child: Text(
                'Rendering Cyberpunk Video...',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      await _exportTemplateVideo();
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  void _showEditorNotice(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _loadInitialVideoFile(File file) async {
    try {
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.pause();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _selectedMediaFile = file;
        _videoController = controller;
        _isPlaying = false;
        _mediaLabel = file.path.split(Platform.pathSeparator).last;
      });
    } catch (error) {
      _showEditorNotice('Unable to load initial video: $error');
    }
  }

  Future<void> _pickMedia() async {
    try {
      setState(() => _isImporting = true);
      final isPhotoMode = widget.launchConfig.mode.toLowerCase() == 'photo';
      final isVideoMode = widget.launchConfig.mode.toLowerCase() == 'video';
      final file = await _mediaPicker.pickMediaFile(
        allowImages: isPhotoMode || !isVideoMode,
        allowVideos: isVideoMode || !isPhotoMode,
      );

      if (!mounted || file == null) {
        setState(() => _isImporting = false);
        return;
      }

      final path = file.path;
      final extension = path.split('.').last.toLowerCase();
      final isVideo = ['mp4', 'mov', 'm4v', 'avi', 'mkv'].contains(extension);
      final isImage = ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(extension);
      final mediaName = path.split(Platform.pathSeparator).last;

      if (isVideo) {
        final previous = _videoController;
        _videoController = null;
        await previous?.dispose();

        final controller = VideoPlayerController.file(file);
        await controller.initialize();
        await controller.setLooping(true);
        await controller.pause();

        if (!mounted) {
          await controller.dispose();
          return;
        }

        setState(() {
          _selectedMediaFile = file;
          _imageBytes = null;
          _mediaLabel = mediaName;
          _isPlaying = false;
          _videoController = controller;
          _isImporting = false;
        });
        _showEditorNotice('Added video: $mediaName');
        return;
      }

      if (isImage) {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          setState(() => _isImporting = false);
          _showEditorNotice('Could not read the selected image.');
          return;
        }

        await _videoController?.dispose();
        _videoController = null;

        if (!mounted) {
          return;
        }

        setState(() {
          _imageBytes = bytes;
          _mediaLabel = mediaName;
          _isPlaying = false;
          _isImporting = false;
        });
        _showEditorNotice('Added image: $mediaName');
        return;
      }

      setState(() {
        _isImporting = false;
        _mediaLabel = mediaName;
      });
      _showEditorNotice('Selected $mediaName.');
    } catch (error) {
      if (mounted) {
        setState(() => _isImporting = false);
        _showEditorNotice('Media import failed: $error');
      }
    }
  }

  Widget _buildCanvasPreview() {
    final videoController = _videoController;
    if (videoController != null && videoController.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: videoController.value.size.width,
              height: videoController.value.size.height,
              child: VideoPlayer(videoController),
            ),
          ),
          if (_mediaLabel != null)
            Positioned(
              left: 12,
              bottom: 12,
              child: _buildMediaBadge(_mediaLabel!),
            ),
        ],
      );
    }

    final imageBytes = _imageBytes;
    if (imageBytes != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            imageBytes,
            fit: BoxFit.cover,
            key: const ValueKey('editor-selected-image'),
          ),
          if (_mediaLabel != null)
            Positioned(
              left: 12,
              bottom: 12,
              child: _buildMediaBadge(_mediaLabel!),
            ),
        ],
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.perm_media_outlined,
              color: Colors.white24,
              size: 44,
            ),
            const SizedBox(height: 10),
            Text(
              'Video / Photo Canvas $_activeAspectPreset',
              key: const ValueKey('editor-canvas-label'),
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap + to import a photo or video.',
              style: TextStyle(color: Colors.white24, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHudOverlayLabels() {
    return IgnorePointer(
      child: Stack(
        children: [
          const Positioned(
            top: 24,
            left: 24,
            child: Text(
              'REC // SHINJUKU // TILT: -10\nCAM_01: ACTIVE // ZONE_B',
              style: TextStyle(
                color: Colors.cyanAccent,
                fontSize: 9,
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
          Positioned(
            bottom: 28,
            right: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'FEED: DIGITAL_STREAM_v7',
                  style: TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 9,
                    fontFamily: 'monospace',
                  ),
                ),
                Container(
                  height: 2,
                  width: 56,
                  margin: const EdgeInsets.only(top: 4),
                  color: const Color(0xFFFF4FD8).withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _togglePlayback() async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      setState(() => _isPlaying = !_isPlaying);
      return;
    }

    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }

    if (mounted) {
      setState(() => _isPlaying = controller.value.isPlaying);
    }
  }

  Widget _buildGuideOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.65),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2A).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(24),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select one track to edit.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.content_cut,
                              color: Colors.white70, size: 18),
                          SizedBox(width: 12),
                          Icon(Icons.call_split,
                              color: Colors.white70, size: 18),
                          SizedBox(width: 12),
                          Icon(
                            Icons.delete_outline,
                            color: Colors.white70,
                            size: 18,
                          ),
                          SizedBox(width: 12),
                          Icon(Icons.speed, color: Colors.white70, size: 18),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Drag the handle to trim video.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF6366F1)),
                      ),
                      child: const Center(
                        child: Text(
                          '< Drag Handles >',
                          style: TextStyle(
                            color: Color(0xFF6366F1),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => setState(() => _showGuide = false),
                        child: const Text(
                          'NEXT',
                          style: TextStyle(
                            color: Color(0xFF6366F1),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
