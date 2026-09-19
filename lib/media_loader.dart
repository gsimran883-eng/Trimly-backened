import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'media_picker_handler.dart';
import 'screens/clip_snap_pro_editor.dart';
import 'screens/clip_snap_studio_editor.dart';
import 'theme/motion_spec.dart';
import 'widgets/throttled_video_scrubber.dart';

class ClipSnapVideoEditor extends StatefulWidget {
  final String initialMode;
  final bool autoOpenPicker;
  final String initialAspectRatio;
  final String? initialWorkflow;
  final String? initialAiTool;
  final Map<String, Object?>? initialAiConfig;
  final File? initialVideoFile;
  final String launchSource;

  const ClipSnapVideoEditor({
    super.key,
    this.initialMode = 'Video',
    this.autoOpenPicker = false,
    this.initialAspectRatio = '9:16 Reels/Shorts',
    this.initialWorkflow,
    this.initialAiTool,
    this.initialAiConfig,
    this.initialVideoFile,
    this.launchSource = 'Quick Dock',
  });

  @override
  State<ClipSnapVideoEditor> createState() => _ClipSnapVideoEditorState();
}

class _ClipSnapVideoEditorState extends State<ClipSnapVideoEditor>
    with TickerProviderStateMixin {
  static const Color _accent = Color(0xFF3E56FF);
  static const Color _accentSoft = Color(0xFF47C8FF);
  static const Duration _longVideoThreshold = Duration(minutes: 20);

  VideoPlayerController? _videoController;
  final SafeMediaPicker _mediaPicker = SafeMediaPicker();
  File? _imageFile;

  String _activeTool = 'Adjust';
  String _activeAdjustSubTool = 'Brightness';

  double _brightness = 0.0;
  double _contrast = 1.0;
  double _saturation = 1.0;
  double _playbackSpeed = 1.0;

  Color _filterTint = Colors.transparent;
  double _filterOpacity = 0.0;

  final List<TextOverlayData> _textLayers = [];

  double _startTrimMs = 0;
  double _endTrimMs = 0;
  Timer? _trimSeekDebounce;

  late final AnimationController _entryController;

  bool get _shouldOpenImagePicker =>
      widget.initialMode.toLowerCase() == 'photo';

  String get _normalizedMode => widget.initialMode.trim().toLowerCase();

  @override
  void dispose() {
    _trimSeekDebounce?.cancel();
    _entryController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: MotionSpec.entryDuration,
    )..forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreOrOpenInitialPicker();
    });
  }

  Future<void> _importImage() async {
    final file = await _mediaPicker.selectImageFromGallery();
    if (file == null) {
      _showImportMessage('No image selected. Please choose a photo.');
      return;
    }
    await _loadImageFile(file);
  }

  Future<void> _importVideo() async {
    final file = await _mediaPicker.selectVideoFromGallery();
    if (file == null) {
      _showImportMessage('No video selected. Please choose a video.');
      return;
    }

    await _loadVideoFile(file);
  }

  void _showImportMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _restoreOrOpenInitialPicker() async {
    final initialVideoFile = widget.initialVideoFile;
    if (initialVideoFile != null) {
      await _loadVideoFile(initialVideoFile);
      return;
    }

    final lostFile = await _mediaPicker.retrieveLostMedia();
    if (!mounted) {
      return;
    }

    if (lostFile != null) {
      final isLostVideo = _isVideoPath(lostFile.path);
      final isLostImage = _isImagePath(lostFile.path);

      debugPrint(
        'Recovered lost media path=${lostFile.path} mode=$_normalizedMode '
        'isVideo=$isLostVideo isImage=$isLostImage',
      );

      if (_shouldOpenImagePicker) {
        if (isLostImage || !isLostVideo) {
          await _loadImageFile(lostFile);
          return;
        }

        _showImportMessage(
            'Recovered media was a video. Please choose a photo.');
      } else {
        if (isLostVideo) {
          await _loadVideoFile(lostFile);
          return;
        }

        _showImportMessage(
            'Recovered media was an image. Please choose a video.');
      }
    }

    if (!widget.autoOpenPicker) {
      return;
    }

    if (_shouldOpenImagePicker) {
      await _importImage();
    } else {
      await _importVideo();
    }
  }

  bool _isVideoPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm');
  }

  bool _isImagePath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif');
  }

  Future<void> _loadImageFile(File file) async {
    await _videoController?.dispose();
    if (!mounted) {
      return;
    }

    setState(() {
      _imageFile = file;
      _videoController = null;
      _startTrimMs = 0;
      _endTrimMs = 0;
    });

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClipSnapProEditor(
          imageFile: file,
          initialAiTool: widget.initialAiTool,
          initialAiConfig: widget.initialAiConfig,
        ),
      ),
    );
  }

  Future<void> _loadVideoFile(
    File file, {
    bool allowProxyPrompt = true,
  }) async {
    await _videoController?.dispose();
    final controller = VideoPlayerController.file(file);
    await controller.initialize();

    if (allowProxyPrompt &&
        controller.value.duration >= _longVideoThreshold &&
        mounted) {
      final shouldProxy = await _promptForProxyEdit(controller.value.duration);
      if (shouldProxy) {
        await controller.dispose();
        final proxyFile = await _createProxyVideo(file);
        if (proxyFile != null) {
          await _loadVideoFile(proxyFile, allowProxyPrompt: false);
          return;
        }
      }
    }

    await controller.setLooping(true);
    await controller.pause();

    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _imageFile = null;
      _videoController = controller;
      _startTrimMs = 0;
      _endTrimMs = controller.value.duration.inMilliseconds.toDouble();
    });

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClipSnapStudioEditor(
          videoFile: file,
          initialAspectRatio: widget.initialAspectRatio,
          initialWorkflow: widget.initialWorkflow,
          initialAiTool: widget.initialAiTool,
          initialAiConfig: widget.initialAiConfig,
          launchSource: widget.launchSource,
        ),
      ),
    );
  }

  Future<bool> _promptForProxyEdit(Duration duration) async {
    final minutes = duration.inMinutes;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Large video detected'),
            content: Text(
              '$minutes min videos can scrub slowly. Create a lightweight proxy for editing?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Use original'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Create proxy'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<File?> _createProxyVideo(File inputFile) async {
    _showImportMessage('Creating smooth editing proxy...');
    final tempDir = await getTemporaryDirectory();
    final outputPath =
        '${tempDir.path}/clipsnap_proxy_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final command = '-y -i "${_escapePathArg(inputFile.path)}" '
        '-vf "scale=-2:720" -r 24 -c:v libx264 -preset ultrafast -crf 30 '
        '-c:a aac -b:a 96k -movflags +faststart "${_escapePathArg(outputPath)}"';
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    final outputFile = File(outputPath);
    if (ReturnCode.isSuccess(returnCode) && await outputFile.exists()) {
      _showImportMessage('Proxy ready for smooth editing.');
      return outputFile;
    }

    _showImportMessage('Proxy creation failed. Opening original video.');
    return null;
  }

  String _escapePathArg(String value) {
    return value.replaceAll('"', r'\"');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0F),
      body: SafeArea(
        child: Column(
          children: [
            _buildReveal(order: 0, child: _buildTopNavBar()),
            Expanded(
              child: Center(
                child: _videoController != null &&
                        _videoController!.value.isInitialized
                    ? Container(
                        margin: const EdgeInsets.all(16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: AspectRatio(
                            aspectRatio: _videoController!.value.aspectRatio,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                ColorFiltered(
                                  colorFilter:
                                      ColorFilter.matrix(_buildColorMatrix()),
                                  child: VideoPlayer(_videoController!),
                                ),
                                Positioned.fill(
                                  child: Container(
                                    color: _filterTint.withValues(
                                      alpha: _filterOpacity,
                                    ),
                                  ),
                                ),
                                ..._textLayers.map(_buildDraggableText),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      if (_videoController!.value.isPlaying) {
                                        _videoController!.pause();
                                      } else {
                                        _videoController!.play();
                                      }
                                    });
                                  },
                                  child: Container(
                                    color: Colors.transparent,
                                    child: !_videoController!.value.isPlaying
                                        ? const Icon(
                                            Icons.play_circle_fill,
                                            size: 64,
                                            color: Colors.white70,
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : _imageFile != null
                        ? Container(
                            margin: const EdgeInsets.all(16),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  ColorFiltered(
                                    colorFilter:
                                        ColorFilter.matrix(_buildColorMatrix()),
                                    child: Image.file(
                                      _imageFile!,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: Container(
                                      color: _filterTint.withValues(
                                        alpha: _filterOpacity,
                                      ),
                                    ),
                                  ),
                                  ..._textLayers.map(_buildDraggableText),
                                ],
                              ),
                            ),
                          )
                        : _buildEmptyState(),
              ),
            ),
            if (_videoController != null &&
                _videoController!.value.isInitialized)
              _buildReveal(order: 1, child: _buildVideoTimeline()),
            _buildBottomPanel(),
          ],
        ),
      ),
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

  Widget _buildBottomPanel() {
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
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF12121A),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 110,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: AnimatedSwitcher(
                  duration: MotionSpec.panelSwitchDuration,
                  switchInCurve: MotionSpec.switchInCurve,
                  switchOutCurve: MotionSpec.switchOutCurve,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(MotionSpec.switchOffsetX, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey('tool-panel-$_activeTool'),
                    child: _buildActiveToolControls(),
                  ),
                ),
              ),
              Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      _accentSoft.withValues(alpha: 0.35),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              _buildMainToolBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopNavBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.folder_open, color: Colors.white),
            onPressed: _shouldOpenImagePicker ? _importImage : _importVideo,
          ),
          const Text(
            'ClipSnap Studio',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            onPressed: _videoController != null ? _exportVideo : null,
            child: const Text(
              'Export',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return GestureDetector(
      onTap: _shouldOpenImagePicker ? _importImage : _importVideo,
      child: Container(
        width: 280,
        height: 380,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.video_call_rounded,
                size: 64, color: Color(0xFF2563EB)),
            const SizedBox(height: 12),
            Text(
              _shouldOpenImagePicker ? 'Import Photo' : 'Import Video Clip',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap to select from device gallery',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoTimeline() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: const Color(0xFF0D0D12),
      child: Row(
        children: [
          ValueListenableBuilder(
            valueListenable: _videoController!,
            builder: (context, VideoPlayerValue value, child) {
              return Text(
                _formatDuration(value.position),
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              );
            },
          ),
          Expanded(
            child: ThrottledVideoScrubber(
              controller: _videoController!,
              playedColor: _accent,
              bufferedColor: Colors.white24,
              backgroundColor: Colors.white10,
            ),
          ),
          Text(
            _formatDuration(_videoController!.value.duration),
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveToolControls() {
    final hasMedia =
        _videoController != null && _videoController!.value.isInitialized;
    final hasImage = _imageFile != null;

    if (!hasMedia && !hasImage) {
      return const Center(
        child: Text(
          'Import a photo or video to enable tools',
          style: TextStyle(color: Colors.white38),
        ),
      );
    }

    switch (_activeTool) {
      case 'Adjust':
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildSubToolChip('Brightness'),
                const SizedBox(width: 8),
                _buildSubToolChip('Contrast'),
                const SizedBox(width: 8),
                _buildSubToolChip('Saturation'),
              ],
            ),
            Expanded(
              child: Slider(
                value: _getAdjustValue(),
                min: _getAdjustMin(),
                max: _getAdjustMax(),
                activeColor: _accent,
                onChanged: (val) {
                  setState(() {
                    _setAdjustValue(val);
                  });
                },
              ),
            ),
          ],
        );
      case 'Filters':
        return ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _buildFilterPreset('Original', Colors.transparent, 0.0),
            _buildFilterPreset('Cinematic', Colors.amber, 0.2),
            _buildFilterPreset('Cyber', Colors.cyan, 0.25),
            _buildFilterPreset('Moody', Colors.purple, 0.3),
            _buildFilterPreset('Noir', Colors.black, 0.5),
          ],
        );
      case 'Text':
        return Row(
          children: [
            Expanded(
              child: TextField(
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Add text overlay...',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                ),
                onSubmitted: (text) {
                  if (text.isNotEmpty) {
                    setState(() {
                      _textLayers.add(TextOverlayData(text: text));
                    });
                  }
                },
              ),
            ),
            ElevatedButton(
              onPressed: _showAddTextDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
              ),
              child: const Text('Add Text'),
            ),
          ],
        );
      case 'Speed':
        if (!hasMedia) {
          return const Center(
            child: Text(
              'Speed controls are available for video clips.',
              style: TextStyle(color: Colors.white38),
            ),
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [0.5, 1.0, 1.25, 1.5, 2.0].map((speed) {
            final isSelected = _playbackSpeed == speed;
            return ChoiceChip(
              label: Text('${speed}x'),
              selected: isSelected,
              selectedColor: _accent,
              backgroundColor: const Color(0xFF1E1E2A),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
              ),
              onSelected: (_) {
                setState(() {
                  _playbackSpeed = speed;
                  _videoController!.setPlaybackSpeed(speed);
                });
              },
            );
          }).toList(),
        );
      case 'Trim':
        if (!hasMedia) {
          return const Center(
            child: Text(
              'Trim controls are available for video clips.',
              style: TextStyle(color: Colors.white38),
            ),
          );
        }
        final duration =
            _videoController!.value.duration.inMilliseconds.toDouble();
        return Column(
          children: [
            const Text(
              'Trim Range',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            RangeSlider(
              values: RangeValues(_startTrimMs, _endTrimMs),
              min: 0,
              max: duration > 0 ? duration : 1.0,
              activeColor: _accent,
              onChanged: (RangeValues values) {
                setState(() {
                  _startTrimMs = values.start;
                  _endTrimMs = values.end;
                });
                _queueTrimSeek(values.start);
              },
              onChangeEnd: (values) => _seekTrimImmediately(values.start),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _queueTrimSeek(double startMs) {
    if (_trimSeekDebounce?.isActive ?? false) {
      return;
    }
    _trimSeekDebounce = Timer(const Duration(milliseconds: 50), () {
      _videoController?.seekTo(Duration(milliseconds: startMs.toInt()));
    });
  }

  void _seekTrimImmediately(double startMs) {
    _trimSeekDebounce?.cancel();
    _videoController?.seekTo(Duration(milliseconds: startMs.toInt()));
  }

  Widget _buildMainToolBar() {
    final tools = [
      {'name': 'Adjust', 'icon': Icons.tune},
      {'name': 'Filters', 'icon': Icons.auto_awesome},
      {'name': 'Text', 'icon': Icons.text_fields},
      if (_videoController != null && _videoController!.value.isInitialized)
        {'name': 'Trim', 'icon': Icons.content_cut},
      if (_videoController != null && _videoController!.value.isInitialized)
        {'name': 'Speed', 'icon': Icons.speed},
    ];

    return Container(
      height: 65,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: tools.map((tool) {
          final isSelected = _activeTool == tool['name'];
          return GestureDetector(
            onTap: () => setState(() => _activeTool = tool['name'] as String),
            child: AnimatedScale(
              duration: MotionSpec.selectionDuration,
              curve: MotionSpec.emphasisCurve,
              scale: isSelected ? 1.04 : 1.0,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    tool['icon'] as IconData,
                    color: isSelected ? _accent : Colors.white60,
                    size: 22,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tool['name'] as String,
                    style: TextStyle(
                      color: isSelected ? _accentSoft : Colors.white60,
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDraggableText(TextOverlayData layer) {
    return Positioned(
      left: layer.offset.dx,
      top: layer.offset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            layer.offset += details.delta;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            layer.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(blurRadius: 6, color: Colors.black)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubToolChip(String label) {
    final isSelected = _activeAdjustSubTool == label;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: isSelected,
      selectedColor: _accent,
      backgroundColor: const Color(0xFF1E1E2A),
      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white60),
      onSelected: (_) => setState(() => _activeAdjustSubTool = label),
    );
  }

  Widget _buildFilterPreset(String name, Color color, double opacity) {
    final isSelected = _filterTint == color;
    return GestureDetector(
      onTap: () => setState(() {
        _filterTint = color;
        _filterOpacity = opacity;
      }),
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _accent : const Color(0xFF1E1E2A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  List<double> _buildColorMatrix() {
    final b = _brightness * 255;
    final c = _contrast;
    final s = _saturation;

    return [
      c * s,
      0,
      0,
      0,
      b,
      0,
      c * s,
      0,
      0,
      b,
      0,
      0,
      c * s,
      0,
      b,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  double _getAdjustValue() {
    if (_activeAdjustSubTool == 'Brightness') return _brightness;
    if (_activeAdjustSubTool == 'Contrast') return _contrast;
    return _saturation;
  }

  double _getAdjustMin() => _activeAdjustSubTool == 'Brightness' ? -0.5 : 0.5;
  double _getAdjustMax() => _activeAdjustSubTool == 'Brightness' ? 0.5 : 1.5;

  void _setAdjustValue(double val) {
    if (_activeAdjustSubTool == 'Brightness') _brightness = val;
    if (_activeAdjustSubTool == 'Contrast') _contrast = val;
    if (_activeAdjustSubTool == 'Saturation') _saturation = val;
  }

  void _showAddTextDialog() {
    String input = '';
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
          decoration: const InputDecoration(
            hintText: 'Enter text...',
            hintStyle: TextStyle(color: Colors.white38),
          ),
          onChanged: (value) => input = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
            ),
            onPressed: () {
              if (input.isNotEmpty) {
                setState(() => _textLayers.add(TextOverlayData(text: input)));
              }
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _exportVideo() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Processing video render & export...')),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}';
  }
}

class TextOverlayData {
  String text;
  Offset offset;

  TextOverlayData({
    required this.text,
    this.offset = const Offset(80, 120),
  });
}
