import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../data/template_presets.dart';
import '../models/template_model.dart';
import '../services/ai_caption_service.dart';
import '../services/ai_speech_service.dart';
import '../services/b_roll_suggester.dart';
import '../services/beat_sync_service.dart';
import '../services/export_status_service.dart';
import '../services/monetization_service.dart';
import '../services/point_service.dart';
import '../theme/motion_spec.dart';
import '../widgets/app_feedback.dart';
import '../widgets/editor_tool_bottom_sheet.dart';
import '../widgets/throttled_video_scrubber.dart';
import '../widgets/voice_picker_dialog.dart';

class ClipSnapStudioEditor extends StatefulWidget {
  final File? videoFile;
  final String? initialWorkflow;
  final String? initialTemplateId;
  final bool templateAlreadyRendered;
  final String? initialAiTool;
  final Map<String, Object?>? initialAiConfig;
  final String initialAspectRatio;
  final String launchSource;

  const ClipSnapStudioEditor({
    super.key,
    this.videoFile,
    this.initialWorkflow,
    this.initialTemplateId,
    this.templateAlreadyRendered = false,
    this.initialAiTool,
    this.initialAiConfig,
    this.initialAspectRatio = '9:16 Reels/Shorts',
    this.launchSource = 'Quick Dock',
  });

  @override
  State<ClipSnapStudioEditor> createState() => _ClipSnapStudioEditorState();
}

class _ClipSnapStudioEditorState extends State<ClipSnapStudioEditor>
    with TickerProviderStateMixin {
  static const String _settingsExportQualityKey = 'settings.export_quality';
  static const String _settingsExportFpsKey = 'settings.export_fps';
  static const String _settingsExportBitrateKey =
      'settings.export_bitrate_mbps';
  static const String _settingsDynamicCaptionsKey = 'settings.dynamic_captions';
  static const String _settingsCaptionStylePresetKey =
      'settings.caption_style_preset';
  static const String _settingsBrandWatermarkKey = 'settings.brand_watermark';
  static const String _settingsBrandWatermarkTextKey =
      'settings.brand_watermark_text';
  static const String _settingsBrandAccentColorKey =
      'settings.brand_accent_color';
  static const String _settingsBrandEndScreenTextKey =
      'settings.brand_end_screen_text';
  static const String _settingsBrandLutPathKey = 'settings.brand_lut_path';

  VideoPlayerController? _videoController;
  final AudioPlayer _timelineAudioPlayer = AudioPlayer();
  bool _isVideoInitialized = false;
  bool _isPlaying = false;
  bool _isSyncingAudioPreview = false;
  int _previewingAudioSegment = -1;

  String _activeTool = 'AI';
  bool _isToolSheetOpen = false;
  String _audioToolCategory = 'Audio';
  String _activeAdjustSubTool = 'Brightness';

  double _brightness = 0.0;
  double _contrast = 1.0;
  double _saturation = 1.0;
  double _warmth = 0.0;
  double _vignette = 0.0;

  double _playbackSpeed = 1.0;
  bool _autoDucking = false;
  bool _noiseReduction = false;
  bool _silenceFillerCleanupEnabled = false;

  double _aspectRatio = 0.5625;
  final int _rotationQuarterTurns = 0;

  final List<Map<String, dynamic>> _textLayers = [];
  final Set<int> _removedTranscriptIndexes = <int>{};
  final AiCaptionService _aiCaptionService = AiCaptionService();
  final AISpeechService _aiSpeechService = AISpeechService();
  final BRollSuggester _bRollSuggester = BRollSuggester();
  final BeatSyncService _beatSyncService = BeatSyncService();
  bool _dynamicCaptionsEnabled = true;
  String _captionStylePreset = 'Karaoke';
  int _lastCaptionTickBucket = -1;
  bool _isAnalyzingBeats = false;
  List<int> _beatMarkersMs = [];
  bool _autoCutAtBeatsEnabled = false;
  List<_CutSegment> _autoCutSegments = [];
  List<BRollSuggestion> _bRollSuggestions = [];
  String _selectedOutputRatioPreset = '9:16';
  bool _kineticTextEnabled = false;
  bool _glitchTextStyleEnabled = false;
  bool _duoBeatSyncEnabled = false;
  String? _duoCreator2VideoPath;
  String? _duoAudioTrackPath;
  String? _voiceoverTrackPath;
  String? _musicTrackPath;
  String? _timelineAudioTrackPath;
  bool _previewAudioMuted = false;
  bool _originalAudioMuted = false;
  bool _isExtractingAudio = false;
  double _timelineAudioVolume = 1.0;
  double _audioFadeInSeconds = 0.0;
  double _audioFadeOutSeconds = 0.0;
  List<_AudioSegment> _audioSegments = [const _AudioSegment(0.0, 1.0)];
  List<double> _audioWaveform = const [];
  int _selectedAudioSegment = 0;
  bool _audioDuckerProEnabled = false;
  String _studioMaskTarget = 'Subject';
  bool _studioRefineEdge = true;
  bool _studioSmartTrack = true;
  bool _studioInvertMask = false;
  String _studioUpscalePreset = '2x';
  String _studioSkyPreset = 'Sunny';
  bool _isStudioAiEnhancing = false;

  bool _isExporting = false;
  bool _isGeneratingCaptions = false;
  bool _isGeneratingVoiceover = false;
  double _exportProgress = 0.0;
  String? _sessionExportQuality;
  int? _sessionExportFps;
  int? _sessionExportBitrateMbps;
  bool _templateExportProfileApplied = false;

  final List<Map<String, dynamic>> _tools = [
    {'id': 'Adjust', 'label': 'Color Grade', 'icon': Icons.palette_outlined},
    {
      'id': 'Ratio',
      'label': 'Canvas Ratio',
      'icon': Icons.aspect_ratio_rounded
    },
    {'id': 'Speed', 'label': 'Speed Ramp', 'icon': Icons.speed_rounded},
    {'id': 'AI', 'label': 'AI Tools', 'icon': Icons.auto_awesome},
    {
      'id': 'Audio',
      'label': 'AI Audio Clean',
      'icon': Icons.graphic_eq_rounded
    },
    {'id': 'Captions', 'label': 'Subtitles', 'icon': Icons.subtitles_rounded},
    {'id': 'Transcript', 'label': 'Text Edit', 'icon': Icons.subject_rounded},
    {'id': 'BRoll', 'label': 'B-Roll', 'icon': Icons.movie_filter_rounded},
    {'id': 'Duo', 'label': 'Duo Sync', 'icon': Icons.people_alt_outlined},
    {'id': 'Vignette', 'label': 'Vignette', 'icon': Icons.vignette_rounded},
    {'id': 'Reset', 'label': 'Reset All', 'icon': Icons.restore_rounded},
  ];

  late final AnimationController _entryController;

  VideoTemplate? get _activeTemplate {
    final templateId = widget.initialTemplateId;
    if (templateId == null || templateId.isEmpty) {
      return null;
    }
    for (final template in clipSnapTemplates) {
      if (template.id == templateId) {
        return template;
      }
    }
    return null;
  }

  double get _activeTemplateOverlayOpacity {
    final templateId = _activeTemplate?.id;
    return templateId == 'cyber_glitch_v2' || templateId == 'retro_80s_vhs'
        ? 0.22
        : 0.92;
  }

  bool get _activeTemplateUsesScreenBlend =>
      _activeTemplate?.id == 'cyberpunk_tokyo';

  @override
  void initState() {
    super.initState();
    unawaited(MonetizationService.instance.initialize());
    _entryController = AnimationController(
      vsync: this,
      duration: MotionSpec.entryDuration,
    )..forward();
    _applyInitialTemplateDefaults();
    _applyInitialAiWorkflowConfig();
    _initializeVideo();
    _loadCaptionPreferences();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final workflow = widget.initialWorkflow;
      if (workflow == null || workflow.trim().isEmpty) {
        return;
      }
      final modeLabel = widget.launchSource == 'Template'
          ? 'Template applied'
          : 'Workflow loaded';
      final exportLabel = _templateExportProfileApplied &&
              _sessionExportQuality != null &&
              _sessionExportFps != null &&
              _sessionExportBitrateMbps != null
          ? ' • ${_sessionExportQuality!} / ${_sessionExportFps!}fps / ${_sessionExportBitrateMbps!}Mbps'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$modeLabel: $workflow$exportLabel')),
      );
      if (widget.initialAiTool == 'extract_audio') {
        setState(() => _isToolSheetOpen = true);
      }
    });
  }

  Future<void> _loadCaptionPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      _dynamicCaptionsEnabled =
          prefs.getBool(_settingsDynamicCaptionsKey) ?? _dynamicCaptionsEnabled;
      final savedStyle = prefs.getString(_settingsCaptionStylePresetKey);
      _captionStylePreset = ['Classic', 'Karaoke', 'Neon'].contains(savedStyle)
          ? savedStyle!
          : _captionStylePreset;
      _applyInitialTemplateDefaults();
    });
  }

  void _applyInitialTemplateDefaults() {
    final preset = _ratioPresetFromAspectLabel(widget.initialAspectRatio);
    if (preset != null) {
      _selectedOutputRatioPreset = preset;
      _aspectRatio = _ratioForPreset(preset);
    }

    final workflow = widget.initialWorkflow?.trim();
    if (workflow == null || workflow.isEmpty) {
      return;
    }

    _templateExportProfileApplied = false;

    switch (widget.initialTemplateId ?? workflow) {
      case 'cyberpunk_tokyo':
        _brightness = -0.02;
        _contrast = 1.3;
        _saturation = 1.4;
        _activeTool = 'Adjust';
        _setSessionExportProfile(quality: '1080p', fps: 30, bitrateMbps: 16);
        break;
      case 'neon_velocity':
        _contrast = 1.4;
        _saturation = 1.8;
        _vignette = 0.25;
        _activeTool = 'Adjust';
        _setSessionExportProfile(quality: '1080p', fps: 60, bitrateMbps: 20);
        break;
      case 'cyber_glitch_v2':
        _brightness = -0.05;
        _contrast = 1.3;
        _activeTool = 'Adjust';
        _setSessionExportProfile(quality: '1080p', fps: 30, bitrateMbps: 16);
        break;
      case 'retro_80s_vhs':
        _brightness = 0.04;
        _contrast = 1.15;
        _saturation = 1.25;
        _warmth = 0.25;
        _vignette = 0.12;
        _activeTool = 'Adjust';
        _setSessionExportProfile(quality: '1080p', fps: 30, bitrateMbps: 16);
        break;
      case 'holo_matrix':
        _contrast = 1.1;
        _saturation = 1.3;
        _warmth = -0.2;
        _activeTool = 'Adjust';
        _setSessionExportProfile(quality: '1080p', fps: 30, bitrateMbps: 16);
        break;
      case 'quantum_cinematic':
        _saturation = 1.2;
        _brightness = -0.1;
        _activeTool = 'Adjust';
        _setSessionExportProfile(quality: '4K', fps: 24, bitrateMbps: 24);
        break;
      case 'Duo Beat-Sync':
        _duoBeatSyncEnabled = true;
        _kineticTextEnabled = true;
        _activeTool = 'Duo';
        _setSessionExportProfile(quality: '1080p', fps: 60, bitrateMbps: 22);
        break;
      case 'Podcast Cut':
        _dynamicCaptionsEnabled = true;
        _captionStylePreset = 'Karaoke';
        _noiseReduction = true;
        _silenceFillerCleanupEnabled = true;
        _activeTool = 'Captions';
        _setSessionExportProfile(quality: '1080p', fps: 30, bitrateMbps: 14);
        break;
      case 'Product Spotlight':
        _kineticTextEnabled = true;
        _glitchTextStyleEnabled = false;
        _activeTool = 'Adjust';
        _setSessionExportProfile(quality: '4K', fps: 30, bitrateMbps: 24);
        break;
      case 'Square Promo':
        _selectedOutputRatioPreset = '1:1';
        _aspectRatio = 1.0;
        _kineticTextEnabled = true;
        _activeTool = 'Text';
        _setSessionExportProfile(quality: '1080p', fps: 30, bitrateMbps: 12);
        break;
      case 'Auto-Cap Cut':
        _dynamicCaptionsEnabled = true;
        _captionStylePreset = 'Karaoke';
        _activeTool = 'Captions';
        _setSessionExportProfile(quality: '1080p', fps: 30, bitrateMbps: 12);
        break;
      case 'Voice Sync':
        _noiseReduction = true;
        _silenceFillerCleanupEnabled = true;
        _activeTool = 'Audio';
        _setSessionExportProfile(quality: '1080p', fps: 30, bitrateMbps: 14);
        break;
      case 'Highlight Reel':
        _kineticTextEnabled = true;
        _activeTool = 'Adjust';
        _setSessionExportProfile(quality: '1080p', fps: 60, bitrateMbps: 20);
        break;
      default:
        break;
    }
  }

  void _setSessionExportProfile({
    required String quality,
    required int fps,
    required int bitrateMbps,
  }) {
    _sessionExportQuality = quality;
    _sessionExportFps = fps;
    _sessionExportBitrateMbps = bitrateMbps;
    _templateExportProfileApplied = true;
  }

  void _applyInitialAiWorkflowConfig() {
    if (widget.initialAiTool == 'extract_audio') {
      _activeTool = 'Audio';
      return;
    }

    final aiConfig = widget.initialAiConfig;
    if (aiConfig == null || aiConfig.isEmpty) {
      return;
    }

    _activeTool = 'AI';

    final aiTool = widget.initialAiTool;
    final preset = aiConfig['preset'] as String?;
    final strength = (aiConfig['refinementStrength'] as num?)?.toDouble();

    if (preset != null && preset.isNotEmpty) {
      _studioMaskTarget = _mapStudioMaskTarget(preset);
    }
    if (aiConfig['preserveHairEdges'] is bool) {
      _studioRefineEdge = aiConfig['preserveHairEdges'] as bool;
    }
    if (aiConfig['horizonBlend'] is bool) {
      _studioSmartTrack = aiConfig['horizonBlend'] as bool;
    }
    if (aiConfig['denoisePass'] is bool) {
      _noiseReduction = aiConfig['denoisePass'] as bool;
    }

    final skyPack = aiConfig['skyPack'] as String?;
    if (skyPack != null || aiTool == 'sky_replace') {
      _studioSkyPreset = _mapStudioSkyPreset(skyPack);
    }

    final outputSize = aiConfig['outputSize'] as String?;
    if (outputSize != null ||
        aiTool == 'ai_upscale' ||
        aiTool == 'object_preset') {
      _studioUpscalePreset = _mapStudioUpscalePreset(outputSize);
    }

    if (strength != null) {
      final normalized = strength.clamp(0.0, 1.0);
      _contrast = (0.95 + normalized * 0.25).clamp(0.5, 2.0);
      _saturation = (0.95 + normalized * 0.18).clamp(0.3, 2.0);
      _vignette = (0.08 + normalized * 0.16).clamp(0.0, 0.8);
    }
  }

  String _mapStudioMaskTarget(String preset) {
    switch (preset) {
      case 'Ad Product':
      case 'Product Focus':
        return 'Select Object';
      case 'Trailer Cut':
      case 'Clean BG':
        return 'Background';
      default:
        return 'Subject';
    }
  }

  String _mapStudioSkyPreset(String? skyPack) {
    switch (skyPack) {
      case 'Golden Hour':
        return 'Sunset';
      case 'Dramatic Clouds':
      case 'Night Glow':
        return 'Starry';
      default:
        return 'Sunny';
    }
  }

  String _mapStudioUpscalePreset(String? outputSize) {
    switch (outputSize) {
      case '2K':
        return '2x';
      case '4K':
        return '4x';
      case '8K Preview':
        return '8x';
      default:
        return '4x';
    }
  }

  String? _ratioPresetFromAspectLabel(String? aspectLabel) {
    if (aspectLabel == null || aspectLabel.isEmpty) {
      return null;
    }
    if (aspectLabel.startsWith('9:16')) {
      return '9:16';
    }
    if (aspectLabel.startsWith('16:9')) {
      return '16:9';
    }
    if (aspectLabel.startsWith('1:1')) {
      return '1:1';
    }
    if (aspectLabel.startsWith('4:5')) {
      return '4:5';
    }
    return null;
  }

  double _ratioForPreset(String preset) {
    switch (preset) {
      case '16:9':
        return 1.777;
      case '1:1':
        return 1.0;
      case '4:5':
        return 0.8;
      case '9:16':
      default:
        return 0.5625;
    }
  }

  Future<void> _persistCaptionPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_settingsDynamicCaptionsKey, _dynamicCaptionsEnabled);
    await prefs.setString(_settingsCaptionStylePresetKey, _captionStylePreset);
  }

  Future<void> _initializeVideo() async {
    final input = widget.videoFile;
    if (input == null) {
      return;
    }

    final controller = VideoPlayerController.file(input);
    await controller.initialize();
    await controller.setLooping(true);
    await controller.setVolume(
      _previewAudioMuted || _originalAudioMuted ? 0 : 1,
    );
    controller.addListener(_onVideoTick);

    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _videoController = controller;
      _isVideoInitialized = true;
    });
  }

  @override
  void dispose() {
    _entryController.dispose();
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    unawaited(_timelineAudioPlayer.dispose());
    super.dispose();
  }

  void _onVideoTick() {
    final positionMs = _videoController?.value.position.inMilliseconds;
    if (positionMs == null) {
      return;
    }

    unawaited(_syncTimelineAudioPreview(positionMs));

    if (!_dynamicCaptionsEnabled || _textLayers.isEmpty) {
      return;
    }

    final bucket = positionMs ~/ 120;
    if (bucket == _lastCaptionTickBucket || !mounted) {
      return;
    }

    setState(() {
      _lastCaptionTickBucket = bucket;
    });
  }

  Future<void> _togglePlayback() async {
    final controller = _videoController;
    if (controller == null || !_isVideoInitialized) {
      return;
    }

    if (controller.value.isPlaying) {
      await controller.pause();
      await _timelineAudioPlayer.pause();
      if (mounted) {
        setState(() => _isPlaying = false);
      }
      return;
    }

    await controller.setVolume(
      _previewAudioMuted || _originalAudioMuted ? 0 : 1,
    );
    await controller.play();
    if (mounted) {
      setState(() => _isPlaying = true);
    }
    await _syncTimelineAudioPreview(
      controller.value.position.inMilliseconds,
      force: true,
    );
  }

  Future<void> _setOriginalAudioMuted(bool muted) async {
    setState(() => _originalAudioMuted = muted);
    await _videoController?.setVolume(
      _previewAudioMuted || muted ? 0 : 1,
    );
  }

  Future<void> _setPreviewAudioMuted(bool muted) async {
    setState(() => _previewAudioMuted = muted);
    await Future.wait([
      if (_videoController != null)
        _videoController!.setVolume(
          muted || _originalAudioMuted ? 0 : 1,
        ),
      _timelineAudioPlayer.setVolume(muted ? 0 : _timelineAudioVolume),
    ]);
  }

  Future<void> _syncTimelineAudioPreview(
    int positionMs, {
    bool force = false,
  }) async {
    if (_isSyncingAudioPreview) {
      return;
    }

    final controller = _videoController;
    final audioPath = _timelineAudioTrackPath;
    final durationMs = controller?.value.duration.inMilliseconds ?? 0;
    if (controller == null ||
        audioPath == null ||
        durationMs <= 0 ||
        !controller.value.isPlaying) {
      if (_timelineAudioPlayer.state == PlayerState.playing) {
        await _timelineAudioPlayer.pause();
      }
      _previewingAudioSegment = -1;
      return;
    }

    final positionRatio = (positionMs / durationMs).clamp(0.0, 1.0);
    final segmentIndex = _audioSegments.indexWhere(
      (segment) =>
          positionRatio >= segment.start && positionRatio < segment.end,
    );
    if (segmentIndex < 0) {
      if (_timelineAudioPlayer.state == PlayerState.playing) {
        await _timelineAudioPlayer.pause();
      }
      _previewingAudioSegment = -1;
      return;
    }

    final segment = _audioSegments[segmentIndex];
    final previewVolume = _audioPreviewVolume(positionRatio, segment);
    if (!force &&
        segmentIndex == _previewingAudioSegment &&
        _timelineAudioPlayer.state == PlayerState.playing) {
      await _timelineAudioPlayer.setVolume(previewVolume);
      return;
    }

    _isSyncingAudioPreview = true;
    try {
      await _timelineAudioPlayer.play(
        DeviceFileSource(audioPath),
        position: Duration(milliseconds: positionMs),
        volume: previewVolume,
      );
      await _timelineAudioPlayer.setPlaybackRate(_playbackSpeed);
      _previewingAudioSegment = segmentIndex;
    } finally {
      _isSyncingAudioPreview = false;
    }
  }

  double _audioPreviewVolume(
    double positionRatio,
    _AudioSegment segment,
  ) {
    if (_previewAudioMuted) {
      return 0;
    }
    final elapsed = (positionRatio - segment.start) * _videoDurationSeconds;
    final remaining = (segment.end - positionRatio) * _videoDurationSeconds;
    final fadeInGain = _audioFadeInSeconds <= 0
        ? 1.0
        : (elapsed / _audioFadeInSeconds).clamp(0.0, 1.0);
    final fadeOutGain = _audioFadeOutSeconds <= 0
        ? 1.0
        : (remaining / _audioFadeOutSeconds).clamp(0.0, 1.0);
    return _timelineAudioVolume * math.min(fadeInGain, fadeOutGain);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF09090E),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Stack(
            children: [
              Column(
                children: [
                  _buildReveal(order: 0, child: _buildTopNavBar()),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: _buildVideoCanvas(),
                      ),
                    ),
                  ),
                  _buildReveal(order: 1, child: _buildPlaybackControls()),
                  _buildScrollableToolBar(),
                ],
              ),
              if (_isToolSheetOpen)
                Positioned.fill(
                  bottom: 65,
                  child: EditorToolBottomSheet(
                    title: _activeToolLabel,
                    onDismiss: () => setState(() => _isToolSheetOpen = false),
                    child: KeyedSubtree(
                      key: ValueKey('studio-tool-$_activeTool'),
                      child: _buildActiveToolWorkspace(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String get _activeToolLabel {
    final tool = _tools.cast<Map<String, dynamic>>().firstWhere(
          (item) => item['id'] == _activeTool,
          orElse: () => {'label': _activeTool},
        );
    return tool['label'] as String;
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

  Widget _buildTopNavBar() {
    final presetParts = <String>[
      _selectedOutputRatioPreset,
      _duoBeatSyncEnabled ? 'Duo' : 'Solo',
      _kineticTextEnabled
          ? (_glitchTextStyleEnabled ? 'Kinetic+Glitch' : 'Kinetic')
          : 'No Kinetic',
      _autoDucking ? 'Ducker' : 'No Ducker',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const Expanded(
                child: Text(
                  'ClipSnap Studio Pro',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: _isExporting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.download_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                label: Text(
                  _isExporting
                      ? '${(_exportProgress * 100).toInt()}%'
                      : 'Export',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: _isExporting ? null : _exportVideoWithFFmpeg,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.center,
            child: SizedBox(
              width: double.infinity,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A26),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  'Preset: ${presetParts.join(' • ')}',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasActiveTemplateComposite {
    if (widget.templateAlreadyRendered) return false;
    final template = _activeTemplate;
    if (template == null) return false;
    final materialPath = template.materialAssetPath ?? template.overlayAssetPath;
    return materialPath != null && materialPath.isNotEmpty;
  }

  Widget _buildVideoCanvas() {
    final activeTemplate = _activeTemplate;
    final videoController = _videoController;

    if (widget.videoFile != null &&
        (videoController == null || !_isVideoInitialized)) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.cyanAccent),
      );
    }

    final previewMatrix = _hasActiveTemplateComposite
        ? const <double>[
            1,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ]
        : _buildComprehensiveMatrix();

    return Container(
      margin: const EdgeInsets.all(16),
      constraints: const BoxConstraints(maxWidth: 360, maxHeight: 640),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyanAccent, width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Transform.rotate(
          angle: _rotationQuarterTurns * (math.pi / 2),
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix(previewMatrix),
            child: Stack(
              alignment: Alignment.center,
              fit: StackFit.passthrough,
              children: [
            if (videoController != null && _isVideoInitialized)
              AspectRatio(
                aspectRatio: videoController.value.aspectRatio,
                child: VideoPlayer(videoController),
              )
            else
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.movie_creation_outlined,
                      color: Colors.white38,
                      size: 48,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'ClipSnap Engine Viewport',
                      style: TextStyle(color: Colors.white38),
                    ),
                  ],
                ),
              ),
            if (!widget.templateAlreadyRendered &&
              activeTemplate != null &&
                (activeTemplate.materialAssetPath ?? activeTemplate.overlayAssetPath) != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: _activeTemplateOverlayOpacity,
                    child: Image.asset(
                      (activeTemplate.materialAssetPath ??
                              activeTemplate.overlayAssetPath)!,
                      fit: BoxFit.fill,
                      color: _activeTemplateUsesScreenBlend
                          ? Colors.white
                          : null,
                      colorBlendMode: _activeTemplateUsesScreenBlend
                          ? BlendMode.screen
                          : null,
                    ),
                  ),
                ),
              ),
            if (activeTemplate?.id == 'retro_80s_vhs')
              const Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _VhsScanlinePainter()),
                ),
              ),
            if (_showStudioReferenceUi) _buildStudioAssetRail(),
            if (_showStudioReferenceUi && _activeTool == 'AI')
              _buildStudioMaskingCard(),
            if (_showStudioReferenceUi) _buildStudioNextButton(),
            if (_vignette > 0)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: RadialGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(
                          alpha: _vignette.clamp(0.0, 0.95),
                        ),
                      ],
                      stops: const [0.5, 1.0],
                    ),
                  ),
                ),
              ),
            ..._textLayers
                .where((layer) => layer['removed'] != true)
                .map((layer) => _buildDraggableText(layer)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _showStudioReferenceUi {
    final width = MediaQuery.of(context).size.width;
    return _activeTool == 'AI' && width >= 900;
  }

  void _applyStudioMaskPreset() {
    setState(() {
      _contrast = _studioRefineEdge ? 1.08 : 1.0;
      _saturation = _studioSmartTrack ? 1.05 : 1.0;
      _vignette = _studioInvertMask ? 0.34 : 0.18;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Mask updated: $_studioMaskTarget '
          '(${_studioRefineEdge ? 'Refine' : 'Soft'} / '
          '${_studioSmartTrack ? 'Track' : 'Static'} / '
          '${_studioInvertMask ? 'Inverted' : 'Normal'})',
        ),
      ),
    );
  }

  void _applyStudioSkyTone() {
    setState(() {
      if (_studioSkyPreset == 'Sunset') {
        _warmth = 0.2;
      } else if (_studioSkyPreset == 'Starry') {
        _warmth = -0.18;
      } else {
        _warmth = 0.04;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Applied $_studioSkyPreset sky tone preview.')),
    );
  }

  Future<void> _runStudioAiEnhance() async {
    if (_isStudioAiEnhancing) {
      return;
    }

    setState(() => _isStudioAiEnhancing = true);

    String quality;
    int bitrate;
    switch (_studioUpscalePreset) {
      case 'Ultra':
      case '8x':
        quality = '4K';
        bitrate = 26;
        break;
      case '4x':
        quality = '1440p';
        bitrate = 22;
        break;
      case '2x':
      default:
        quality = '1080p';
        bitrate = 16;
        break;
    }

    setState(() {
      _setSessionExportProfile(quality: quality, fps: 30, bitrateMbps: bitrate);
      _clarityBoostForAi();
    });

    _applyStudioSkyTone();

    if (!mounted) {
      return;
    }

    setState(() => _isStudioAiEnhancing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'AI Enhance ready: $_studioUpscalePreset + $_studioSkyPreset. Export profile set to $quality.',
        ),
      ),
    );
  }

  void _clarityBoostForAi() {
    _contrast = (_contrast + 0.06).clamp(0.5, 2.0);
    _saturation = (_saturation + 0.05).clamp(0.3, 2.0);
    _vignette = (_vignette + 0.04).clamp(0.0, 0.8);
  }

  Widget _buildStudioAssetRail() {
    return Positioned(
      left: 14,
      top: 14,
      child: Container(
        width: 170,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xE81E222D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pro Workflows',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const Text(
              'Creative Cloud Workflows (Assets)',
              style: TextStyle(color: Colors.white54, fontSize: 10),
            ),
            const SizedBox(height: 8),
            ...List.generate(3, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 60,
                    width: 160,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF334155).withValues(alpha: 0.95),
                          const Color(0xFF0F172A).withValues(alpha: 0.95),
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.photo_library_outlined,
                      color: Colors.white60,
                      size: 20,
                    ),
                  ),
                ),
              );
            }),
            const Text(
              'Heran track sentence',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(height: 4),
            const Text(
              'Moderane Images',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const Divider(color: Colors.white24),
            const Text(
              'Select a language',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudioMaskingCard() {
    return Positioned(
      left: 20,
      bottom: 20,
      child: Container(
        width: 310,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xE8262B36),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI-Powered Object Masking',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Intelligent mask generation for subjects, background, and objects',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _studioMaskChip('Subject'),
                _studioMaskChip('Background'),
                _studioMaskChip('Select Object'),
              ],
            ),
            const Divider(color: Colors.white12),
            Material(
              color: Colors.transparent,
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Refine Edge',
                    style: TextStyle(color: Colors.white)),
                value: _studioRefineEdge,
                onChanged: (v) {
                  setState(() => _studioRefineEdge = v);
                  _applyStudioMaskPreset();
                },
              ),
            ),
            Material(
              color: Colors.transparent,
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Smart Track',
                    style: TextStyle(color: Colors.white)),
                value: _studioSmartTrack,
                onChanged: (v) {
                  setState(() => _studioSmartTrack = v);
                  _applyStudioMaskPreset();
                },
              ),
            ),
            Material(
              color: Colors.transparent,
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Invert Mask',
                    style: TextStyle(color: Colors.white)),
                value: _studioInvertMask,
                onChanged: (v) {
                  setState(() => _studioInvertMask = v);
                  _applyStudioMaskPreset();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _studioMaskChip(String label) {
    final selected = _studioMaskTarget == label;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: const Color(0xFF3B6BC0),
      backgroundColor: const Color(0xFF2C3342),
      labelStyle: TextStyle(color: selected ? Colors.white : Colors.white70),
      onSelected: (_) {
        setState(() => _studioMaskTarget = label);
        _applyStudioMaskPreset();
      },
    );
  }

  Widget _buildStudioNextButton() {
    return Positioned(
      right: 14,
      bottom: 14,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF8DBDFF),
          foregroundColor: const Color(0xFF0A1931),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
        onPressed: _isExporting ? null : _exportVideoWithFFmpeg,
        child: const Text(
          'Next',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildPlaybackControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: const Color(0xFF0D0D14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                  color: const Color(0xFF2563EB),
                  size: 32,
                ),
                onPressed: _togglePlayback,
              ),
              Expanded(
                child: _isVideoInitialized && _videoController != null
                    ? _buildTimelineWithBeatMarkers()
                    : Container(height: 4, color: Colors.white10),
              ),
              IconButton(
                tooltip: _previewAudioMuted
                    ? 'Unmute preview audio'
                    : 'Mute preview audio',
                onPressed: () => _setPreviewAudioMuted(!_previewAudioMuted),
                icon: Icon(
                  _previewAudioMuted ? Icons.volume_off : Icons.volume_up,
                  color: _previewAudioMuted
                      ? const Color(0xFFFF6B6B)
                      : Colors.white70,
                  size: 20,
                ),
              ),
            ],
          ),
          if (_timelineAudioTrackPath != null) ...[
            const SizedBox(height: 4),
            _buildAudioTimelineTrack(),
          ],
          if (_beatMarkersMs.isNotEmpty) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: 28,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _beatMarkersMs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final beatMs = _beatMarkersMs[index];
                  return ActionChip(
                    label: Text(
                      _formatMs(beatMs),
                      style: const TextStyle(fontSize: 11),
                    ),
                    backgroundColor: const Color(0xFF1E1E2A),
                    side: const BorderSide(color: Color(0xFF2563EB)),
                    onPressed: () {
                      _videoController?.seekTo(Duration(milliseconds: beatMs));
                    },
                  );
                },
              ),
            ),
          ],
          if (_autoCutSegments.isNotEmpty) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Auto cut segments: ${_autoCutSegments.length}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimelineWithBeatMarkers() {
    final controller = _videoController;
    if (controller == null) {
      return Container(height: 4, color: Colors.white10);
    }

    final durationMs = controller.value.duration.inMilliseconds;
    if (durationMs <= 0) {
      return ThrottledVideoScrubber(
        controller: controller,
        playedColor: const Color(0xFF2563EB),
        bufferedColor: Colors.white24,
        backgroundColor: Colors.white10,
      );
    }

    return SizedBox(
      height: 16,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              ThrottledVideoScrubber(
                controller: controller,
                markerMs: _beatMarkersMs,
                playedColor: const Color(0xFF2563EB),
                bufferedColor: Colors.white24,
                backgroundColor: Colors.white10,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActiveToolWorkspace() {
    switch (_activeTool) {
      case 'Adjust':
        return Column(
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildSubToolChip('Brightness'),
                _buildSubToolChip('Contrast'),
                _buildSubToolChip('Saturation'),
                _buildSubToolChip('Warmth'),
              ],
            ),
            Expanded(
              child: Slider(
                value: _getAdjustValue(),
                min: _getAdjustMin(),
                max: _getAdjustMax(),
                activeColor: const Color(0xFF2563EB),
                onChanged: (val) => setState(() => _setAdjustValue(val)),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _launchAiObjectClone,
                icon: const Icon(Icons.auto_fix_high, size: 14),
                label: const Text('AI Object Clone (Pro)'),
              ),
            ),
          ],
        );

      case 'Ratio':
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildRatioChip('9:16 (Shorts/TikTok)', 0.5625, '9:16'),
                  _buildRatioChip('1:1 (Square)', 1.0, '1:1'),
                  _buildRatioChip('16:9 (YouTube)', 1.777, '16:9'),
                  _buildRatioChip('4:5 (Portrait)', 0.8, '4:5'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Output reframing preset: $_selectedOutputRatioPreset',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        );

      case 'Speed':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Playback Speed: ${_playbackSpeed.toStringAsFixed(2)}x',
              style: const TextStyle(color: Colors.white70),
            ),
            Slider(
              value: _playbackSpeed,
              min: 0.25,
              max: 3.0,
              divisions: 11,
              activeColor: const Color(0xFF2563EB),
              onChanged: (val) {
                setState(() => _playbackSpeed = val);
                _videoController?.setPlaybackSpeed(val);
              },
            ),
          ],
        );

      case 'AI':
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
              ),
              onPressed: () => setState(() => _activeTool = 'Audio'),
              icon: const Icon(Icons.graphic_eq, color: Colors.white),
              label: const Text(
                'Open AI Audio Clean',
                style: TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1B1F2A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AI-Powered Object Masking',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Intelligent mask generation for subjects, background, and objects',
                    style: TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: ['Subject', 'Background', 'Select Object']
                        .map((target) {
                      final selected = _studioMaskTarget == target;
                      return ChoiceChip(
                        label: Text(target),
                        selected: selected,
                        selectedColor: const Color(0xFF355EA1),
                        backgroundColor: const Color(0xFF2A3040),
                        labelStyle: TextStyle(
                          color: selected ? Colors.white : Colors.white70,
                          fontSize: 11,
                        ),
                        onSelected: (_) {
                          setState(() => _studioMaskTarget = target);
                          _applyStudioMaskPreset();
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 6),
                  Material(
                    color: Colors.transparent,
                    child: SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      visualDensity: const VisualDensity(vertical: -4),
                      title: const Text('Refine Edge',
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                      value: _studioRefineEdge,
                      onChanged: (v) {
                        setState(() => _studioRefineEdge = v);
                        _applyStudioMaskPreset();
                      },
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      visualDensity: const VisualDensity(vertical: -4),
                      title: const Text('Smart Track',
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                      value: _studioSmartTrack,
                      onChanged: (v) {
                        setState(() => _studioSmartTrack = v);
                        _applyStudioMaskPreset();
                      },
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      visualDensity: const VisualDensity(vertical: -4),
                      title: const Text('Invert Mask',
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                      value: _studioInvertMask,
                      onChanged: (v) {
                        setState(() => _studioInvertMask = v);
                        _applyStudioMaskPreset();
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1B1F2A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quick Features',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'AI Upscaling & Detail Recovery',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: ['2x', '4x', '8x', 'Ultra'].map((preset) {
                      final selected = _studioUpscalePreset == preset;
                      return ChoiceChip(
                        label: Text(preset),
                        selected: selected,
                        selectedColor: const Color(0xFF4D78C7),
                        backgroundColor: const Color(0xFF2A3040),
                        labelStyle: TextStyle(
                          color: selected ? Colors.white : Colors.white70,
                        ),
                        onSelected: (_) =>
                            setState(() => _studioUpscalePreset = preset),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Smart Sky Replacement',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: ['Sunny', 'Sunset', 'Starry'].map((preset) {
                      final selected = _studioSkyPreset == preset;
                      return ChoiceChip(
                        label: Text(preset),
                        selected: selected,
                        selectedColor: const Color(0xFF4D78C7),
                        backgroundColor: const Color(0xFF2A3040),
                        labelStyle: TextStyle(
                          color: selected ? Colors.white : Colors.white70,
                        ),
                        onSelected: (_) =>
                            setState(() => _studioSkyPreset = preset),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _applyStudioMaskPreset,
                          child: const Text('Apply Mask'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _applyStudioSkyTone,
                          child: const Text('Apply Sky'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8DBDFF),
                  foregroundColor: const Color(0xFF0A1931),
                ),
                onPressed: _isStudioAiEnhancing ? null : _runStudioAiEnhance,
                icon: _isStudioAiEnhancing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  _isStudioAiEnhancing ? 'Enhancing...' : 'AI Enhance',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        );

      case 'Audio':
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildAudioCategoryTabs(),
            const SizedBox(height: 8),
            if (_audioToolCategory == 'Audio') ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isExtractingAudio
                        ? null
                        : _extractAudioFromPickedVideo,
                    icon: _isExtractingAudio
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.audio_file_outlined),
                    label: Text(
                      _isExtractingAudio
                          ? 'Extracting...'
                          : 'Extract Audio from Video',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: widget.videoFile == null || _isExtractingAudio
                        ? null
                        : _detachCurrentVideoAudio,
                    icon: const Icon(Icons.call_split),
                    label: const Text('Detach Audio'),
                  ),
                ],
              ),
              Material(
                color: Colors.transparent,
                child: SwitchListTile.adaptive(
                  key: const ValueKey('original-audio-mute-toggle'),
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -3),
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Mute Original Video Audio',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  secondary: Icon(
                    _originalAudioMuted ? Icons.volume_off : Icons.volume_up,
                    color: Colors.white70,
                  ),
                  value: _originalAudioMuted,
                  activeThumbColor: const Color(0xFF2563EB),
                  onChanged: _setOriginalAudioMuted,
                ),
              ),
              if (_timelineAudioTrackPath != null) ...[
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Timeline Audio',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  subtitle: Text(
                    _shortPath(_timelineAudioTrackPath!),
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      TextButton.icon(
                        onPressed: _replaceTimelineAudio,
                        icon: const Icon(Icons.swap_horiz, size: 18),
                        label: const Text('Replace'),
                      ),
                      IconButton(
                        tooltip: 'Remove audio track',
                        onPressed: _removeTimelineAudio,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Trim selected segment',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                RangeSlider(
                  key: const ValueKey('audio-trim-range'),
                  values: RangeValues(
                    _audioSegments[_selectedAudioSegment].start,
                    _audioSegments[_selectedAudioSegment].end,
                  ),
                  min: 0,
                  max: 1,
                  divisions: 100,
                  labels: RangeLabels(
                    '${(_audioSegments[_selectedAudioSegment].start * 100).round()}%',
                    '${(_audioSegments[_selectedAudioSegment].end * 100).round()}%',
                  ),
                  onChanged: _trimSelectedAudioSegment,
                ),
                Row(
                  children: [
                    const Icon(Icons.volume_down, color: Colors.white54),
                    Expanded(
                      child: Slider(
                        key: const ValueKey('timeline-audio-volume'),
                        value: _timelineAudioVolume,
                        min: 0,
                        max: 1.5,
                        divisions: 30,
                        label: '${(_timelineAudioVolume * 100).round()}%',
                        onChanged: (value) {
                          setState(() => _timelineAudioVolume = value);
                          unawaited(
                            _timelineAudioPlayer.setVolume(
                              _previewAudioMuted ? 0 : value,
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text(
                        '${(_timelineAudioVolume * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _buildAudioEffectSlider(
                        label: 'Fade In',
                        value: _audioFadeInSeconds,
                        onChanged: (value) =>
                            setState(() => _audioFadeInSeconds = value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildAudioEffectSlider(
                        label: 'Fade Out',
                        value: _audioFadeOutSeconds,
                        onChanged: (value) =>
                            setState(() => _audioFadeOutSeconds = value),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _splitAudioAtPlayhead,
                        icon: const Icon(Icons.content_cut, size: 18),
                        label: const Text('Split at Playhead'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Delete selected segment',
                      onPressed: _deleteSelectedAudioSegment,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
              ],
            ],
            if (_audioToolCategory == 'Voice') ...[
              Material(
                color: Colors.transparent,
                child: SwitchListTile(
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -3),
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'AI Auto-Ducking',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  value: _autoDucking,
                  activeThumbColor: const Color(0xFF2563EB),
                  onChanged: (v) {
                    if (!v) {
                      setState(() {
                        _autoDucking = false;
                        _audioDuckerProEnabled = false;
                      });
                      return;
                    }
                    _enableAudioDuckerPro();
                  },
                ),
              ),
              Material(
                color: Colors.transparent,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Voiceover Track',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  subtitle: Text(
                    _voiceoverTrackPath == null
                        ? 'Not selected'
                        : _shortPath(_voiceoverTrackPath!),
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      TextButton(
                        onPressed: _isGeneratingVoiceover
                            ? null
                            : _generateAiVoiceoverTrack,
                        child: Text(
                          _isGeneratingVoiceover
                              ? 'Generating...'
                              : 'AI Generate',
                        ),
                      ),
                      TextButton(
                        onPressed: _pickVoiceoverTrack,
                        child: const Text('Select'),
                      ),
                    ],
                  ),
                ),
              ),
              if (_autoDucking || _musicTrackPath != null) ...[
                Material(
                  color: Colors.transparent,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Music Track',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    subtitle: Text(
                      _musicTrackPath == null
                          ? 'Not selected'
                          : _shortPath(_musicTrackPath!),
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    trailing: TextButton(
                      onPressed: _pickMusicTrack,
                      child: const Text('Select'),
                    ),
                  ),
                ),
              ],
              Material(
                color: Colors.transparent,
                child: SwitchListTile(
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -3),
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Studio Sound (Voice Isolation)',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  value: _noiseReduction,
                  activeThumbColor: const Color(0xFF2563EB),
                  onChanged: (v) => setState(() => _noiseReduction = v),
                ),
              ),
            ],
            if (_audioToolCategory == 'Editing') ...[
              SwitchListTile.adaptive(
                dense: true,
                visualDensity: const VisualDensity(vertical: -3),
                contentPadding: EdgeInsets.zero,
                activeThumbColor: const Color(0xFF2563EB),
                title: const Text(
                  'Silence + Filler Cleanup',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
                subtitle: const Text(
                  'Remove dead air and filler words from transcript',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                value: _silenceFillerCleanupEnabled,
                onChanged: (v) =>
                    setState(() => _silenceFillerCleanupEnabled = v),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                ),
                onPressed: _optimizeSpeechTrack,
                icon: const Icon(Icons.auto_fix_high, color: Colors.white),
                label: const Text(
                  'Remove Silence & Filler Words',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                ),
                onPressed: _isAnalyzingBeats ? null : _analyzeBeatSync,
                icon: _isAnalyzingBeats
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.graphic_eq, color: Colors.white),
                label: Text(
                  _isAnalyzingBeats
                      ? 'Detecting beats...'
                      : 'Analyze Auto Beat-Sync',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              SwitchListTile.adaptive(
                dense: true,
                visualDensity: const VisualDensity(vertical: -3),
                contentPadding: EdgeInsets.zero,
                activeThumbColor: const Color(0xFF2563EB),
                title: const Text(
                  'Auto Cut At Beats',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
                subtitle: Text(
                  _autoCutSegments.isEmpty
                      ? 'Analyze beats first to create cut segments'
                      : '${_autoCutSegments.length} segments ready for export',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                value: _autoCutAtBeatsEnabled,
                onChanged: (v) => setState(() => _autoCutAtBeatsEnabled = v),
              ),
              if (_beatMarkersMs.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _generateAutoCutSegments,
                    icon: const Icon(Icons.cut, size: 14),
                    label: const Text('Generate cut segments from beats'),
                  ),
                ),
              if (_beatMarkersMs.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      _beatMarkersMs = [];
                      _autoCutSegments = [];
                      _autoCutAtBeatsEnabled = false;
                    }),
                    icon: const Icon(Icons.clear, size: 14),
                    label: const Text('Clear beat markers'),
                  ),
                ),
              if (_textLayers.any((layer) => layer['isCaption'] == true))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      _activeTool = 'Transcript';
                      _isToolSheetOpen = true;
                    }),
                    icon: const Icon(Icons.subject, size: 14),
                    label: const Text('Edit transcript text'),
                  ),
                ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: MonetizationService.instance.startProPurchaseFlow,
                icon: const Icon(Icons.workspace_premium, size: 16),
                label: const Text('Unlock ClipSnap Pro (No Ads + HD exports)'),
              ),
            ),
          ],
        );

      case 'Captions':
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
              ),
              icon: _isGeneratingCaptions
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.auto_awesome, color: Colors.white),
              label: Text(
                _isGeneratingCaptions
                    ? 'Generating...'
                    : 'Auto-Generate Dynamic Captions',
                style: const TextStyle(color: Colors.white),
              ),
              onPressed: _isGeneratingCaptions ? null : _generateCaptionsWithAi,
            ),
            SwitchListTile.adaptive(
              dense: true,
              visualDensity: const VisualDensity(vertical: -3),
              contentPadding: EdgeInsets.zero,
              activeThumbColor: const Color(0xFF2563EB),
              title: const Text(
                'Dynamic Word Highlight',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
              subtitle: const Text(
                'Animate words like short-form social captions',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              value: _dynamicCaptionsEnabled,
              onChanged: (value) {
                setState(() => _dynamicCaptionsEnabled = value);
                _persistCaptionPreferences();
              },
            ),
            Wrap(
              spacing: 8,
              children: ['Classic', 'Karaoke', 'Neon'].map((style) {
                final selected = _captionStylePreset == style;
                return ChoiceChip(
                  label: Text(style),
                  selected: selected,
                  selectedColor: const Color(0xFF2563EB),
                  backgroundColor: const Color(0xFF1E1E2A),
                  labelStyle: TextStyle(
                      color: selected ? Colors.white : Colors.white70),
                  onSelected: (_) {
                    setState(() => _captionStylePreset = style);
                    _persistCaptionPreferences();
                  },
                );
              }).toList(),
            ),
            SwitchListTile.adaptive(
              dense: true,
              visualDensity: const VisualDensity(vertical: -3),
              contentPadding: EdgeInsets.zero,
              activeThumbColor: const Color(0xFF2563EB),
              title: const Text(
                'Kinetic Text Overlay',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
              subtitle: const Text(
                'Render timed drawtext overlays at export',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              value: _kineticTextEnabled,
              onChanged: (value) => setState(() => _kineticTextEnabled = value),
            ),
            SwitchListTile.adaptive(
              dense: true,
              visualDensity: const VisualDensity(vertical: -3),
              contentPadding: EdgeInsets.zero,
              activeThumbColor: const Color(0xFF2563EB),
              title: const Text(
                'Glitch Text Effect',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
              subtitle: const Text(
                'Adds alpha flicker and jitter to kinetic captions',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              value: _glitchTextStyleEnabled,
              onChanged: (value) =>
                  setState(() => _glitchTextStyleEnabled = value),
            ),
          ],
        );

      case 'Transcript':
        final transcriptLayers =
            _textLayers.where((layer) => layer['isCaption'] == true).toList();
        final removedCount =
            transcriptLayers.where((layer) => layer['removed'] == true).length;
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
              ),
              onPressed: _silenceFillerCleanupEnabled
                  ? _optimizeSpeechTrack
                  : _applyTranscriptRippleCut,
              icon: const Icon(Icons.content_cut, color: Colors.white),
              label: Text(
                _silenceFillerCleanupEnabled
                    ? 'Clean silence + filler words'
                    : 'Apply transcript ripple cut',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            Text(
              'Transcript segments: ${transcriptLayers.length} • Removed: $removedCount',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 8),
            ...transcriptLayers.asMap().entries.map((entry) {
              final index = entry.key;
              final layer = entry.value;
              final removed = layer['removed'] == true;
              final label = layer['text'] as String;
              final startMs = layer['startMs'] as int? ?? 0;
              return Card(
                color:
                    removed ? const Color(0xFF26202A) : const Color(0xFF1B1B24),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  title: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: removed ? Colors.white38 : Colors.white,
                      decoration: removed
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                  subtitle: Text(
                    _formatMs(startMs),
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      removed ? Icons.restore : Icons.delete_outline,
                      color: removed ? Colors.greenAccent : Colors.redAccent,
                    ),
                    onPressed: () => _toggleTranscriptRemoval(index),
                  ),
                  onTap: () => _seekToTranscriptLayer(layer),
                ),
              );
            }),
            if (transcriptLayers.isEmpty)
              const Text(
                'Generate captions first to edit transcript text.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
          ],
        );

      case 'BRoll':
        final transcriptLayers = _textLayers
            .where((layer) =>
                layer['isCaption'] == true && layer['removed'] != true)
            .toList();
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
              ),
              onPressed:
                  transcriptLayers.isEmpty ? null : _generateBRollSuggestions,
              icon: const Icon(Icons.auto_awesome, color: Colors.white),
              label: const Text(
                'Suggest AI B-Roll',
                style: TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _bRollSuggestions.isEmpty
                  ? 'Scan captions to find matching stock footage or sticker prompts.'
                  : 'Suggested shots: ${_bRollSuggestions.length}',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 8),
            ..._bRollSuggestions.map((suggestion) {
              return Card(
                color: const Color(0xFF1B1B24),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  dense: true,
                  title: Text(
                    '${suggestion.category}: ${suggestion.keyword}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    '${_formatMs(suggestion.startMs)} • ${suggestion.stockQuery}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.add_photo_alternate,
                      color: Color(0xFF2563EB),
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Added B-roll prompt: ${suggestion.overlayPrompt}',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            }),
            if (_bRollSuggestions.isEmpty)
              const Text(
                'Generate captions first, then run B-roll suggestion.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
          ],
        );

      case 'Duo':
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            Material(
              color: Colors.transparent,
              child: SwitchListTile.adaptive(
                dense: true,
                visualDensity: const VisualDensity(vertical: -3),
                contentPadding: EdgeInsets.zero,
                activeThumbColor: const Color(0xFF2563EB),
                title: const Text(
                  'Enable Duo Beat-Sync',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
                subtitle: const Text(
                  'Concatenate Creator A + B and sync to beat track',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                value: _duoBeatSyncEnabled,
                onChanged: (value) =>
                    setState(() => _duoBeatSyncEnabled = value),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Creator B Video',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
                subtitle: Text(
                  _duoCreator2VideoPath == null
                      ? 'Not selected'
                      : _shortPath(_duoCreator2VideoPath!),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                trailing: TextButton(
                  onPressed: _pickDuoCreator2Video,
                  child: const Text('Select'),
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Beat Track',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
                subtitle: Text(
                  _duoAudioTrackPath == null
                      ? 'Not selected'
                      : _shortPath(_duoAudioTrackPath!),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                trailing: TextButton(
                  onPressed: _pickDuoAudioTrack,
                  child: const Text('Select'),
                ),
              ),
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
              activeColor: const Color(0xFF2563EB),
              onChanged: (val) => setState(() => _vignette = val),
            ),
          ],
        );

      case 'Reset':
        return Center(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.restore, color: Colors.white),
            label: const Text(
              'Reset All Settings',
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

  Widget _buildAudioCategoryTabs() {
    const categories = [
      ('Audio', Icons.graphic_eq),
      ('Editing', Icons.content_cut),
      ('Voice', Icons.record_voice_over_outlined),
    ];
    return Row(
      key: const ValueKey('audio-category-tabs'),
      children: categories.map((category) {
        final selected = _audioToolCategory == category.$1;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: TextButton.icon(
              onPressed: () => setState(() => _audioToolCategory = category.$1),
              style: TextButton.styleFrom(
                foregroundColor:
                    selected ? Colors.white : const Color(0xFF9CA3B8),
                backgroundColor:
                    selected ? const Color(0xFF2563EB) : Colors.white10,
                padding: const EdgeInsets.symmetric(vertical: 9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: Icon(category.$2, size: 16),
              label: Text(
                category.$1,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildScrollableToolBar() {
    return Container(
      height: 72,
      color: const Color(0xFF111118),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        scrollDirection: Axis.horizontal,
        itemCount: _tools.length,
        itemBuilder: (context, index) {
          final tool = _tools[index];
          final isSelected = _activeTool == tool['id'];
          final isAi = tool['id'] == 'AI';
          final accent =
              isAi ? const Color(0xFFDA7DFF) : const Color(0xFF6EDCFF);

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _activeTool = tool['id'] as String;
                    _isToolSheetOpen = true;
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  key: ValueKey('editor-tool-tile-${tool['id']}'),
                  duration: MotionSpec.selectionDuration,
                  curve: MotionSpec.emphasisCurve,
                  width: 88,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accent.withValues(alpha: 0.10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? accent.withValues(alpha: 0.32)
                          : Colors.transparent,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.14),
                              blurRadius: 12,
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 30,
                        height: 24,
                        child: Stack(
                          children: [
                            Center(
                              child: isAi
                                  ? ShaderMask(
                                      shaderCallback: (bounds) =>
                                          const LinearGradient(
                                        colors: [
                                          Color(0xFFFF72C6),
                                          Color(0xFF63D8FF),
                                        ],
                                      ).createShader(bounds),
                                      child: Icon(
                                        tool['icon'] as IconData,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                    )
                                  : Icon(
                                      tool['icon'] as IconData,
                                      color:
                                          isSelected ? accent : Colors.white70,
                                      size: 22,
                                    ),
                            ),
                            if (isAi)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  width: 5,
                                  height: 5,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF63D8FF),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 5),
                      Flexible(
                        child: Text(
                          tool['label'] as String,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected || isAi ? accent : Colors.white60,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
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
    final c = _contrast;
    final s = _saturation;
    final w = _warmth * 40;

    return [
      (c * s) + (w > 0 ? w / 100 : 0),
      0,
      0,
      0,
      b + w,
      0,
      c * s,
      0,
      0,
      b,
      0,
      0,
      (c * s) - (w < 0 ? w / 100 : 0),
      0,
      b - w,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  Future<void> _exportVideoWithFFmpeg() async {
    final inputFile = widget.videoFile;
    if (inputFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No input video loaded to render.')),
      );
      return;
    }

    setState(() {
      _isExporting = true;
      _exportProgress = 0.1;
    });
    ExportStatusService.instance.start(
      'Exporting ${_shortPath(inputFile.path)}',
    );

    final appDir = await getApplicationDocumentsDirectory();
    final outputPath =
        '${appDir.path}/ClipSnap_Export_${DateTime.now().millisecondsSinceEpoch}.mp4';

    final prefs = await SharedPreferences.getInstance();
    final exportQuality = _sessionExportQuality ??
        prefs.getString(_settingsExportQualityKey) ??
        '1080p';
    final exportFps =
        _sessionExportFps ?? prefs.getInt(_settingsExportFpsKey) ?? 30;
    final exportBitrateMbps = _sessionExportBitrateMbps ??
        prefs.getInt(_settingsExportBitrateKey) ??
        12;
    final brandWatermarkEnabled =
        prefs.getBool(_settingsBrandWatermarkKey) ?? false;
    final brandWatermarkText =
        prefs.getString(_settingsBrandWatermarkTextKey)?.trim().isNotEmpty ==
                true
            ? prefs.getString(_settingsBrandWatermarkTextKey)!.trim()
            : 'ClipSnap';
    final brandAccentColorValue =
        prefs.getInt(_settingsBrandAccentColorKey) ?? 0xFF6366F1;
    final brandEndScreenText =
        prefs.getString(_settingsBrandEndScreenTextKey)?.trim().isNotEmpty ==
                true
            ? prefs.getString(_settingsBrandEndScreenTextKey)!.trim()
            : 'Follow for more';
    final brandLutPath = prefs.getString(_settingsBrandLutPathKey);
    final duoRequested = _duoBeatSyncEnabled &&
        _duoCreator2VideoPath != null &&
        _duoAudioTrackPath != null;

    if (duoRequested) {
      final result = await renderDuoBeatSync(
        creator1Path: inputFile.path,
        creator2Path: _duoCreator2VideoPath!,
        audioTrackPath: _duoAudioTrackPath!,
        outputPath: outputPath,
      );

      if (!mounted) {
        return;
      }
      final savedToGallery = result
          ? await _saveExportToGalleryAfterInterstitial(outputPath)
          : false;
      if (!mounted) {
        return;
      }
      setState(() {
        _isExporting = false;
        _exportProgress = result ? 1.0 : 0.0;
      });
      ExportStatusService.instance.finish(success: result);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result
              ? savedToGallery
                ? 'Duo beat-sync video saved to Gallery.'
                : 'Duo beat-sync export complete, but gallery save failed.'
                : 'Duo beat-sync export failed.',
          ),
        ),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    final unlockedLut = brandLutPath == null || brandLutPath.isEmpty
        ? true
        : await MonetizationService.instance.unlockProFeatureGate(
            context,
            featureName: 'Advanced LUTs',
          );
    if (!mounted) {
      return;
    }

    String scaleClause = '';
    if (exportQuality == '720p') {
      scaleClause = ',scale=-2:720';
    } else if (exportQuality == '1080p') {
      scaleClause = ',scale=-2:1080';
    } else if (exportQuality == '4K') {
      scaleClause = ',scale=3840:2160';
    }

    final lutClause =
        (unlockedLut && brandLutPath != null && brandLutPath.isNotEmpty)
            ? ',lut3d=file=${_escapeFilterPath(brandLutPath)}'
            : '';
    final aspectReframeClause =
        ',${_buildReframeFilterForPreset(_selectedOutputRatioPreset)}';
    final kineticOverlayFilter =
        _kineticTextEnabled ? _buildKineticTextFilter() : '';

    var filterGraph =
        'eq=brightness=$_brightness:contrast=$_contrast:saturation=$_saturation$scaleClause$lutClause$aspectReframeClause';
    final transcriptSegments = _buildTranscriptSegments();
    final shouldUseTranscriptRipple =
        _removedTranscriptIndexes.isNotEmpty && transcriptSegments.isNotEmpty;

    if (_playbackSpeed != 1.0 &&
        !_autoCutAtBeatsEnabled &&
        !shouldUseTranscriptRipple) {
      filterGraph += ',setpts=${1 / _playbackSpeed}*PTS';
    }

    var audioFilterGraph = '';
    if (_noiseReduction) {
      audioFilterGraph =
          'highpass=f=80,lowpass=f=12000,afftdn=dB=-25,dynaudnorm=f=150:g=15';
    }

    final targetFps = [24, 30, 60].contains(exportFps) ? exportFps : 30;
    final targetBitrate = exportBitrateMbps.clamp(6, 50);

    final shouldAutoCut = _autoCutAtBeatsEnabled && _autoCutSegments.isNotEmpty;
    final videoOutputLabel = brandWatermarkEnabled ? '[outv_brand]' : '[outv]';
    final activeTemplate = _activeTemplate;
    final templateAssetPath = activeTemplate?.materialAssetPath ??
        activeTemplate?.overlayAssetPath;

    String ffmpegCommand;
    if (!widget.templateAlreadyRendered &&
      activeTemplate != null &&
        templateAssetPath != null &&
        templateAssetPath.isNotEmpty) {
      final templateGraph = activeTemplate.buildFilterGraph(
        overlayAssetPath: templateAssetPath,
      );
      ffmpegCommand =
          '-y -i "${inputFile.path}" -loop 1 -i "${_escapePathArg(templateAssetPath)}" '
          '-filter_complex "$templateGraph" -map "[v]" -map 0:a? -r $targetFps '
          '-c:v libx264 -preset medium -b:v ${targetBitrate}M -maxrate ${targetBitrate}M '
          '-bufsize ${targetBitrate * 2}M -c:a aac -movflags +faststart "$outputPath"';
    } else if (shouldAutoCut) {
      var filterComplex = _buildAutoCutFilterComplex(filterGraph);
      filterComplex = _appendKineticTextToFilterComplex(
        filterComplex,
        kineticOverlayFilter,
      );
      filterComplex = _appendBrandWatermarkToFilterComplex(
        filterComplex,
        brandWatermarkEnabled: brandWatermarkEnabled,
        watermarkText: brandWatermarkText,
        watermarkColorValue: brandAccentColorValue,
        endScreenText: brandEndScreenText,
      );
      ffmpegCommand =
          '-y -i "${inputFile.path}" -filter_complex "$filterComplex" '
          '-map "$videoOutputLabel" -map "[outa]" -r $targetFps '
          '-c:v libx264 -preset medium -b:v ${targetBitrate}M -maxrate ${targetBitrate}M '
          '-bufsize ${targetBitrate * 2}M -c:a aac -movflags +faststart "$outputPath"';
    } else if (shouldUseTranscriptRipple) {
      var filterComplex = _buildTranscriptRippleFilterComplex(
        videoFilter: filterGraph,
        audioFilter: audioFilterGraph,
        transcriptSegments: transcriptSegments,
      );
      filterComplex = _appendKineticTextToFilterComplex(
        filterComplex,
        kineticOverlayFilter,
      );
      filterComplex = _appendBrandWatermarkToFilterComplex(
        filterComplex,
        brandWatermarkEnabled: brandWatermarkEnabled,
        watermarkText: brandWatermarkText,
        watermarkColorValue: brandAccentColorValue,
        endScreenText: brandEndScreenText,
      );
      ffmpegCommand =
          '-y -i "${inputFile.path}" -filter_complex "$filterComplex" '
          '-map "$videoOutputLabel" -map "[outa]" -r $targetFps '
          '-c:v libx264 -preset medium -b:v ${targetBitrate}M -maxrate ${targetBitrate}M '
          '-bufsize ${targetBitrate * 2}M -c:a aac -movflags +faststart "$outputPath"';
    } else {
      final watermarkFilter = _buildBrandWatermarkFilter(
        watermarkText: brandWatermarkText,
        watermarkColorValue: brandAccentColorValue,
        endScreenText: brandEndScreenText,
      );
      final kineticClause =
          kineticOverlayFilter.isEmpty ? '' : ',$kineticOverlayFilter';
      final finalFilterGraph = watermarkFilter.isEmpty
          ? '$filterGraph$kineticClause'
          : '$filterGraph$kineticClause,$watermarkFilter';

      if (_timelineAudioTrackPath != null && _audioSegments.isNotEmpty) {
        final durationSeconds = _videoDurationSeconds;
        final timelineFilters = <String>[];
        final timelineLabels = <String>[];
        for (var index = 0; index < _audioSegments.length; index++) {
          final segment = _audioSegments[index];
          final start = segment.start * durationSeconds;
          final end = segment.end * durationSeconds;
          final segmentDuration = end - start;
          final fadeIn = math.min(_audioFadeInSeconds, segmentDuration / 2);
          final fadeOut = math.min(_audioFadeOutSeconds, segmentDuration / 2);
          final delayMs = (start * 1000).round();
          final fadeInFilter = fadeIn > 0
              ? ',afade=t=in:st=0:d=${fadeIn.toStringAsFixed(3)}'
              : '';
          final fadeOutFilter = fadeOut > 0
              ? ',afade=t=out:st=${(segmentDuration - fadeOut).toStringAsFixed(3)}:d=${fadeOut.toStringAsFixed(3)}'
              : '';
          timelineFilters.add(
            '[1:a]atrim=start=${start.toStringAsFixed(3)}:end=${end.toStringAsFixed(3)},'
            'asetpts=PTS-STARTPTS,volume=${_timelineAudioVolume.toStringAsFixed(2)}'
            '$fadeInFilter$fadeOutFilter,'
            'adelay=$delayMs|$delayMs[track$index]',
          );
          timelineLabels.add('[track$index]');
        }
        final combinedTimeline = _audioSegments.length == 1
            ? '${timelineLabels.single}anull[timeline]'
            : '${timelineLabels.join()}amix=inputs=${timelineLabels.length}:duration=longest[timeline]';
        final originalAudio = audioFilterGraph.isEmpty
            ? '[0:a]anull[original]'
            : '[0:a]$audioFilterGraph[original]';
        final audioMix = _originalAudioMuted
            ? '[timeline]apad[aout]'
            : '$originalAudio;[original][timeline]amix=inputs=2:duration=first[aout]';
        final filterComplex = '[0:v]$finalFilterGraph[outv];'
            '${timelineFilters.join(';')};$combinedTimeline;$audioMix';
        ffmpegCommand =
            '-y -i "${inputFile.path}" -i "${_escapePathArg(_timelineAudioTrackPath!)}" '
            '-filter_complex "$filterComplex" -map "[outv]" -map "[aout]" -shortest -r $targetFps '
            '-c:v libx264 -preset medium -b:v ${targetBitrate}M -maxrate ${targetBitrate}M '
            '-bufsize ${targetBitrate * 2}M -c:a aac -movflags +faststart "$outputPath"';
      } else if (_originalAudioMuted) {
        ffmpegCommand =
            '-y -i "${inputFile.path}" -vf "$finalFilterGraph" -an -r $targetFps '
            '-c:v libx264 -preset medium -b:v ${targetBitrate}M -maxrate ${targetBitrate}M '
            '-bufsize ${targetBitrate * 2}M -movflags +faststart "$outputPath"';
      } else if (_autoDucking &&
          _audioDuckerProEnabled &&
          _voiceoverTrackPath != null &&
          _musicTrackPath != null) {
        final voiceBase = audioFilterGraph.isEmpty
            ? '[1:a]anull[voice]'
            : '[1:a]$audioFilterGraph[voice]';
        final filterComplex = '[0:v]$finalFilterGraph[outv];'
            '$voiceBase;'
            '[2:a][voice]sidechaincompress=threshold=0.08:ratio=4:attack=20:release=300[bg_music];'
            '[voice][bg_music]amix=inputs=2:duration=first[aout]';
        ffmpegCommand =
            '-y -i "${inputFile.path}" -i "${_voiceoverTrackPath!}" -i "${_musicTrackPath!}" '
            '-filter_complex "$filterComplex" -map "[outv]" -map "[aout]" -shortest -r $targetFps '
            '-c:v libx264 -preset medium -b:v ${targetBitrate}M -maxrate ${targetBitrate}M '
            '-bufsize ${targetBitrate * 2}M -c:a aac -movflags +faststart "$outputPath"';
      } else {
        final audioFlags =
            audioFilterGraph.isNotEmpty ? ' -af "$audioFilterGraph"' : '';
        ffmpegCommand =
            '-y -i "${inputFile.path}" -vf "$finalFilterGraph"$audioFlags -r $targetFps '
            '-c:v libx264 -preset medium -b:v ${targetBitrate}M -maxrate ${targetBitrate}M '
            '-bufsize ${targetBitrate * 2}M -c:a aac -movflags +faststart "$outputPath"';
      }
    }

    final primaryRun = await _runExportCommand(ffmpegCommand);
    if (primaryRun.success) {
      final savedToGallery = await _saveExportToGalleryAfterInterstitial(
        outputPath,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isExporting = false;
        _exportProgress = 1.0;
      });
      ExportStatusService.instance.finish(success: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            savedToGallery
                ? 'Video saved to Gallery successfully!'
                : 'Export complete, but gallery save failed.',
          ),
        ),
      );
      return;
    }

    // Compatibility mode keeps the chosen audio source even if effects fail.
    final String fallbackCommand;
    if (_timelineAudioTrackPath != null) {
      final audioInput = '-i "${_escapePathArg(_timelineAudioTrackPath!)}"';
      final audioMapping = _originalAudioMuted
          ? '-map 0:v:0 -map 1:a:0'
          : '-filter_complex "[0:a][1:a]amix=inputs=2:duration=first[aout]" '
              '-map 0:v:0 -map "[aout]"';
      fallbackCommand = '-y -i "${inputFile.path}" $audioInput $audioMapping '
          '-shortest -r $targetFps -c:v libx264 -preset medium '
          '-b:v ${targetBitrate}M -maxrate ${targetBitrate}M '
          '-bufsize ${targetBitrate * 2}M -c:a aac -movflags +faststart "$outputPath"';
    } else if (_originalAudioMuted) {
      fallbackCommand = '-y -i "${inputFile.path}" -map 0:v:0 -an '
          '-r $targetFps -c:v libx264 -preset medium '
          '-b:v ${targetBitrate}M -maxrate ${targetBitrate}M '
          '-bufsize ${targetBitrate * 2}M -movflags +faststart "$outputPath"';
    } else {
      fallbackCommand = '-y -i "${inputFile.path}" '
          '-map 0:v:0 -map 0:a? -r $targetFps '
          '-c:v libx264 -preset medium -b:v ${targetBitrate}M '
          '-maxrate ${targetBitrate}M -bufsize ${targetBitrate * 2}M '
          '-c:a aac -movflags +faststart "$outputPath"';
    }

    final fallbackRun = await _runExportCommand(fallbackCommand);

    if (!mounted) {
      return;
    }

    if (fallbackRun.success) {
      final savedToGallery = await _saveExportToGalleryAfterInterstitial(
        outputPath,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isExporting = false;
        _exportProgress = 1.0;
      });
      ExportStatusService.instance.finish(success: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            savedToGallery
                ? 'Video saved to Gallery (compatibility mode).'
                : 'Export completed, but gallery save failed.',
          ),
        ),
      );
      return;
    }

    final copyFallbackCommand = _originalAudioMuted
        ? '-y -i "${inputFile.path}" -map 0:v:0 -an -c:v copy '
            '-movflags +faststart "$outputPath"'
        : '-y -i "${inputFile.path}" -map 0:v:0 -map 0:a? -c copy '
            '-movflags +faststart "$outputPath"';
    final copyFallbackRun = _timelineAudioTrackPath == null
        ? await _runExportCommand(copyFallbackCommand)
        : (success: false, output: fallbackRun.output);

    if (!mounted) {
      return;
    }

    setState(() {
      _isExporting = false;
      _exportProgress = copyFallbackRun.success ? 1.0 : 0.0;
    });
    ExportStatusService.instance.finish(success: copyFallbackRun.success);

    if (copyFallbackRun.success) {
      final savedToGallery = await _saveExportToGalleryAfterInterstitial(
        outputPath,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            savedToGallery
                ? 'Video saved to Gallery (original media mode).'
                : 'Export completed, but gallery save failed.',
          ),
        ),
      );
      return;
    }

    final details =
        ('${primaryRun.output}\n${fallbackRun.output}\n${copyFallbackRun.output}')
            .trim();
    final preview = _summarizeFfmpegFailure(details);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          preview.isEmpty
              ? 'Rendering failed. Please try again.'
              : 'Rendering failed: $preview',
        ),
      ),
    );
  }

  Future<bool> _saveExportToGalleryAfterInterstitial(String outputPath) async {
    await MonetizationService.instance.showInterstitialAd();
    final result = await ImageGallerySaverPlus.saveFile(outputPath);
    return result is Map && result['isSuccess'] == true;
  }

  String _summarizeFfmpegFailure(String output) {
    final lines = output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final errorLines = lines
        .where(
          (line) => RegExp(
            r'(error|failed|invalid|not found|no such|cannot|unable)',
            caseSensitive: false,
          ).hasMatch(line),
        )
        .toList();
    final summaryLines = errorLines.isEmpty ? lines : errorLines;
    final summary = summaryLines.isEmpty ? '' : summaryLines.last;
    return summary.length > 240 ? '${summary.substring(0, 240)}...' : summary;
  }

  Future<({bool success, String output})> _runExportCommand(
      String command) async {
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    final output = (await session.getOutput()) ?? '';
    return (success: ReturnCode.isSuccess(returnCode), output: output);
  }

  Future<void> _generateCaptionsWithAi() async {
    final inputFile = widget.videoFile;
    if (inputFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Load a video before generating captions.')),
      );
      return;
    }

    final isPro = MonetizationService.instance.isProUnlocked.value;
    if (!isPro) {
      final rewarded = await MonetizationService.instance.promptRewardedGate();
      if (!rewarded) {
        return;
      }
      if (!mounted) {
        return;
      }
    }

    if (!_aiCaptionService.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Configure AI_CAPTION_ENDPOINT and AI_CAPTION_API_KEY with --dart-define.',
          ),
        ),
      );
      return;
    }

    setState(() => _isGeneratingCaptions = true);
    try {
      final segments =
          await _aiCaptionService.generateCaptionsFromVideo(inputFile);
      if (!mounted) {
        return;
      }

      setState(() {
        _textLayers
          ..clear()
          ..addAll(
            List.generate(segments.length, (index) {
              final segment = segments[index];
              final nextStart = index + 1 < segments.length
                  ? segments[index + 1].startMs
                  : segment.startMs + 1400;
              return {
                'text': segment.text,
                'offset': const Offset(24, 430),
                'isCaption': true,
                'segmentIndex': index,
                'removed': false,
                'startMs': segment.startMs,
                'endMs': math.max(nextStart, segment.startMs + 650),
              };
            }),
          );
        _removedTranscriptIndexes.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Generated ${segments.length} caption segments.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Caption generation failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isGeneratingCaptions = false);
      }
    }
  }

  Future<void> _analyzeBeatSync() async {
    final inputFile = widget.videoFile;
    if (inputFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Load a video before beat analysis.')),
      );
      return;
    }

    setState(() => _isAnalyzingBeats = true);
    try {
      final markers = await _beatSyncService.detectBeatMarkers(inputFile);
      if (!mounted) {
        return;
      }

      setState(() {
        _beatMarkersMs = markers.map((m) => m.timeMs).toList();
      });

      _generateAutoCutSegments();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Detected ${_beatMarkersMs.length} beat points and ${_autoCutSegments.length} cut segments.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Beat analysis failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isAnalyzingBeats = false);
      }
    }
  }

  Future<void> _optimizeSpeechTrack() async {
    final transcriptLayers =
        _textLayers.where((layer) => layer['isCaption'] == true).toList();
    if (transcriptLayers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Generate captions first to optimize speech.')),
      );
      return;
    }

    final fillerPattern = RegExp(
      r'^(um+|uh+|erm+|like|you know|i mean|sort of|kind of)$',
      caseSensitive: false,
    );

    var removedCount = 0;
    setState(() {
      for (final layer in transcriptLayers) {
        final index = layer['segmentIndex'] as int?;
        if (index == null) {
          continue;
        }
        final text = (layer['text'] as String).trim().toLowerCase();
        final isFiller = fillerPattern.hasMatch(text) || text.length <= 2;
        if (isFiller) {
          layer['removed'] = true;
          _removedTranscriptIndexes.add(index);
          removedCount++;
        }
      }
      _silenceFillerCleanupEnabled = true;
    });

    if (removedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No filler words detected in current transcript.')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Removed $removedCount filler segments. Silence will ripple-cut on export.')),
    );
  }

  Future<void> _launchAiObjectClone() async {
    await MonetizationService.instance.triggerProFeature(
      context,
      () {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AI Object Clone beta unlocked for this session.'),
          ),
        );
      },
      featureName: 'AI Object Clone',
    );
  }

  void _generateBRollSuggestions() {
    final transcriptLayers = _textLayers
        .where(
            (layer) => layer['isCaption'] == true && layer['removed'] != true)
        .toList();
    if (transcriptLayers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Generate captions first to suggest B-roll.')),
      );
      return;
    }

    final suggestions = _bRollSuggester.suggestFromTranscript(transcriptLayers);
    setState(() {
      _bRollSuggestions = suggestions;
      _activeTool = 'BRoll';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Suggested ${suggestions.length} B-roll ideas.')),
    );
  }

  void _applyTranscriptRippleCut() {
    if (_removedTranscriptIndexes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Delete transcript segments first, then export to ripple-cut them.'),
        ),
      );
      return;
    }

    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Transcript ripple cut armed for ${_removedTranscriptIndexes.length} removed segments.'),
      ),
    );
  }

  Widget _buildSubToolChip(String label) {
    final isSelected = _activeAdjustSubTool == label;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 10)),
      selected: isSelected,
      selectedColor: const Color(0xFF2563EB),
      backgroundColor: const Color(0xFF1E1E2A),
      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white60),
      onSelected: (_) => setState(() => _activeAdjustSubTool = label),
    );
  }

  Widget _buildRatioChip(String label, double ratio, String presetId) {
    final isSelected = _aspectRatio == ratio;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: const Color(0xFF2563EB),
        backgroundColor: const Color(0xFF1E1E2A),
        labelStyle:
            TextStyle(color: isSelected ? Colors.white : Colors.white70),
        onSelected: (_) => setState(() {
          _aspectRatio = ratio;
          _selectedOutputRatioPreset = presetId;
        }),
      ),
    );
  }

  Future<void> _enableAudioDuckerPro() async {
    final unlocked = await MonetizationService.instance.unlockProFeatureGate(
      context,
      featureName: 'Audio Ducker',
    );
    if (!mounted) {
      return;
    }
    if (!unlocked) {
      setState(() {
        _autoDucking = false;
        _audioDuckerProEnabled = false;
      });
      return;
    }

    setState(() {
      _autoDucking = true;
      _audioDuckerProEnabled = true;
    });
  }

  Future<void> _pickDuoCreator2Video() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'mov', 'mkv', 'webm'],
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) {
      return;
    }
    setState(() => _duoCreator2VideoPath = path);
  }

  Future<void> _pickDuoAudioTrack() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'wav', 'm4a', 'aac'],
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) {
      return;
    }
    setState(() => _duoAudioTrackPath = path);
  }

  Future<void> _pickVoiceoverTrack() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'wav', 'm4a', 'aac'],
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) {
      return;
    }
    setState(() => _voiceoverTrackPath = path);
  }

  Future<void> _generateAiVoiceoverTrack() async {
    if (_isGeneratingVoiceover) {
      return;
    }

    final currentContext = context;
    final generatedPayload =
        await showModalBottomSheet<({VoiceOption voice, String text})>(
      context: currentContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: VoicePickerDialog(
          onGenerate: (voice, text) {
            Navigator.of(ctx).pop((voice: voice, text: text));
          },
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    if (generatedPayload == null) {
      return;
    }

    if (!_aiSpeechService.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Configure ELEVENLABS_API_KEY with --dart-define to generate speech.',
          ),
        ),
      );
      return;
    }

    final currentPoints = await PointService.getPoints();
    if (!mounted) {
      return;
    }

    final usePoints = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF151520),
        title: const Text(
          'Choose how to generate speech',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '${PointService.speechGenerationCost} points are required, or watch a short ad to continue.\n\n$currentPoints points available.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Watch ad'),
          ),
          ElevatedButton(
            onPressed: currentPoints >= PointService.speechGenerationCost
                ? () => Navigator.of(dialogContext).pop(true)
                : null,
            child: Text('Use ${PointService.speechGenerationCost} points'),
          ),
        ],
      ),
    );

    if (!mounted || usePoints == null) {
      return;
    }

    if (!usePoints) {
      final watched = await MonetizationService.instance
          .watchRewardedAdForTemplate();
      if (!mounted) {
        return;
      }
      if (!watched) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The rewarded ad was not completed.')),
        );
        return;
      }
    }

    var pointsCharged = false;
    if (usePoints) {
      pointsCharged = await PointService.deductPoints(
        PointService.speechGenerationCost,
      );
      if (!pointsCharged) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Your points balance changed. Try again.')),
          );
        }
        return;
      }
    }

    setState(() => _isGeneratingVoiceover = true);
    try {
      final generatedFile = await _aiSpeechService.generateSpeech(
        text: generatedPayload.text,
        voiceId: generatedPayload.voice.id,
      );

      if (!mounted) {
        return;
      }

      if (generatedFile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speech generation returned no file.')),
        );
        return;
      }

      setState(() {
        _voiceoverTrackPath = generatedFile.path;
        if (_autoDucking && _audioDuckerProEnabled) {
          _activeTool = 'Audio';
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'AI voice track ready: ${_shortPath(generatedFile.path)}',
          ),
        ),
      );
    } catch (error) {
      if (pointsCharged) {
        await PointService.addPoints(PointService.speechGenerationCost);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speech generation failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isGeneratingVoiceover = false);
      }
    }
  }

  Future<void> _pickMusicTrack() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'wav', 'm4a', 'aac'],
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) {
      return;
    }
    setState(() => _musicTrackPath = path);
  }

  Future<void> _extractAudioFromPickedVideo() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'mov', 'mkv', 'webm'],
    );
    final path = result?.files.single.path;
    if (path == null) {
      return;
    }
    await _extractAudioToTimeline(path, muteOriginal: false);
  }

  Future<void> _detachCurrentVideoAudio() async {
    final video = widget.videoFile;
    if (video == null) {
      return;
    }
    await _extractAudioToTimeline(video.path, muteOriginal: true);
  }

  Future<void> _extractAudioToTimeline(
    String videoPath, {
    required bool muteOriginal,
  }) async {
    setState(() => _isExtractingAudio = true);
    try {
      final cache = await getTemporaryDirectory();
      final outputPath =
          '${cache.path}/clipsnap_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final session = await FFmpegKit.execute(
        '-y -i "${_escapePathArg(videoPath)}" -map 0:a:0? -vn -c:a aac -b:a 192k "${_escapePathArg(outputPath)}"',
      );
      final returnCode = await session.getReturnCode();
      final outputFile = File(outputPath);
      final hasAudioOutput = ReturnCode.isSuccess(returnCode) &&
          await outputFile.exists() &&
          await outputFile.length() > 0;
      if (!mounted) {
        return;
      }
      if (!hasAudioOutput) {
        showAppFeedback(
          context,
          'No extractable audio found',
          kind: FeedbackKind.error,
        );
        return;
      }
      final waveform = await _generateWaveform(outputPath);
      await _timelineAudioPlayer.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _timelineAudioTrackPath = outputPath;
        _originalAudioMuted = muteOriginal;
        _audioSegments = [const _AudioSegment(0.0, 1.0)];
        _audioWaveform = waveform;
        _selectedAudioSegment = 0;
      });
      await _videoController?.setVolume(
        _previewAudioMuted || muteOriginal ? 0 : 1,
      );
      if (!mounted) {
        return;
      }
      showAppFeedback(
        context,
        muteOriginal
            ? 'Audio extracted & video muted'
            : 'Audio extracted to timeline',
        kind: FeedbackKind.success,
      );
    } finally {
      if (mounted) {
        setState(() => _isExtractingAudio = false);
      }
    }
  }

  Future<void> _replaceTimelineAudio() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'wav', 'm4a', 'aac'],
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) {
      return;
    }
    final waveform = await _generateWaveform(path);
    await _timelineAudioPlayer.stop();
    if (!mounted) {
      return;
    }
    setState(() {
      _timelineAudioTrackPath = path;
      _audioWaveform = waveform;
    });
  }

  void _removeTimelineAudio() {
    unawaited(_timelineAudioPlayer.stop());
    setState(() {
      _timelineAudioTrackPath = null;
      _audioSegments = [const _AudioSegment(0.0, 1.0)];
      _audioWaveform = const [];
      _selectedAudioSegment = 0;
    });
  }

  Future<List<double>> _generateWaveform(String audioPath) async {
    final cache = await getTemporaryDirectory();
    final pcmPath =
        '${cache.path}/clipsnap_waveform_${DateTime.now().microsecondsSinceEpoch}.pcm';
    final session = await FFmpegKit.execute(
      '-y -i "${_escapePathArg(audioPath)}" -map 0:a:0 -ac 1 -ar 400 '
      '-f s16le "${_escapePathArg(pcmPath)}"',
    );
    final returnCode = await session.getReturnCode();
    final pcmFile = File(pcmPath);
    if (!ReturnCode.isSuccess(returnCode) || !await pcmFile.exists()) {
      return const [];
    }

    try {
      return buildWaveformSamples(await pcmFile.readAsBytes());
    } finally {
      if (await pcmFile.exists()) {
        await pcmFile.delete();
      }
    }
  }

  void _splitAudioAtPlayhead() {
    final controller = _videoController;
    if (controller == null || controller.value.duration.inMilliseconds <= 0) {
      return;
    }
    final split = controller.value.position.inMilliseconds /
        controller.value.duration.inMilliseconds;
    final index = _audioSegments.indexWhere(
      (segment) => split > segment.start + 0.005 && split < segment.end - 0.005,
    );
    if (index < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Move the playhead inside an audio segment.')),
      );
      return;
    }
    final segment = _audioSegments[index];
    HapticFeedback.mediumImpact();
    setState(() {
      _audioSegments = [
        ..._audioSegments.take(index),
        _AudioSegment(segment.start, split),
        _AudioSegment(split, segment.end),
        ..._audioSegments.skip(index + 1),
      ];
      _selectedAudioSegment = index + 1;
    });
  }

  void _deleteSelectedAudioSegment() {
    if (_audioSegments.isEmpty) {
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _audioSegments.removeAt(_selectedAudioSegment);
      if (_audioSegments.isEmpty) {
        _timelineAudioTrackPath = null;
        _audioSegments = [const _AudioSegment(0.0, 1.0)];
        _selectedAudioSegment = 0;
      } else {
        _selectedAudioSegment = math.min(
          _selectedAudioSegment,
          _audioSegments.length - 1,
        );
      }
    });
  }

  void _trimSelectedAudioSegment(RangeValues values) {
    if (values.end - values.start < 0.01) {
      return;
    }
    setState(() {
      _audioSegments[_selectedAudioSegment] =
          _AudioSegment(values.start, values.end);
      _audioSegments.sort((a, b) => a.start.compareTo(b.start));
      _selectedAudioSegment = _audioSegments.indexWhere(
        (segment) => segment.start == values.start && segment.end == values.end,
      );
    });
    final positionMs = _videoController?.value.position.inMilliseconds;
    if (positionMs != null) {
      unawaited(_syncTimelineAudioPreview(positionMs, force: true));
    }
  }

  double get _videoDurationSeconds {
    final seconds = _videoController?.value.duration.inMilliseconds ?? 0;
    return seconds > 0 ? seconds / 1000 : 1.0;
  }

  Widget _buildAudioEffectSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label ${value.toStringAsFixed(1)}s',
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        Slider(value: value, min: 0, max: 3, onChanged: onChanged),
      ],
    );
  }

  Widget _buildAudioTimelineTrack() {
    return SizedBox(
      key: const ValueKey('audio-timeline-track'),
      height: 34,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              Positioned.fill(
                child: Container(color: const Color(0xFF171923)),
              ),
              for (var index = 0; index < _audioSegments.length; index++)
                Positioned(
                  left: constraints.maxWidth * _audioSegments[index].start,
                  width: math.max(
                    4,
                    constraints.maxWidth *
                        (_audioSegments[index].end -
                            _audioSegments[index].start),
                  ),
                  top: 2,
                  bottom: 2,
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _selectedAudioSegment = index;
                      _activeTool = 'Audio';
                    }),
                    child: Container(
                      decoration: BoxDecoration(
                        color: index == _selectedAudioSegment
                            ? const Color(0xFF2563EB)
                            : const Color(0xFF174E75),
                        border: Border.all(color: Colors.white24),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(
                          18,
                          (bar) {
                            final segment = _audioSegments[index];
                            final position = segment.start +
                                (segment.end - segment.start) * (bar / 17);
                            final sampleIndex = _audioWaveform.isEmpty
                                ? -1
                                : (position * (_audioWaveform.length - 1))
                                    .round()
                                    .clamp(0, _audioWaveform.length - 1);
                            final amplitude = sampleIndex < 0
                                ? 0.12
                                : _audioWaveform[sampleIndex];
                            return Container(
                              width: 2,
                              height: 4 + amplitude * 22,
                              color: Colors.white70,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _shortPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  Future<bool> renderDuoBeatSync({
    required String creator1Path,
    required String creator2Path,
    required String audioTrackPath,
    required String outputPath,
  }) async {
    final reframe = _buildReframeFilterForPreset(_selectedOutputRatioPreset);
    final command = '-i "${_escapePathArg(creator1Path)}" '
        '-i "${_escapePathArg(creator2Path)}" '
        '-i "${_escapePathArg(audioTrackPath)}" '
        '-filter_complex "'
        '[0:v]trim=0:1.5,setpts=PTS-STARTPTS,$reframe[v1];'
        '[1:v]trim=0:1.8,setpts=PTS-STARTPTS,$reframe[v2];'
        '[v1][v2]concat=n=2:v=1:a=0[outv]" '
        '-map "[outv]" -map 2:a -c:v libx264 -preset ultrafast -pix_fmt yuv420p -shortest "${_escapePathArg(outputPath)}"';

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    return ReturnCode.isSuccess(returnCode);
  }

  String _buildReframeFilterForPreset(String preset) {
    switch (preset) {
      case '16:9':
        return 'scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2';
      case '1:1':
        return 'scale=1080:1080:force_original_aspect_ratio=increase,crop=1080:1080';
      case '4:5':
        return 'scale=1080:1350:force_original_aspect_ratio=increase,crop=1080:1350';
      case '9:16':
      default:
        return 'scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920';
    }
  }

  String _buildKineticTextFilter() {
    final firstStyle = _glitchTextStyleEnabled
        ? "drawtext=text='VIBES...':fontcolor=orange:fontsize=72:borderw=4:bordercolor=black:x=(w-tw)/2+4*sin(18*t):y=(h-th)/2:alpha='if(lt(mod(t\\,0.2)\\,0.1)\\,1\\,0.65)':enable='between(t,0,1.2)'"
        : "drawtext=text='VIBES...':fontcolor=orange:fontsize=72:x=(w-tw)/2:y=(h-th)/2:enable='between(t,0,1.2)'";
    final secondStyle = _glitchTextStyleEnabled
        ? "drawtext=text='FIRE!':fontcolor=cyan:fontsize=84:borderw=4:bordercolor=0x111111:x=(w-tw)/2-4*sin(20*t):y=(h-th)/2:alpha='if(lt(mod(t\\,0.16)\\,0.08)\\,1\\,0.62)':enable='between(t,1.2,3.0)'"
        : "drawtext=text='FIRE!':fontcolor=cyan:fontsize=84:x=(w-tw)/2:y=(h-th)/2:enable='between(t,1.2,3.0)'";
    return '$firstStyle,$secondStyle';
  }

  String _appendKineticTextToFilterComplex(
    String filterComplex,
    String kineticTextFilter,
  ) {
    if (kineticTextFilter.isEmpty) {
      return filterComplex;
    }
    return '$filterComplex;[outv]$kineticTextFilter[outv]';
  }

  String _escapePathArg(String value) {
    return value.replaceAll('"', r'\"');
  }

  Widget _buildDraggableText(Map<String, dynamic> layer) {
    final offset = layer['offset'] as Offset;
    final isCaption = layer['isCaption'] == true;
    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            layer['offset'] = offset + details.delta;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF2563EB), width: 1.5),
          ),
          child: isCaption
              ? _buildCaptionStyledText(layer)
              : Text(
                  layer['text'] as String,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildCaptionStyledText(Map<String, dynamic> layer) {
    final text = (layer['text'] as String).trim();
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    final words =
        text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) {
      return const SizedBox.shrink();
    }

    final positionMs = _videoController?.value.position.inMilliseconds ?? 0;
    final startMs = (layer['startMs'] as int?) ?? 0;
    final endMs = (layer['endMs'] as int?) ?? (startMs + 1200);
    final duration = math.max(1, endMs - startMs);

    var highlightedWords = words.length;
    if (_dynamicCaptionsEnabled) {
      if (positionMs < startMs) {
        highlightedWords = 0;
      } else if (positionMs >= endMs) {
        highlightedWords = words.length;
      } else {
        final progress = (positionMs - startMs) / duration;
        highlightedWords =
            (progress * words.length).ceil().clamp(1, words.length);
      }
    }

    final baseStyle = _captionStylePreset == 'Neon'
        ? const TextStyle(
            color: Color(0xFF8EF9F3),
            fontSize: 18,
            fontWeight: FontWeight.w800,
            shadows: [
              Shadow(color: Color(0xAA36D1FF), blurRadius: 10),
              Shadow(color: Color(0x6636D1FF), blurRadius: 22),
            ],
          )
        : const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          );

    final highlightStyle = _captionStylePreset == 'Classic'
        ? const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          )
        : _captionStylePreset == 'Neon'
            ? const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                shadows: [Shadow(color: Color(0xAA36D1FF), blurRadius: 14)],
              )
            : const TextStyle(
                color: Color(0xFFFFD84D),
                fontSize: 17,
                fontWeight: FontWeight.w900,
              );

    return RichText(
      text: TextSpan(
        children: List.generate(words.length, (index) {
          final isHighlighted = index < highlightedWords;
          final suffix = index == words.length - 1 ? '' : ' ';
          return TextSpan(
            text: words[index] + suffix,
            style: isHighlighted ? highlightStyle : baseStyle,
          );
        }),
      ),
      textAlign: TextAlign.center,
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
    return _warmth;
  }

  double _getAdjustMin() {
    return (_activeAdjustSubTool == 'Brightness' ||
            _activeAdjustSubTool == 'Warmth')
        ? -0.5
        : 0.0;
  }

  double _getAdjustMax() {
    return (_activeAdjustSubTool == 'Brightness' ||
            _activeAdjustSubTool == 'Warmth')
        ? 0.5
        : 2.0;
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
    if (_activeAdjustSubTool == 'Warmth') {
      _warmth = val;
    }
  }

  void _resetAll() {
    setState(() {
      _brightness = 0.0;
      _contrast = 1.0;
      _saturation = 1.0;
      _warmth = 0.0;
      _vignette = 0.0;
      _playbackSpeed = 1.0;
      _aspectRatio = 0.5625;
      _selectedOutputRatioPreset = '9:16';
      _autoDucking = false;
      _audioDuckerProEnabled = false;
      _noiseReduction = false;
      _silenceFillerCleanupEnabled = false;
      _kineticTextEnabled = false;
      _glitchTextStyleEnabled = false;
      _duoBeatSyncEnabled = false;
      _duoCreator2VideoPath = null;
      _duoAudioTrackPath = null;
      _voiceoverTrackPath = null;
      _musicTrackPath = null;
      _timelineAudioTrackPath = null;
      _previewAudioMuted = false;
      _originalAudioMuted = false;
      _timelineAudioVolume = 1.0;
      _audioFadeInSeconds = 0.0;
      _audioFadeOutSeconds = 0.0;
      _audioSegments = [const _AudioSegment(0.0, 1.0)];
      _audioWaveform = const [];
      _selectedAudioSegment = 0;
      _beatMarkersMs = [];
      _autoCutAtBeatsEnabled = false;
      _autoCutSegments = [];
      _removedTranscriptIndexes.clear();
      _bRollSuggestions = [];
      _textLayers.clear();
    });
    _videoController?.setPlaybackSpeed(1.0);
    _videoController?.setVolume(1.0);
    unawaited(_timelineAudioPlayer.setVolume(1.0));
  }

  List<_CutSegment> _buildTranscriptSegments() {
    final segments = <_CutSegment>[];
    final transcriptLayers = _textLayers
        .where(
            (layer) => layer['isCaption'] == true && layer['removed'] != true)
        .toList();

    for (final layer in transcriptLayers) {
      final startMs = layer['startMs'] as int? ?? 0;
      final endMs = layer['endMs'] as int? ?? (startMs + 800);
      if (endMs - startMs < 120) {
        continue;
      }
      segments.add(_CutSegment(startMs: startMs, endMs: endMs));
    }

    return segments;
  }

  String _buildTranscriptRippleFilterComplex({
    required String videoFilter,
    required String audioFilter,
    required List<_CutSegment> transcriptSegments,
  }) {
    final sections = <String>[];
    final videoLabels = <String>[];
    final audioLabels = <String>[];

    for (var i = 0; i < transcriptSegments.length; i++) {
      final segment = transcriptSegments[i];
      final start = (segment.startMs / 1000).toStringAsFixed(3);
      final end = (segment.endMs / 1000).toStringAsFixed(3);

      final videoLabel = 'tv$i';
      final audioLabel = 'ta$i';
      videoLabels.add('[$videoLabel]');
      audioLabels.add('[$audioLabel]');

      sections.add(
        '[0:v]trim=start=$start:end=$end,setpts=PTS-STARTPTS,$videoFilter[$videoLabel]',
      );
      final audioChain = audioFilter.isEmpty
          ? 'atrim=start=$start:end=$end,asetpts=PTS-STARTPTS'
          : 'atrim=start=$start:end=$end,asetpts=PTS-STARTPTS,$audioFilter';
      sections.add('[0:a]$audioChain[$audioLabel]');
    }

    sections.add(
      '${videoLabels.join()}${audioLabels.join()}concat=n=${transcriptSegments.length}:v=1:a=1[outv][outa]',
    );

    return sections.join(';');
  }

  String _appendBrandWatermarkToFilterComplex(
    String filterComplex, {
    required bool brandWatermarkEnabled,
    required String watermarkText,
    required int watermarkColorValue,
    required String endScreenText,
  }) {
    if (!brandWatermarkEnabled) {
      return filterComplex;
    }

    final watermarkFilter = _buildBrandWatermarkFilter(
      watermarkText: watermarkText,
      watermarkColorValue: watermarkColorValue,
      endScreenText: endScreenText,
    );
    return '$filterComplex;[outv]$watermarkFilter[outv_brand]';
  }

  String _buildBrandWatermarkFilter({
    required String watermarkText,
    required int watermarkColorValue,
    required String endScreenText,
  }) {
    final text = '${watermarkText.trim()}\\n${endScreenText.trim()}';
    final color = _ffmpegColorHex(Color(watermarkColorValue));
    return "drawtext=text='${_escapeForDrawText(text)}':fontcolor=$color:fontsize=28:x=w-tw-24:y=h-th-24:box=1:boxcolor=0x00000066";
  }

  String _escapeForDrawText(String value) {
    return value
        .replaceAll('\\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('%', r'\%')
        .replaceAll(':', r'\:');
  }

  String _escapeFilterPath(String value) {
    return value
        .replaceAll('\\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll(':', r'\:')
        .replaceAll(',', r'\,')
        .replaceAll(' ', r'\ ')
        .replaceAll('[', r'\[')
        .replaceAll(']', r'\]');
  }

  String _ffmpegColorHex(Color color) {
    final argb = color.toARGB32();
    return '0x${argb.toRadixString(16).padLeft(8, '0')}';
  }

  void _toggleTranscriptRemoval(int index) {
    final layer = _textLayers.firstWhere(
      (item) => item['segmentIndex'] == index,
      orElse: () => <String, dynamic>{},
    );
    if (layer.isEmpty) {
      return;
    }

    setState(() {
      final isRemoved = layer['removed'] == true;
      layer['removed'] = !isRemoved;
      if (layer['removed'] == true) {
        _removedTranscriptIndexes.add(index);
      } else {
        _removedTranscriptIndexes.remove(index);
      }
    });
  }

  void _seekToTranscriptLayer(Map<String, dynamic> layer) {
    final startMs = layer['startMs'] as int?;
    if (startMs == null) {
      return;
    }
    _videoController?.seekTo(Duration(milliseconds: startMs));
  }

  void _generateAutoCutSegments() {
    final durationMs = _videoController?.value.duration.inMilliseconds ?? 0;
    if (durationMs <= 0 || _beatMarkersMs.isEmpty) {
      setState(() => _autoCutSegments = []);
      return;
    }

    final boundaries = <int>[0, ..._beatMarkersMs, durationMs]
      ..sort((a, b) => a.compareTo(b));

    final segments = <_CutSegment>[];
    for (var i = 0; i < boundaries.length - 1; i++) {
      final startMs = boundaries[i];
      final endMs = boundaries[i + 1];
      if (endMs - startMs < 260) {
        continue;
      }
      segments.add(_CutSegment(startMs: startMs, endMs: endMs));
    }

    setState(() {
      _autoCutSegments = segments;
      _autoCutAtBeatsEnabled = segments.isNotEmpty;
    });
  }

  String _buildAutoCutFilterComplex(String videoFilter) {
    final sections = <String>[];
    final videoLabels = <String>[];
    final audioLabels = <String>[];

    for (var i = 0; i < _autoCutSegments.length; i++) {
      final segment = _autoCutSegments[i];
      final start = (segment.startMs / 1000).toStringAsFixed(3);
      final end = (segment.endMs / 1000).toStringAsFixed(3);

      final videoLabel = 'v$i';
      final audioLabel = 'a$i';
      videoLabels.add('[$videoLabel]');
      audioLabels.add('[$audioLabel]');

      sections.add(
        '[0:v]trim=start=$start:end=$end,setpts=PTS-STARTPTS,$videoFilter[$videoLabel]',
      );
      sections.add(
        '[0:a]atrim=start=$start:end=$end,asetpts=PTS-STARTPTS[$audioLabel]',
      );
    }

    sections.add(
      '${videoLabels.join()}${audioLabels.join()}concat=n=${_autoCutSegments.length}:v=1:a=1[outv][outa]',
    );

    return sections.join(';');
  }

  String _formatMs(int ms) {
    final totalSeconds = (ms / 1000).floor();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final tenth = ((ms % 1000) / 100).floor();
    return '$minutes:${seconds.toString().padLeft(2, '0')}.$tenth';
  }
}

class _CutSegment {
  final int startMs;
  final int endMs;

  const _CutSegment({required this.startMs, required this.endMs});
}

class _AudioSegment {
  final double start;
  final double end;

  const _AudioSegment(this.start, this.end);
}

List<double> buildWaveformSamples(
  Uint8List pcmBytes, {
  int bucketCount = 72,
}) {
  final sampleCount = pcmBytes.length ~/ 2;
  if (sampleCount == 0 || bucketCount <= 0) {
    return const [];
  }

  final data = ByteData.sublistView(pcmBytes);
  final buckets = math.min(bucketCount, sampleCount);
  return List<double>.generate(buckets, (bucket) {
    final start = bucket * sampleCount ~/ buckets;
    final end = (bucket + 1) * sampleCount ~/ buckets;
    var peak = 0;
    for (var sample = start; sample < end; sample++) {
      final amplitude = data.getInt16(sample * 2, Endian.little).abs();
      peak = math.max(peak, amplitude);
    }
    return (peak / 32768).clamp(0.04, 1.0);
  });
}

class _VhsScanlinePainter extends CustomPainter {
  const _VhsScanlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.16);
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VhsScanlinePainter oldDelegate) => false;
}
