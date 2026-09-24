class VideoTemplate {
  final String id;
  final String name;
  final String description;
  final String previewImagePath;
  final String? overlayAssetPath;
  final String? materialAssetPath;
  final bool isPremium;
  final bool hasGlitchEffect;
  final String badgeText;
  final String ffmpegFilterGraph;
  final Map<String, Object?> actionPayload;

  const VideoTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.previewImagePath,
    this.overlayAssetPath,
    this.materialAssetPath,
    this.isPremium = false,
    this.hasGlitchEffect = false,
    required this.badgeText,
    required this.ffmpegFilterGraph,
    this.actionPayload = const {},
  });

  Map<String, Object?> get resolvedActionPayload {
    final payload = <String, Object?>{
      'templateId': id,
      'name': name,
      'description': description,
      'subjectMask': false,
      'backgroundReplacement': false,
      'materialAssetPath': materialAssetPath ?? overlayAssetPath,
      'particleOverlay': materialAssetPath ?? overlayAssetPath,
      'backgroundPrompt': description,
      'grade': 'default',
    };

    final mergedPayload = Map<String, Object?>.from(payload)
      ..addAll(actionPayload);

    if (mergedPayload['materialAssetPath'] == null ||
        (mergedPayload['materialAssetPath'] as String).isEmpty) {
      mergedPayload['materialAssetPath'] = overlayAssetPath;
    }
    if (mergedPayload['particleOverlay'] == null ||
        (mergedPayload['particleOverlay'] as String).isEmpty) {
      mergedPayload['particleOverlay'] = mergedPayload['materialAssetPath'];
    }
    if (mergedPayload['backgroundPrompt'] == null ||
        (mergedPayload['backgroundPrompt'] as String).isEmpty) {
      mergedPayload['backgroundPrompt'] = description;
    }
    return mergedPayload;
  }

  String buildActionMetadata({String? overlayAssetPath}) {
    final payload = Map<String, Object?>.from(resolvedActionPayload);
    final materialAsset = overlayAssetPath ??
        payload['materialAssetPath'] as String? ??
        this.overlayAssetPath;
    if (materialAsset != null && materialAsset.isNotEmpty) {
      payload['materialAssetPath'] = materialAsset;
    }
    if (payload['particleOverlay'] == null ||
        (payload['particleOverlay'] as String?)?.isEmpty == true) {
      payload['particleOverlay'] = materialAsset;
    }
    final metadata = <String>[
      '-metadata template_id=${_quoteMetadata(payload['templateId'] ?? id)}',
      '-metadata subject_mask=${(payload['subjectMask'] == true) ? 1 : 0}',
      '-metadata background_replacement=${(payload['backgroundReplacement'] == true) ? 1 : 0}',
      '-metadata background_prompt=${_quoteMetadata(payload['backgroundPrompt'] ?? description)}',
      if (materialAsset != null && materialAsset.isNotEmpty)
        '-metadata material_asset=${_quoteMetadata(materialAsset)}',
      if (payload['particleOverlay'] != null &&
          (payload['particleOverlay'] as String).isNotEmpty)
        '-metadata particle_overlay=${_quoteMetadata(payload['particleOverlay'])}',
      if (payload['grade'] != null && (payload['grade'] as String).isNotEmpty)
        '-metadata grade=${_quoteMetadata(payload['grade'])}',
    ];
    return metadata.join(' ');
  }

  String buildFFmpegFilter() {
    if (id == 'retro_80s_vhs') {
      return '$ffmpegFilterGraph,noise=alls=15:allf=t+u,chromashift=cbh=2:crh=-2,drawgrid=w=iw:h=4:t=1:c=black@0.22,vignette=PI/5';
    }
    if (id == 'cyber_glitch_v2') {
      return '$ffmpegFilterGraph,noise=alls=12:allf=t+u,chromashift=cbh=3:crh=-3,drawgrid=w=iw:h=6:t=1:c=0xff00ffff@0.16';
    }
    if (id == 'neon_velocity') {
      return '$ffmpegFilterGraph,chromashift=cbh=4:crh=-4,drawgrid=w=iw/3:h=ih/3:t=2:c=0x00e5ffff@0.24,vignette=PI/4';
    }
    if (id == 'holo_matrix') {
      return '$ffmpegFilterGraph,drawgrid=w=80:h=80:t=1:c=0x00ffffff@0.2,drawbox=x=iw*0.08:y=ih*0.08:w=iw*0.84:h=ih*0.84:color=0x00ffffff@0.28:t=2';
    }
    if (id == 'quantum_cinematic') {
      return '$ffmpegFilterGraph,drawbox=x=0:y=0:w=iw:h=ih*0.09:color=black:t=fill,drawbox=x=0:y=ih*0.91:w=iw:h=ih*0.09:color=black:t=fill,drawbox=x=iw*0.04:y=ih*0.04:w=iw*0.92:h=ih*0.92:color=0xffffcc88@0.35:t=2';
    }
    if (hasGlitchEffect) {
      return '$ffmpegFilterGraph,noise=alls=15:allf=t+u';
    }
    return ffmpegFilterGraph;
  }

  String buildFilterGraph({String? overlayAssetPath}) {
    final resolvedOverlay =
        overlayAssetPath ?? materialAssetPath ?? this.overlayAssetPath;
    if (resolvedOverlay == null || resolvedOverlay.isEmpty) {
      return buildFFmpegFilter();
    }

    switch (id) {
      case 'rambo_action':
        return '[1:v]scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280,'
            'eq=contrast=1.18:saturation=1.24:brightness=-0.04,gblur=sigma=1.2[background]; '
            '[0:v]scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280,split=2[subjectSource][maskSource]; '
            '[maskSource]format=gray,geq=lum=\'255*exp(-4*(pow((X-W/2)/(W*0.38),2)+pow((Y-H*0.5)/(H*0.56),2)))\','
            'gblur=sigma=18[subjectMask]; '
            '[subjectSource]format=rgba,${buildFFmpegFilter()},unsharp=5:5:1.15:5:5:0[subjectRgba]; '
            '[subjectRgba][subjectMask]alphamerge[subject]; '
            '[background][subject]overlay=0:0:shortest=1,'
            'drawbox=x=0:y=0:w=iw:h=ih*0.035:color=0xff9d42@0.45:t=fill,'
            'drawbox=x=0:y=ih*0.965:w=iw:h=ih*0.035:color=black@0.72:t=fill,'
            'vignette=PI/4,eq=contrast=1.12:saturation=1.18[v]';
      case 'cinderella_ballroom':
        return '[0:v]scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280,${buildFFmpegFilter()}[base]; '
            '[1:v]scale=720:1280,format=rgba,colorchannelmixer=aa=0.58[overlay]; '
            '[base][overlay]overlay=0:0:shortest=1,eq=brightness=0.08:contrast=1.2:saturation=1.35[v]';
      case 'cyberpunk_tokyo':
        return '[0:v]scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280,${buildFFmpegFilter()}[base]; '
            '[1:v]scale=720:1280,format=rgba,colorkey=0x000000:0.12:0.08[overlay]; '
            '[base][overlay]overlay=0:0[v]';
      case 'cyber_glitch_v2':
        return '[0:v]scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280,${buildFFmpegFilter()}[base]; '
            '[1:v]scale=720:1280,chromakey=0x8f3e29:0.3:0.08,format=rgba,colorchannelmixer=aa=0.72[overlay]; '
            '[base][overlay]overlay=0:0[v]';
      case 'retro_80s_vhs':
        return '[0:v]scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280,${buildFFmpegFilter()}[base]; '
            '[1:v]scale=720:1280,chromakey=0x8f3e29:0.3:0.08,format=rgba,colorchannelmixer=aa=0.72[overlay]; '
            '[base][overlay]overlay=0:0[v]';
      default:
        return '[0:v]scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280,${buildFFmpegFilter()}[base]; '
            '[1:v]scale=720:1280,format=rgba,colorchannelmixer=aa=0.42[overlay]; '
            '[base][overlay]overlay=0:0[v]';
    }
  }

  static String _quoteMetadata(Object? value) {
    final text = value.toString().replaceAll('"', '\\"');
    return '"$text"';
  }
}