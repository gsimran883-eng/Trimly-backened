import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:disk_capacity/disk_capacity.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../data/template_presets.dart';
import '../models/template_model.dart';
import '../services/export_status_service.dart';
import '../services/monetization_service.dart';
import '../services/template_render_service.dart';
import '../theme/motion_spec.dart';
import '../widgets/monetization_banner.dart';
import '../widgets/custom_template_card.dart';
import 'clip_snap_studio_editor.dart';
import 'clip_snap_pro_editor.dart';
import 'editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  static const String _homeLogoAsset = 'assets/images/clipsnap_brand_logo.png';
  static const String _heroVideoAsset = 'assets/videos/leon_loop.mp4';
  static const Color _canvasStart = Color(0xFF000000);
  static const Color _surfaceCard = Color(0xFF14161D);
  static const Color _actionButton = Color(0xFF232631);
  static const Color _mutedText = Color(0xFF9EA3B0);

  static const String _settingsAspectIndexKey = 'settings.aspect_index';
  static const String _settingsSmartSuggestionsKey =
      'settings.smart_suggestions';
  static const String _settingsAutoSaveDraftsKey = 'settings.auto_save_drafts';
  static const String _settingsHqPreviewKey = 'settings.hq_preview';
  static const String _settingsExportQualityKey = 'settings.export_quality';
  static const String _settingsExportFpsKey = 'settings.export_fps';
  static const String _settingsExportBitrateKey =
      'settings.export_bitrate_mbps';
  static const String _settingsDynamicCaptionsKey = 'settings.dynamic_captions';
  static const String _settingsSubjectIsolationKey =
      'settings.subject_isolation_beta';
  static const String _settingsAutoBeatSyncKey = 'settings.auto_beat_sync';
  static const String _settingsBrandWatermarkKey = 'settings.brand_watermark';
  static const String _settingsBrandWatermarkTextKey =
      'settings.brand_watermark_text';
  static const String _settingsBrandAccentColorKey =
      'settings.brand_accent_color';
  static const String _settingsBrandEndScreenTextKey =
      'settings.brand_end_screen_text';
  static const String _settingsBrandLutPathKey = 'settings.brand_lut_path';

  late final AnimationController _introController;
  late final AnimationController _shimmerController;

  int _selectedAspectIndex = 0;
  int _selectedHomeTab = 0;
  double? _availableStorageGb;
  bool _smartSuggestionsEnabled = true;
  bool _autoSaveDraftsEnabled = true;
  bool _hqPreviewEnabled = false;
  String _exportQuality = '1080p';
  int _exportFps = 30;
  int _exportBitrateMbps = 12;
  bool _dynamicCaptionsEnabled = true;
  bool _subjectIsolationBetaEnabled = false;
  bool _autoBeatSyncEnabled = false;
  bool _brandWatermarkEnabled = false;
  String _brandWatermarkText = 'ClipSnap';
  int _brandAccentColorValue = 0xFF6366F1;
  String _brandEndScreenText = 'Follow for more';
  String? _brandLutPath;

  final List<String> _aspectRatios = const [
    '9:16 Reels/Shorts',
    '16:9 YouTube',
    '1:1 Square',
    '4:5 Feed',
  ];

  final List<_DraftProject> _drafts = [
    const _DraftProject(
      title: 'Gaming Highlight Reel',
      updatedLabel: 'Edited 2h ago',
      duration: '00:45',
      fileSize: '120 MB',
      progress: 0.72,
      accent: Color(0xFF6366F1),
      previewImage:
          'https://images.unsplash.com/photo-1542751371-adc38448a05e?auto=format&fit=crop&w=600&q=80',
    ),
    const _DraftProject(
      title: 'Travel Vlog Shorts',
      updatedLabel: 'Edited Yesterday',
      duration: '00:15',
      fileSize: '48 MB',
      progress: 0.38,
      accent: Color(0xFF10B981),
      previewImage:
          'https://images.unsplash.com/photo-1469854523086-cc02fe5d8800?auto=format&fit=crop&w=600&q=80',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: MotionSpec.entryDuration,
    )..forward();
    _shimmerController = AnimationController(
      vsync: this,
      duration: MotionSpec.shimmerSweepDuration,
    )..repeat();
    _loadSettings();
    _loadStorageStatus();
  }

  @override
  void dispose() {
    _introController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedAspectIndex = prefs.getInt(_settingsAspectIndexKey);
    final savedExportQuality = prefs.getString(_settingsExportQualityKey);
    final savedFps = prefs.getInt(_settingsExportFpsKey);
    final savedBitrate = prefs.getInt(_settingsExportBitrateKey);

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedAspectIndex = savedAspectIndex != null &&
              savedAspectIndex >= 0 &&
              savedAspectIndex < _aspectRatios.length
          ? savedAspectIndex
          : _selectedAspectIndex;
      _smartSuggestionsEnabled = prefs.getBool(_settingsSmartSuggestionsKey) ??
          _smartSuggestionsEnabled;
      _autoSaveDraftsEnabled =
          prefs.getBool(_settingsAutoSaveDraftsKey) ?? _autoSaveDraftsEnabled;
      _hqPreviewEnabled =
          prefs.getBool(_settingsHqPreviewKey) ?? _hqPreviewEnabled;
      _exportQuality = ['720p', '1080p', '4K'].contains(savedExportQuality)
          ? savedExportQuality!
          : _exportQuality;
      _exportFps = [24, 30, 60].contains(savedFps) ? savedFps! : _exportFps;
      _exportBitrateMbps =
          savedBitrate != null && savedBitrate >= 6 && savedBitrate <= 50
              ? savedBitrate
              : _exportBitrateMbps;
      _dynamicCaptionsEnabled =
          prefs.getBool(_settingsDynamicCaptionsKey) ?? _dynamicCaptionsEnabled;
      _subjectIsolationBetaEnabled =
          prefs.getBool(_settingsSubjectIsolationKey) ??
              _subjectIsolationBetaEnabled;
      _autoBeatSyncEnabled =
          prefs.getBool(_settingsAutoBeatSyncKey) ?? _autoBeatSyncEnabled;
      _brandWatermarkEnabled =
          prefs.getBool(_settingsBrandWatermarkKey) ?? _brandWatermarkEnabled;
      _brandWatermarkText = prefs.getString(_settingsBrandWatermarkTextKey) ??
          _brandWatermarkText;
      _brandEndScreenText = prefs.getString(_settingsBrandEndScreenTextKey) ??
          _brandEndScreenText;
      _brandAccentColorValue =
          prefs.getInt(_settingsBrandAccentColorKey) ?? _brandAccentColorValue;
      _brandLutPath = prefs.getString(_settingsBrandLutPathKey);
    });
  }

  Future<void> _persistSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_settingsAspectIndexKey, _selectedAspectIndex);
    await prefs.setBool(_settingsSmartSuggestionsKey, _smartSuggestionsEnabled);
    await prefs.setBool(_settingsAutoSaveDraftsKey, _autoSaveDraftsEnabled);
    await prefs.setBool(_settingsHqPreviewKey, _hqPreviewEnabled);
    await prefs.setString(_settingsExportQualityKey, _exportQuality);
    await prefs.setInt(_settingsExportFpsKey, _exportFps);
    await prefs.setInt(_settingsExportBitrateKey, _exportBitrateMbps);
    await prefs.setBool(_settingsDynamicCaptionsKey, _dynamicCaptionsEnabled);
    await prefs.setBool(
        _settingsSubjectIsolationKey, _subjectIsolationBetaEnabled);
    await prefs.setBool(_settingsAutoBeatSyncKey, _autoBeatSyncEnabled);
    await prefs.setBool(_settingsBrandWatermarkKey, _brandWatermarkEnabled);
    await prefs.setString(_settingsBrandWatermarkTextKey, _brandWatermarkText);
    await prefs.setString(_settingsBrandEndScreenTextKey, _brandEndScreenText);
    await prefs.setInt(_settingsBrandAccentColorKey, _brandAccentColorValue);
    if (_brandLutPath == null || _brandLutPath!.isEmpty) {
      await prefs.remove(_settingsBrandLutPathKey);
    } else {
      await prefs.setString(_settingsBrandLutPathKey, _brandLutPath!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFF07080C),
      appBar: _selectedHomeTab == 0 ? _buildEditorAppBar() : null,
      body: Stack(
        children: [
          Positioned.fill(child: _buildAtmosphereBackground()),
          if (_selectedHomeTab == 0)
            _buildCurrentHomeBody()
          else
            SafeArea(child: _buildCurrentHomeBody()),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MonetizationBanner(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _ClipSnapBottomNavBar(
                currentIndex: _selectedHomeTab,
                onTap: (index) => setState(() => _selectedHomeTab = index),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentHomeBody() {
    if (_selectedHomeTab == 0) {
      return CustomScrollView(
        physics: const BouncingScrollPhysics(),
        scrollCacheExtent: const ScrollCacheExtent.pixels(900),
        slivers: _buildEditorHomeSlivers(),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 96),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: _buildCurrentHomeTab(),
      ),
    );
  }

  Widget _buildCurrentHomeTab() {
    return switch (_selectedHomeTab) {
      1 => _buildAiAudioTab(),
      2 => _buildProfileTab(),
      _ => _buildEditorHomeTab(),
    };
  }

  List<Widget> _buildEditorHomeSlivers() {
    return [
      SliverToBoxAdapter(
        child: _buildReveal(order: 0, child: _buildHeroCreationHub()),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        sliver: SliverToBoxAdapter(
          child: _buildReveal(order: 1, child: _buildQuickActionRow()),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.only(top: 16),
        sliver: SliverToBoxAdapter(
          child: _buildReveal(order: 4, child: _buildTemplatesCarousel()),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
        sliver: SliverToBoxAdapter(
          child: _buildReveal(order: 5, child: _buildSectionTitle('My Drafts')),
        ),
      ),
      _buildDraftsSliverGrid(),
      const SliverToBoxAdapter(child: SizedBox(height: 104)),
    ];
  }

  Widget _buildEditorHomeTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildReveal(order: 0, child: _buildHeader()),
        const SizedBox(height: 6),
        _buildReveal(order: 1, child: _buildSystemStatusBar()),
        const SizedBox(height: 12),
        _buildReveal(order: 2, child: _buildHeroCreationHub()),
        const SizedBox(height: 18),
        _buildReveal(order: 3, child: _buildQuickActionRow()),
        const SizedBox(height: 16),
        _buildReveal(order: 4, child: _buildTemplatesCarousel()),
        const SizedBox(height: 16),
        _buildReveal(order: 5, child: _buildSectionTitle('My Drafts')),
        const SizedBox(height: 10),
        _buildReveal(order: 6, child: _buildDraftsList()),
      ],
    );
  }

  Widget _buildAiAudioTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildReveal(order: 0, child: _buildHeader()),
        const SizedBox(height: 18),
        _buildSectionTitle('AI Audio Tools'),
        const SizedBox(height: 12),
        _buildAudioToolCard(
          title: 'AI Voiceover',
          subtitle: 'Generate narration inside the Audio tool',
          icon: Icons.record_voice_over_outlined,
          color: const Color(0xFFFFB86B),
          onTap: () => _requestPermission(
            context,
            'Video',
            source: 'AI Audio Tools',
            workflow: 'Voice Sync',
            initialAiTool: 'extract_audio',
          ),
        ),
        const SizedBox(height: 10),
        _buildAudioToolCard(
          title: 'Audio Extractor',
          subtitle: 'Detach, mute, replace, and export clean audio',
          icon: Icons.audio_file_outlined,
          color: const Color(0xFF4ADE80),
          onTap: () => _requestPermission(
            context,
            'Video',
            source: 'AI Audio Tools',
            workflow: 'Extract Audio',
            initialAiTool: 'extract_audio',
          ),
        ),
      ],
    );
  }

  Widget _buildProfileTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildReveal(order: 0, child: _buildHeader()),
        const SizedBox(height: 18),
        _buildSectionTitle('Profile'),
        const SizedBox(height: 12),
        _buildProfileAction(
          icon: Icons.settings_outlined,
          title: 'Settings & Export Preferences',
          onTap: () => _showSettingsMenu(context),
        ),
        _buildProfileAction(
          icon: Icons.workspace_premium_outlined,
          title: 'ClipSnap Pro',
          onTap: () => _showProSubscription(context),
        ),
        _buildProfileAction(
          icon: Icons.storage_outlined,
          title: _availableStorageGb == null
              ? 'Checking storage...'
              : '${_availableStorageGb!.toStringAsFixed(1)} GB free',
          onTap: _loadStorageStatus,
        ),
      ],
    );
  }

  String _draftAspectLabel(int index) => index.isEven ? '9:16' : '16:9';

  Widget _buildReveal({required int order, required Widget child}) {
    final begin = MotionSpec.revealBeginForOrder(order);
    final animation = CurvedAnimation(
      parent: _introController,
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

  Widget _buildAtmosphereBackground() {
    return Stack(
      children: [
        const ColoredBox(color: _canvasStart),
      ],
    );
  }

  PreferredSizeWidget _buildEditorAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: const Text(
        'ClipSnap',
        style: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => _showProSubscription(context),
          style: TextButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
          ),
          icon: const Icon(Icons.auto_awesome, size: 14),
          label: const Text(
            'PRO',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        IconButton(
          tooltip: 'Profile',
          onPressed: () => setState(() => _selectedHomeTab = 2),
          icon: const CircleAvatar(
            radius: 17,
            backgroundColor: Color(0xFF4B4F59),
            child: Icon(Icons.person, color: Colors.white, size: 20),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Color(0xFFB06AEF), Color(0xFF6356F1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFB06AEF).withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Image.asset(
              _homeLogoAsset,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'Notifications',
          onPressed: () => _showAppNotice(
            'You are up to date. New feature updates will appear here.',
          ),
          icon: const Icon(Icons.notifications_none_rounded, size: 24),
        ),
        IconButton(
          tooltip: 'Settings',
          onPressed: () => _showSettingsMenu(context),
          icon: const Icon(Icons.settings_outlined, size: 24),
        ),
      ],
    );
  }

  Widget _buildHeroCreationHub() {
    return HeroVideoBanner(
      assetPath: _heroVideoAsset,
      onTryTemplate: _tryFeaturedTemplate,
    );
  }

  Future<void> _tryFeaturedTemplate() async {
    await MonetizationService.instance.showInterstitialAd();
    if (!mounted) {
      return;
    }
    _requestPermission(
      context,
      'Video',
      source: 'Hero Template',
      workflow: 'Pro Motion Engine',
    );
  }

  Widget _buildQuickActionRow() {
    final actionItems = [
      (Icons.person_outline, 'AI Voiceover', const Color(0xFFB7B3FF)),
      (Icons.music_note_outlined, 'Audio Extractor', const Color(0xFF4ADE80)),
      (Icons.folder_outlined, 'Local Files', const Color(0xFF9CC7FF)),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          for (int i = 0; i < actionItems.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: i < actionItems.length - 1 ? 12 : 0,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _requestPermission(
                      context,
                      'Video',
                      source: actionItems[i].$2,
                      workflow: i == 0
                          ? 'Voice Sync'
                          : i == 1
                              ? 'Extract Audio'
                              : null,
                      initialAiTool: i == 0
                          ? 'voiceover'
                          : i == 1
                              ? 'extract_audio'
                              : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 48,
                          decoration: BoxDecoration(
                            color: _actionButton,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Icon(
                            actionItems[i].$1,
                            size: 22,
                            color: i == 2 ? Colors.white : actionItems[i].$3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          actionItems[i].$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTemplatesCarousel() {
    return Column(
      key: const ValueKey('studio-templates-carousel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Templates',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'See All',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: _mutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: _mutedText,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 14.0;
            final cardsVisible = 3.0;
            final cardWidth =
                (constraints.maxWidth - (gap * (cardsVisible - 1))) / cardsVisible;
            final cardHeight = cardWidth / 0.75;
            return SizedBox(
              height: cardHeight,
              child: ListView.separated(
                key: const ValueKey('studio-templates-grid'),
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: clipSnapTemplates.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: gap),
                itemBuilder: (context, index) {
                  final template = clipSnapTemplates[index];
                  return SizedBox(
                    width: cardWidth,
                    child: _buildPresetTemplateCard(template),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPresetTemplateCard(VideoTemplate template) {
    return CustomTemplateCard(
      template: template,
      onTap: () => handleTemplateTap(template),
    );
  }

  Future<void> handleTemplateTap(VideoTemplate template) async {
    final unlocked = await MonetizationService.instance
        .unlockTemplateForSession(context, template: template);
    if (!mounted || !unlocked) {
      return;
    }

    debugPrint('Template payload for ${template.id}: ${template.resolvedActionPayload}');

    final mediaType = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF151522),
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.videocam_outlined, color: Colors.cyan),
              title: const Text('Use a video',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.of(sheetContext).pop('video'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined, color: Colors.amber),
              title: const Text('Use a photo',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.of(sheetContext).pop('image'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || mediaType == null) {
      return;
    }

    final picker = ImagePicker();
    final media = mediaType == 'video'
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery);
    if (!mounted || media == null) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(
          children: [
            const CircularProgressIndicator(color: Colors.cyanAccent),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                'Applying ${template.name}...',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    String? outputPath;
    bool rendered = false;
    Object? renderError;
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      outputPath = mediaType == 'video'
          ? '${tempDir.path}/clipsnap_$timestamp.mp4'
          : '${tempDir.path}/clipsnap_$timestamp.png';
      rendered = mediaType == 'video'
          ? await exportVideoWithTemplate(
              inputPath: media.path,
              outputPath: outputPath,
              selectedTemplate: template,
            )
          : await exportImageWithTemplate(
              inputPath: media.path,
              outputPath: outputPath,
              selectedTemplate: template,
            );
    } catch (error) {
      renderError = error;
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (!mounted) {
      return;
    }

    if (!rendered || outputPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            renderError == null
                ? 'Failed to render video template.'
                : 'Template render failed: $renderError',
          ),
        ),
      );
      return;
    }
    final renderedPath = outputPath;

    if (mediaType == 'video') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ClipSnapStudioEditor(
            videoFile: File(renderedPath),
            initialWorkflow: template.name,
            initialTemplateId: template.id,
            templateAlreadyRendered: true,
            launchSource: 'Template',
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ClipSnapProEditor(
            imageFile: File(renderedPath),
            initialAiConfig: {'template': template.id},
          ),
        ),
      );
    }
  }

  Widget _buildDraftsList() {
    if (_drafts.isEmpty) {
      return _buildDraftsEmptyState();
    }

    return GridView.builder(
      key: const ValueKey('drafts-grid'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _drafts.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (context, index) {
        final draft = _drafts[index];
        return _buildProjectTile(
          aspectLabel: _draftAspectLabel(index),
          title: draft.title,
          details: '${draft.updatedLabel} • ${draft.duration}',
          imageUrl: draft.previewImage,
          accent: draft.accent,
          onTap: () => _openDraft(draft),
          onLongPress: () => _showDraftActions(context, draft),
        );
      },
    );
  }

  Widget _buildDraftsSliverGrid() {
    if (_drafts.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(child: _buildDraftsEmptyState()),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        key: const ValueKey('drafts-grid'),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.82,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final draft = _drafts[index];
            return _buildProjectTile(
              aspectLabel: _draftAspectLabel(index),
              title: draft.title,
              details: '${draft.updatedLabel} • ${draft.duration}',
              imageUrl: draft.previewImage,
              accent: draft.accent,
              onTap: () => _openDraft(draft),
              onLongPress: () => _showDraftActions(context, draft),
            );
          },
          childCount: _drafts.length,
        ),
      ),
    );
  }

  Widget _buildProjectTile({
    required String aspectLabel,
    required String title,
    required String details,
    required String imageUrl,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
    required Color accent,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        key: ValueKey('draft-card-$title'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(
                accent.withValues(alpha: 0.18),
                _surfaceCard,
              ),
              const Color(0xFF090A0D),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(18)),
                    child: _buildCardImage(imageUrl),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.35),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.36),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Text(
                        aspectLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 12,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              key: const ValueKey('draft-title-content'),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Text(
                details,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _mutedText,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioToolCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _mutedText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileAction({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: const Color(0xFFBFCBFF)),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
      onTap: onTap,
    );
  }

  Widget _buildDraftsEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF14172B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          Icon(Icons.video_library_outlined, color: Color(0xFF8FA5FF)),
          SizedBox(height: 8),
          Text(
            "No projects yet. Tap 'Start New Project' to start editing!",
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFD7DEFA), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemStatusBar() {
    return ValueListenableBuilder<ExportStatus>(
      valueListenable: ExportStatusService.instance.status,
      builder: (context, export, _) {
        final storage = _availableStorageGb == null
            ? 'Checking storage...'
            : '${_availableStorageGb!.toStringAsFixed(1)} GB free';
        final readyFor4k = (_availableStorageGb ?? 0) >= 8;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    export.isActive
                        ? Icons.movie_filter_outlined
                        : Icons.sd_storage_outlined,
                    size: 16,
                    color: export.isActive
                        ? const Color(0xFF47C8FF)
                        : const Color(0xFF70E1B2),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      export.isActive
                          ? '${export.label} ${(export.progress * 100).round()}%'
                          : '$storage • ${readyFor4k ? 'Ready for 4K export' : 'Use Storage Saver for 4K'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _mutedText,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              if (export.isActive) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: export.progress,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.4,
            ),
          ),
        ),
        if (title == 'My Drafts')
          Row(
            children: [
              IconButton(
                tooltip: 'Search drafts',
                onPressed: () => _showAppNotice('Search drafts'),
                icon: const Icon(Icons.search_rounded,
                    size: 20, color: Colors.white70),
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              IconButton(
                tooltip: 'Sort drafts',
                onPressed: () => _showAppNotice('Sort drafts'),
                icon: const Icon(Icons.sort_rounded,
                    size: 20, color: Colors.white70),
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 6),
              const Text(
                'See All',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildCardImage(String imageSource) {
    if (imageSource.startsWith('http://') ||
        imageSource.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: imageSource,
        fit: BoxFit.cover,
        fadeInDuration: 180.ms,
        placeholder: (context, url) => _buildImageFallback(),
        errorWidget: (context, url, error) => _buildImageFallback(),
      );
    }

    return Image.asset(
      imageSource,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _buildImageFallback(),
    );
  }

  Widget _buildImageFallback() {
    return Container(
      color: Colors.white.withValues(alpha: 0.05),
      alignment: Alignment.center,
      child: const Icon(
        Icons.play_circle_outline,
        color: Colors.white38,
        size: 30,
      ),
    );
  }

  void _requestPermission(
    BuildContext context,
    String mode, {
    required String source,
    String? workflow,
    String? initialAiTool,
    Map<String, Object?>? initialAiConfig,
    String? aspectRatioOverride,
    bool autoOpenPicker = true,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => ClipSnapPermissionDialog(
        onAllow: () {
          Navigator.of(ctx).pop();
          Navigator.of(context).pushNamed(
            '/editor',
            arguments: ClipSnapEditorLaunchConfig(
              mode: mode,
              source: source,
              aspectRatio:
                  aspectRatioOverride ?? _aspectRatios[_selectedAspectIndex],
              workflow: workflow,
              initialAiTool: initialAiTool,
              initialAiConfig: initialAiConfig,
              autoOpenPicker: autoOpenPicker,
            ),
          );
        },
      ),
    );
  }

  void _showProSubscription(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const ClipSnapProSheet(),
    );
  }

  void _showSettingsMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF151522),
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Material(
                color: Colors.transparent,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'App Settings',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Draft projects: ${_drafts.length}',
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        _settingsSwitch(
                          title: 'Dynamic Auto-Captions',
                          subtitle: 'Word-by-word animated subtitle presets',
                          value: _dynamicCaptionsEnabled,
                          onChanged: (value) {
                            setState(() => _dynamicCaptionsEnabled = value);
                            setModalState(() {});
                            _persistSettings();
                          },
                        ),
                        _settingsSwitch(
                          title: 'Subject Isolation (Beta)',
                          subtitle: 'Background removal without green screen',
                          value: _subjectIsolationBetaEnabled,
                          onChanged: (value) {
                            setState(
                                () => _subjectIsolationBetaEnabled = value);
                            setModalState(() {});
                            _persistSettings();
                          },
                        ),
                        _settingsSwitch(
                          title: 'Auto Beat-Sync',
                          subtitle: 'Snap clip cuts to detected audio beats',
                          value: _autoBeatSyncEnabled,
                          onChanged: (value) {
                            setState(() => _autoBeatSyncEnabled = value);
                            setModalState(() {});
                            _persistSettings();
                          },
                        ),
                        _settingsSwitch(
                          title: 'Smart Suggestions',
                          subtitle: 'Personalized editing hints',
                          value: _smartSuggestionsEnabled,
                          onChanged: (value) {
                            setState(() => _smartSuggestionsEnabled = value);
                            setModalState(() {});
                            _persistSettings();
                          },
                        ),
                        _settingsSwitch(
                          title: 'Auto-save Drafts',
                          subtitle: 'Save timeline changes every 30 seconds',
                          value: _autoSaveDraftsEnabled,
                          onChanged: (value) {
                            setState(() => _autoSaveDraftsEnabled = value);
                            setModalState(() {});
                            _persistSettings();
                          },
                        ),
                        _settingsSwitch(
                          title: 'High-Quality Preview',
                          subtitle: 'Uses more battery for cleaner playback',
                          value: _hqPreviewEnabled,
                          onChanged: (value) {
                            setState(() => _hqPreviewEnabled = value);
                            setModalState(() {});
                            _persistSettings();
                          },
                        ),
                        _settingsSwitch(
                          title: 'Brand Watermark',
                          subtitle:
                              'Apply your logo/text on exports by default',
                          value: _brandWatermarkEnabled,
                          onChanged: (value) {
                            setState(() => _brandWatermarkEnabled = value);
                            setModalState(() {});
                            _persistSettings();
                          },
                        ),
                        TextFormField(
                          initialValue: _brandWatermarkText,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Watermark Text',
                            labelStyle: TextStyle(color: Colors.white54),
                          ),
                          onChanged: (value) {
                            _brandWatermarkText = value.trim().isEmpty
                                ? 'ClipSnap'
                                : value.trim();
                            _persistSettings();
                          },
                        ),
                        TextFormField(
                          initialValue: _brandEndScreenText,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'End Screen Text',
                            labelStyle: TextStyle(color: Colors.white54),
                          ),
                          onChanged: (value) {
                            _brandEndScreenText = value.trim().isEmpty
                                ? 'Follow for more'
                                : value.trim();
                            _persistSettings();
                          },
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading:
                              const Icon(Icons.gradient, color: Colors.white70),
                          title: const Text(
                            'Import LUT (.cube / .3dl)',
                            style: TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            _brandLutPath == null
                                ? 'No LUT selected'
                                : _brandLutPath!.split('/').last,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
                          trailing: TextButton(
                            onPressed: () async {
                              final result = await FilePicker.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['cube', '3dl', 'lut'],
                              );
                              final selected = result?.files.single.path;
                              if (selected == null) {
                                return;
                              }
                              setState(() => _brandLutPath = selected);
                              setModalState(() {});
                              await _persistSettings();
                            },
                            child: const Text('Choose'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Export Profile',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: ['720p', '1080p', '4K'].map((quality) {
                            final selected = _exportQuality == quality;
                            return ChoiceChip(
                              label: Text(quality),
                              selected: selected,
                              selectedColor: const Color(0xFF6366F1),
                              backgroundColor: const Color(0xFF1E1E2A),
                              onSelected: (_) {
                                setState(() => _exportQuality = quality);
                                setModalState(() {});
                                _persistSettings();
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [24, 30, 60].map((fps) {
                            final selected = _exportFps == fps;
                            return ChoiceChip(
                              label: Text('$fps FPS'),
                              selected: selected,
                              selectedColor: const Color(0xFF6366F1),
                              backgroundColor: const Color(0xFF1E1E2A),
                              onSelected: (_) {
                                setState(() => _exportFps = fps);
                                setModalState(() {});
                                _persistSettings();
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Bitrate: $_exportBitrateMbps Mbps',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                        Slider(
                          value: _exportBitrateMbps.toDouble(),
                          min: 6,
                          max: 50,
                          divisions: 44,
                          activeColor: const Color(0xFF6366F1),
                          onChanged: (value) {
                            setState(() => _exportBitrateMbps = value.round());
                            setModalState(() {});
                          },
                          onChangeEnd: (_) => _persistSettings(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _settingsSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      dense: true,
      contentPadding: EdgeInsets.zero,
      activeThumbColor: const Color(0xFF6366F1),
      title: Text(title,
          style: const TextStyle(color: Colors.white, fontSize: 14)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: Colors.white54, fontSize: 12)),
      value: value,
      onChanged: onChanged,
    );
  }

  void _showDraftActions(BuildContext context, _DraftProject draft) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF151522),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.white70),
                  title:
                      const Text('Edit', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openDraft(draft);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.ios_share, color: Colors.white70),
                  title: const Text('Quick Export',
                      style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showAppNotice('Started quick export for ${draft.title}.');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy, color: Colors.white70),
                  title: const Text('Duplicate',
                      style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _duplicateDraft(draft);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline,
                      color: Color(0xFFFF8A8A)),
                  title: const Text('Delete',
                      style: TextStyle(color: Color(0xFFFFB4B4))),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _deleteDraft(draft);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openDraft(_DraftProject draft) {
    _requestPermission(
      context,
      'Video',
      source: 'My Drafts',
      workflow: draft.title,
      autoOpenPicker: false,
    );
  }

  void _duplicateDraft(_DraftProject draft) {
    setState(() {
      _drafts.insert(0, draft.copyWith(title: '${draft.title} Copy'));
    });
    _showAppNotice('Duplicated ${draft.title}.');
  }

  void _deleteDraft(_DraftProject draft) {
    setState(() => _drafts.remove(draft));
    _showAppNotice('Deleted ${draft.title}.');
  }

  Future<void> _loadStorageStatus() async {
    try {
      final freeMb = await DiskCapacity().getFreeDiskSpace();
      if (mounted) {
        setState(() => _availableStorageGb = freeMb / 1024);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _availableStorageGb = 0);
      }
    }
  }

  void _showAppNotice(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class ClipSnapPermissionDialog extends StatefulWidget {
  final VoidCallback? onAllow;

  const ClipSnapPermissionDialog({super.key, this.onAllow});

  @override
  State<ClipSnapPermissionDialog> createState() =>
      _ClipSnapPermissionDialogState();
}

class _ClipSnapPermissionDialogState extends State<ClipSnapPermissionDialog> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final options = [
      (
        'Import video',
        Icons.photo_library_outlined,
        const Color(0xFF8A7CFF),
      ),
      (
        'Record a clip',
        Icons.videocam_outlined,
        const Color(0xFF47C8FF),
      ),
      (
        'Blank canvas',
        Icons.note_alt_outlined,
        const Color(0xFF4ADE80),
      ),
    ];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.08),
                  const Color(0xFF151A2B).withValues(alpha: 0.92),
                  const Color(0xFF090A0F).withValues(alpha: 0.94),
                ],
              ),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF47C8FF).withValues(alpha: 0.14),
                  blurRadius: 28,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Start New Project',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Choose a starting point',
                  style: TextStyle(
                    color: Color(0xFF8A94A6),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 18),
                for (int index = 0; index < options.length; index++) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _selectedIndex = index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: _selectedIndex == index
                              ? options[index].$3.withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _selectedIndex == index
                                ? options[index].$3.withValues(alpha: 0.7)
                                : Colors.white.withValues(alpha: 0.08),
                          ),
                          boxShadow: _selectedIndex == index
                              ? [
                                  BoxShadow(
                                    color: options[index]
                                        .$3
                                        .withValues(alpha: 0.18),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color:
                                    options[index].$3.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                options[index].$2,
                                color: options[index].$3,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                options[index].$1,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(
                              _selectedIndex == index
                                  ? Icons.check_rounded
                                  : Icons.chevron_right_rounded,
                              color: _selectedIndex == index
                                  ? options[index].$3
                                  : const Color(0xFF8A94A6),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      if (widget.onAllow != null) {
                        widget.onAllow!();
                        return;
                      }
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Continue',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ClipSnapProSheet extends StatelessWidget {
  const ClipSnapProSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Color(0xFF12121A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Icon(
                Icons.workspace_premium,
                color: Color(0xFFFFD700),
                size: 32,
              ),
              const SizedBox(height: 8),
              const Text(
                'ClipSnap PRO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Unlock AI Effects, 4K Export, & Zero Watermark',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const Spacer(),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Trial flow started.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: const Text(
                  'START FREE TRIAL',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DraftProject {
  final String title;
  final String updatedLabel;
  final String duration;
  final String fileSize;
  final double progress;
  final Color accent;
  final String previewImage;

  const _DraftProject({
    required this.title,
    required this.updatedLabel,
    required this.duration,
    required this.fileSize,
    required this.progress,
    required this.accent,
    required this.previewImage,
  });

  _DraftProject copyWith({String? title}) {
    return _DraftProject(
      title: title ?? this.title,
      updatedLabel: updatedLabel,
      duration: duration,
      fileSize: fileSize,
      progress: progress,
      accent: accent,
      previewImage: previewImage,
    );
  }
}

class HeroVideoBanner extends StatefulWidget {
  final String assetPath;
  final int featuredItemCount;
  final VoidCallback onTryTemplate;

  const HeroVideoBanner({
    super.key,
    required this.assetPath,
    this.featuredItemCount = 1,
    required this.onTryTemplate,
  }) : assert(featuredItemCount > 0);

  @override
  State<HeroVideoBanner> createState() => _HeroVideoBannerState();
}

class _HeroVideoBannerState extends State<HeroVideoBanner>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeVideo());
  }

  Future<void> _initializeVideo() async {
    final controller = VideoPlayerController.asset(
      widget.assetPath,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );

    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0.0);
    } catch (_) {
      await controller.dispose();
      return;
    }

    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _controller = controller;
      _isReady = true;
    });
    unawaited(controller.play());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.resumed) {
      unawaited(controller.play());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(controller.pause());
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return RepaintBoundary(
      child: ScaleButton(
        onTap: widget.onTryTemplate,
        enableRipple: true,
        borderRadius: BorderRadius.zero,
        splashColor: Colors.white.withValues(alpha: 0.12),
        highlightColor: Colors.white.withValues(alpha: 0.05),
        child: SizedBox(
          height: 480,
          width: double.infinity,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: Container(
                  key: const ValueKey('hero-video-placeholder'),
                  color: const Color(0xFF12151E),
                  child: Opacity(
                    opacity: 0.24,
                    child: SvgPicture.asset(
                      'assets/images/clipsnap_hero_art.svg',
                      key: const ValueKey('hero-background-art'),
                      fit: BoxFit.cover,
                      alignment: Alignment.centerRight,
                    ),
                  ),
                ),
              ),
              if (_isReady && controller != null)
                Positioned.fill(
                  child: FittedBox(
                    key: const ValueKey('hero-loop-video'),
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: controller.value.size.width,
                      height: controller.value.size.height,
                      child: VideoPlayer(controller),
                    ),
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.60),
                        Colors.black,
                      ],
                      stops: const [0.4, 0.8, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 58,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'PRO MOTION ENGINE',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xB3FFFFFF),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: widget.onTryTemplate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text(
                        'Try Template',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.featuredItemCount > 1)
                Positioned(
                  bottom: 28,
                  child: Row(
                    key: const ValueKey('hero-page-indicator'),
                    children: [
                      for (int index = 0;
                          index < widget.featuredItemCount;
                          index++) ...[
                        if (index > 0) const SizedBox(width: 8),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: index == 0
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClipSnapBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _ClipSnapBottomNavBar({
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            key: const ValueKey('root-bottom-navigation'),
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xD910121A),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF47C8FF).withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                _buildNavItem(0, Icons.content_cut_rounded, 'Editor'),
                _buildNavItem(1, Icons.graphic_eq_rounded, 'AI Audio Tools'),
                _buildNavItem(2, Icons.person_outline_rounded, 'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final selected = currentIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: MotionSpec.selectionDuration,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF3B82F6).withValues(alpha: 0.20)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color:
                              const Color(0xFF60A5FA).withValues(alpha: 0.28),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                icon,
                color: selected ? const Color(0xFF60A5FA) : Colors.white38,
                size: 20,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? Colors.white : Colors.white38,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool enableRipple;
  final BorderRadius? borderRadius;
  final Color? splashColor;
  final Color? highlightColor;

  const ScaleButton({
    super.key,
    required this.child,
    required this.onTap,
    this.enableRipple = false,
    this.borderRadius,
    this.splashColor,
    this.highlightColor,
  });

  @override
  State<ScaleButton> createState() => _ScaleButtonState();
}

class _ScaleButtonState extends State<ScaleButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scaledChild = AnimatedScale(
      scale: _isPressed ? 0.96 : 1.0,
      duration: const Duration(milliseconds: 100),
      child: widget.child,
    );

    if (!widget.enableRipple) {
      return GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: scaledChild,
      );
    }

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: widget.borderRadius,
        splashColor: widget.splashColor,
        highlightColor: widget.highlightColor,
        onTap: widget.onTap,
        onHighlightChanged: (value) => setState(() => _isPressed = value),
        child: scaledChild,
      ),
    );
  }
}
