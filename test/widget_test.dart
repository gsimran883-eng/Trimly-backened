// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_app/main.dart';
import 'package:my_app/screens/clip_snap_studio_editor.dart';
import 'package:my_app/services/export_status_service.dart';
import 'package:my_app/widgets/app_feedback.dart';
import 'package:my_app/widgets/throttled_video_scrubber.dart';

void main() {
  testWidgets('Home screen exposes the main editor entry points', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ClipSnapApp());
    final verticalScrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text && (widget.data ?? '').toLowerCase() == 'clipsnap',
      ),
      findsOneWidget,
    );
    expect(find.text('Continue Editing: Gaming Highlight Reel'), findsNothing);
    expect(find.text('Try Template'), findsOneWidget);
    expect(find.text('Gameing Highlight Reel'), findsNothing);
    expect(find.text('AI Voiceover'), findsOneWidget);
    expect(find.text('Audio Extractor'), findsOneWidget);
    expect(find.text('Local Files'), findsOneWidget);
    expect(find.text('Templates'), findsOneWidget);
    expect(find.text('Neon Velocity'), findsOneWidget);
    expect(find.text('Cyber Glitch V2'), findsOneWidget);
    final templateCarousel = find.byKey(
      const ValueKey('studio-templates-grid'),
    );
    expect(templateCarousel, findsOneWidget);
    expect(find.text('Holographic Matrix'), findsNothing);
    expect(find.text('Quantum Cinema'), findsNothing);
    expect(
        find.byKey(const ValueKey('root-bottom-navigation')), findsOneWidget);
    expect(find.text('Editor'), findsOneWidget);
    expect(find.text('AI Audio Tools'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.byKey(const ValueKey('ratio-launch-9:16')), findsNothing);

    await tester.scrollUntilVisible(
      find.text('MY DRAFTS'),
      220,
      scrollable: verticalScrollable.first,
    );
    expect(find.text('MY DRAFTS'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('draft-card-Gaming Highlight Reel')),
      180,
      scrollable: verticalScrollable.first,
    );
    expect(find.text('Gaming Highlight Reel'), findsWidgets);
  });

  testWidgets('Draft cards include aspect-ratio badges and premium styling', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(const ClipSnapApp());
    await tester.pump();
    final verticalScrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('draft-card-Gaming Highlight Reel')),
      260,
      scrollable: verticalScrollable.first,
    );

    expect(find.text('9:16'), findsWidgets);
    expect(find.text('16:9'), findsWidgets);
  });

  testWidgets(
      'Home screen hero art loads without unsupported SVG filter warnings', (
    WidgetTester tester,
  ) async {
    final logs = <String>[];

    await runZoned(() async {
      await tester.pumpWidget(const ClipSnapApp());
      await tester.pump();
    }, zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        logs.add(line);
      },
    ));

    expect(
      logs.any((line) => line.contains('unhandled element <filter/>')),
      isFalse,
    );
  });

  testWidgets('Home creation and draft cards fit a narrow phone', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(const ClipSnapApp());
    await tester.pump(const Duration(seconds: 1));
    final verticalScrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );

    expect(find.text('Try Template'), findsOneWidget);
    expect(find.byKey(const ValueKey('hero-background-art')), findsOneWidget);
    expect(find.byKey(const ValueKey('hero-page-indicator')), findsNothing);
    expect(find.text('PRO'), findsOneWidget);
    expect(find.byTooltip('Profile'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('draft-card-Gaming Highlight Reel')),
      260,
      scrollable: verticalScrollable.first,
    );
    expect(find.byTooltip('Search drafts'), findsOneWidget);
    expect(find.byTooltip('Sort drafts'), findsOneWidget);
    expect(find.text('Gaming Highlight Reel'), findsWidgets);
    expect(
        find.byKey(const ValueKey('continue-editing-progress')), findsNothing);
    expect(find.byKey(const ValueKey('hero-action-Pick Video')), findsNothing);
    expect(find.byKey(const ValueKey('hero-action-Record')), findsNothing);
    expect(find.byKey(const ValueKey('draft-filter-strip')), findsNothing);
    expect(
        find.byKey(const ValueKey('root-bottom-navigation')), findsOneWidget);
    expect(find.text('Edited 2h ago • 00:45'), findsOneWidget);
    expect(
        find.text(
            'Tip: Export in full 4K with zero watermarks on any project.'),
        findsNothing);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('draft-title-content')).first)
          .width,
      greaterThanOrEqualTo(120),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Draft cards expose management actions on long press', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(const ClipSnapApp());
    await tester.pump(const Duration(seconds: 1));
    final verticalScrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('draft-card-Gaming Highlight Reel')),
      260,
      scrollable: verticalScrollable.first,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.longPress(
      find.byKey(const ValueKey('draft-card-Gaming Highlight Reel')),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Quick Export'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Duplicate'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Gaming Highlight Reel Copy'), findsWidgets);
  });

  testWidgets('Bottom navigation exposes AI audio and profile tabs', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(const ClipSnapApp());
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('AI Audio Tools'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('AI Voiceover'), findsOneWidget);
    expect(find.text('Audio Extractor'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Settings & Export Preferences'), findsOneWidget);
    expect(find.text('ClipSnap Pro'), findsOneWidget);
  });

  test('ExportStatusService publishes render lifecycle', () {
    final service = ExportStatusService.instance;

    service.start('Exporting test clip');
    service.update(0.74);
    expect(service.status.value.isActive, isTrue);
    expect(service.status.value.progress, 0.74);

    service.finish(success: true);
    expect(service.status.value.isActive, isFalse);
    expect(service.status.value.succeeded, isTrue);
  });

  testWidgets('Editor exposes import and editing controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: EditorHomePage(initialIndex: 0)),
    );

    expect(find.text('Import Media'), findsOneWidget);
    expect(find.text('Adjust'), findsOneWidget);
    expect(find.text('Filters'), findsOneWidget);
  });

  testWidgets('Adjust subtools fit on a narrow phone', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(MaterialApp(home: ClipSnapStudioEditor()));
    await tester.tap(find.text('Color Grade'));
    await tester.pumpAndSettle();

    expect(find.text('Brightness'), findsOneWidget);
    expect(find.text('Contrast'), findsOneWidget);
    expect(find.text('Saturation'), findsOneWidget);
    expect(find.text('Warmth'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('App feedback uses the dark floating SnackBar style', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ClipSnapApp(),
    );

    final context = tester.element(find.byType(Scaffold).first);
    final theme = Theme.of(context).snackBarTheme;
    expect(theme.behavior, SnackBarBehavior.floating);
    expect(theme.backgroundColor, const Color(0xEB1E2230));
    expect(theme.insetPadding, const EdgeInsets.fromLTRB(16, 0, 16, 84));

    showAppFeedback(
      context,
      'Audio extracted & video muted',
      kind: FeedbackKind.success,
    );
    await tester.pump();

    expect(find.text('Audio extracted & video muted'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets('Audio tool exposes the AI voiceover controls', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(MaterialApp(home: ClipSnapStudioEditor()));
    expect(find.byTooltip('Mute preview audio'), findsOneWidget);
    await tester.tap(find.byTooltip('Mute preview audio'));
    await tester.pump();
    expect(find.byTooltip('Unmute preview audio'), findsOneWidget);

    await tester.tap(find.text('AI Audio Clean'));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('editor-tool-bottom-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('audio-category-tabs')), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Editing'), findsOneWidget);
    expect(find.text('Voice'), findsOneWidget);
    expect(find.text('Extract Audio from Video'), findsOneWidget);
    expect(find.text('Detach Audio'), findsOneWidget);
    expect(find.text('Mute Original Video Audio'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('original-audio-mute-toggle')),
          )
          .value,
      isFalse,
    );

    await tester.tap(find.text('Voice'));
    await tester.pumpAndSettle();

    expect(find.text('Voiceover Track'), findsOneWidget);
    expect(find.text('AI Generate'), findsOneWidget);
  });

  testWidgets('Studio tools share a dismissible bottom sheet', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(MaterialApp(home: ClipSnapStudioEditor()));
    expect(
        find.byKey(const ValueKey('editor-tool-bottom-sheet')), findsNothing);

    for (final tool in ['Color Grade', 'Canvas Ratio', 'Speed Ramp']) {
      await tester.tap(find.text(tool));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('editor-tool-bottom-sheet')),
        findsOneWidget,
      );
    }

    await tester.tap(find.byTooltip('Close tool panel'));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('editor-tool-bottom-sheet')), findsNothing);
  });

  test('scrubPositionForOffset clamps and maps timeline positions', () {
    const duration = Duration(minutes: 90);

    expect(
      scrubPositionForOffset(dx: 50, width: 100, duration: duration),
      const Duration(minutes: 45),
    );
    expect(
      scrubPositionForOffset(dx: -10, width: 100, duration: duration),
      Duration.zero,
    );
    expect(
      scrubPositionForOffset(dx: 120, width: 100, duration: duration),
      duration,
    );
  });

  testWidgets('Text and sticker tools expose interactive controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: EditorHomePage(initialIndex: 0)),
    );

    await tester.tap(find.byKey(const ValueKey('tool-text')));
    await tester.pumpAndSettle();

    expect(find.text('Text Overlay'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tool-stickers')));
    await tester.pumpAndSettle();

    expect(find.text('Sticker Pack'), findsOneWidget);
  });

  test('readPickedBytes reads bytes from a real file path', () async {
    final tempDir = await Directory.systemTemp.createTemp('clipsnap-test');
    addTearDown(() => tempDir.delete(recursive: true));

    final file = File('${tempDir.path}/sample.bin');
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    await file.writeAsBytes(bytes);

    final result = await readPickedBytes(
      PlatformFile(
          path: file.path,
          name: file.uri.pathSegments.last,
          size: bytes.length),
    );

    expect(result, bytes);
  });

  test('buildWaveformSamples returns normalized PCM peaks', () {
    final pcm = ByteData(8)
      ..setInt16(0, 0, Endian.little)
      ..setInt16(2, 16384, Endian.little)
      ..setInt16(4, -32768, Endian.little)
      ..setInt16(6, 8192, Endian.little);

    final samples = buildWaveformSamples(
      pcm.buffer.asUint8List(),
      bucketCount: 2,
    );

    expect(samples, hasLength(2));
    expect(samples[0], closeTo(0.5, 0.001));
    expect(samples[1], 1.0);
  });
}
