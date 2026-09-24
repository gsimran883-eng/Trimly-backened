import 'package:flutter_test/flutter_test.dart';

import 'package:my_app/data/template_presets.dart';
import 'package:my_app/services/ai_generative_template_service.dart';
import 'package:my_app/services/template_render_service.dart';

void main() {
  test('cyber glitch template builds a layered FFmpeg graph with an overlay',
      () {
    final template =
        clipSnapTemplates.firstWhere((item) => item.id == 'cyber_glitch_v2');

    final graph =
        template.buildFilterGraph(overlayAssetPath: template.overlayAssetPath);

    expect(graph,
        contains('[0:v]scale=720:1280:force_original_aspect_ratio=increase'));
    expect(graph, contains('overlay=0:0'));
    expect(graph, contains('[1:v]scale=720:1280'));
  });

  test('render command includes a second input when overlay assets are present',
      () {
    final template =
        clipSnapTemplates.firstWhere((item) => item.id == 'cyber_glitch_v2');

    final command = buildTemplateRenderCommand(
      inputPath: '/tmp/input.mp4',
      outputPath: '/tmp/output.mp4',
      selectedTemplate: template,
      overlayAssetPath: '/tmp/overlay.png',
    );

    expect(command, contains('-i "/tmp/input.mp4"'));
    expect(command, contains('-loop 1 -i "/tmp/overlay.png"'));
    expect(command, contains('-i "/tmp/overlay.png"'));
    expect(command, contains('-filter_complex'));
    expect(command, contains('overlay=0:0'));
  });

  test('retro VHS template builds a warm layered graph', () {
    final template =
        clipSnapTemplates.firstWhere((item) => item.id == 'retro_80s_vhs');

    final graph = template.buildFilterGraph(
      overlayAssetPath: template.overlayAssetPath,
    );

    expect(graph, contains('colorbalance=rh=0.3:gh=0.1:bh=-0.3'));
    expect(graph, contains('gblur=sigma=0.6'));
    expect(graph, contains('noise=alls=15:allf=t+u'));
    expect(graph, contains('chromashift=cbh=2:crh=-2'));
    expect(graph, contains('drawgrid=w=iw:h=4'));
    expect(graph, contains('vignette=PI/5'));
    expect(graph, contains('chromakey=0x8f3e29:0.3:0.08'));
    expect(graph, contains('colorchannelmixer=aa=0.72'));
    expect(graph, contains('[base][overlay]overlay=0:0[v]'));
  });

  test('Cyberpunk HUD removes its opaque black background', () {
    final template =
        clipSnapTemplates.firstWhere((item) => item.id == 'cyberpunk_tokyo');

    final graph = template.buildFilterGraph(
      overlayAssetPath: template.overlayAssetPath,
    );

    expect(graph, contains('colorkey=0x000000:0.12:0.08'));
  });

  test('non-overlay templates still build graphic treatment filters', () {
    final neon =
        clipSnapTemplates.firstWhere((item) => item.id == 'neon_velocity');
    final holo =
        clipSnapTemplates.firstWhere((item) => item.id == 'holo_matrix');
    final quantum =
        clipSnapTemplates.firstWhere((item) => item.id == 'quantum_cinematic');

    expect(neon.buildFilterGraph(), contains('drawgrid='));
    expect(holo.buildFilterGraph(), contains('drawbox='));
    expect(quantum.buildFilterGraph(), contains('drawbox=x=0:y=0'));
  });

  test(
      'template id maps to a unique action payload with subject and environment data',
      () {
    final rambo =
        clipSnapTemplates.firstWhere((item) => item.id == 'rambo_action');
    final ballroom = clipSnapTemplates
        .firstWhere((item) => item.id == 'cinderella_ballroom');

    expect(rambo.actionPayload['subjectMask'], isTrue);
    expect(rambo.actionPayload['backgroundPrompt'], contains('jungle'));
    expect(rambo.actionPayload['materialAssetPath'], contains('assets/'));

    expect(ballroom.actionPayload['grade'], equals('warm_cinematic'));
    expect(ballroom.actionPayload['particleOverlay'], contains('sparkles'));
    expect(ballroom.actionPayload['backgroundPrompt'], contains('ballroom'));
  });

  test(
      'render command carries the template action recipe into the export pipeline',
      () {
    final template =
        clipSnapTemplates.firstWhere((item) => item.id == 'rambo_action');

    final command = buildTemplateRenderCommand(
      inputPath: '/tmp/input.mp4',
      outputPath: '/tmp/output.mp4',
      selectedTemplate: template,
      overlayAssetPath: template.actionPayload['materialAssetPath'] as String?,
    );

    expect(command, contains('template_id="rambo_action"'));
    expect(command, contains('subject_mask=1'));
    expect(command, contains('background_prompt="dense jungle combat scene'));
  });

  test(
      'action templates stack a real overlay layer instead of only a filter grade',
      () {
    final rambo =
        clipSnapTemplates.firstWhere((item) => item.id == 'rambo_action');
    final ballroom = clipSnapTemplates
        .firstWhere((item) => item.id == 'cinderella_ballroom');

    final ramboGraph = rambo.buildFilterGraph(
      overlayAssetPath: rambo.materialAssetPath ?? rambo.overlayAssetPath,
    );
    final ballroomGraph = ballroom.buildFilterGraph(
      overlayAssetPath: ballroom.materialAssetPath ?? ballroom.overlayAssetPath,
    );

    expect(ramboGraph, contains('[1:v]scale=720:1280'));
    expect(ramboGraph, contains('overlay=0:0'));
    expect(ballroomGraph, contains('[1:v]scale=720:1280'));
    expect(ballroomGraph, contains('overlay=0:0'));
  });

  test('Rambo replaces the scene and preserves an enhanced subject layer', () {
    final rambo =
        clipSnapTemplates.firstWhere((item) => item.id == 'rambo_action');
    final graph = rambo.buildFilterGraph(
      overlayAssetPath: rambo.materialAssetPath,
    );

    expect(rambo.materialAssetPath, contains('rambo_jungle_backdrop.jpg'));
    expect(graph, contains('[background]'));
    expect(graph, contains('[subject]'));
    expect(graph, contains('alphamerge'));
    expect(graph, contains('gblur=sigma=18'));
    expect(graph, contains('unsharp='));
    expect(graph, contains('[v]'));
  });

  test('Rambo requests a high-fidelity generative clothing transformation', () {
    final rambo =
        clipSnapTemplates.firstWhere((item) => item.id == 'rambo_action');

    expect(rambo.actionPayload['generativeEdit'], isTrue);
    expect(rambo.actionPayload['preserveFace'], isTrue);
    expect(AIGenerativeTemplateService.ramboPrompt,
        contains('uploaded person identity'));
    expect(AIGenerativeTemplateService.ramboPrompt, contains('machine-gun'));
    expect(AIGenerativeTemplateService.ramboPrompt, contains('rainfall'));
    expect(AIGenerativeTemplateService.ramboPrompt, contains('premium 4K'));
    expect(
      AIGenerativeTemplateService().modelName,
      'Local Realistic Vision V6',
    );
  });
}
