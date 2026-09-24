import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/template_model.dart';

Future<bool> exportVideoWithTemplate({
  required String inputPath,
  required String outputPath,
  required VideoTemplate selectedTemplate,
  String? overlayAssetPath,
}) async {
  final resolvedOverlay = await resolveTemplateOverlayAsset(
    overlayAssetPath ??
        selectedTemplate.materialAssetPath ??
        selectedTemplate.overlayAssetPath,
  );
  final command = buildTemplateRenderCommand(
    inputPath: inputPath,
    outputPath: outputPath,
    selectedTemplate: selectedTemplate,
    overlayAssetPath: resolvedOverlay,
    isStillImage: false,
  );

  final session = await FFmpegKit.execute(command);
  final returnCode = await session.getReturnCode();
  return ReturnCode.isSuccess(returnCode);
}

Future<bool> exportImageWithTemplate({
  required String inputPath,
  required String outputPath,
  required VideoTemplate selectedTemplate,
  String? overlayAssetPath,
}) async {
  final resolvedOverlay = await resolveTemplateOverlayAsset(
    overlayAssetPath ??
        selectedTemplate.materialAssetPath ??
        selectedTemplate.overlayAssetPath,
  );
  final command = buildTemplateRenderCommand(
    inputPath: inputPath,
    outputPath: outputPath,
    selectedTemplate: selectedTemplate,
    overlayAssetPath: resolvedOverlay,
    isStillImage: true,
  );

  final session = await FFmpegKit.execute(command);
  final returnCode = await session.getReturnCode();
  return ReturnCode.isSuccess(returnCode);
}

Future<String?> resolveTemplateOverlayAsset(String? assetPath) async {
  if (assetPath == null || assetPath.isEmpty) {
    return null;
  }

  if (!assetPath.startsWith('assets/')) {
    return assetPath;
  }

  final byteData = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final fileName = assetPath.split('/').last;
  final tempFile = File('${tempDir.path}/$fileName');
  await tempFile.writeAsBytes(
    byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    ),
    flush: true,
  );
  return tempFile.path;
}

String buildTemplateRenderCommand({
  required String inputPath,
  required String outputPath,
  required VideoTemplate selectedTemplate,
  String? overlayAssetPath,
  bool isStillImage = false,
}) {
  final resolvedOverlay = overlayAssetPath ??
      selectedTemplate.materialAssetPath ??
      selectedTemplate.overlayAssetPath;
  final escapedInput = _escapePath(inputPath);
  final escapedOutput = _escapePath(outputPath);
  final graph = selectedTemplate.buildFilterGraph(
    overlayAssetPath: resolvedOverlay,
  );
  final metadataTag = selectedTemplate.buildActionMetadata(
    overlayAssetPath: resolvedOverlay,
  );

  final hasOverlay = resolvedOverlay != null && resolvedOverlay.isNotEmpty;
  final beforeFilterInputs = hasOverlay
      ? '-y -i "$escapedInput" ${isStillImage ? "" : "-loop 1 "}'
        '-i "${_escapePath(resolvedOverlay)}" '
      : '-y -i "$escapedInput" ';

  if (hasOverlay) {
    final command =
        '$beforeFilterInputs-filter_complex "$graph" '
        '-map "[v]" -map 0:a? '
        '$metadataTag '
        '${isStillImage ? "-frames:v 1 " : ""}'
        '${isStillImage ? "-c:v png " : "-c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart "}'
        '"$escapedOutput"';
    return command;
  }

  final command =
      '$beforeFilterInputs-vf "$graph" '
      '$metadataTag '
      '${isStillImage ? "-frames:v 1 -c:v png " : "-map 0:v:0 -map 0:a? -c:v libx264 -preset ultrafast -crf 22 -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart "}'
      '"$escapedOutput"';
  return command;
}

String _escapePath(String path) => path.replaceAll('"', '\\"');
