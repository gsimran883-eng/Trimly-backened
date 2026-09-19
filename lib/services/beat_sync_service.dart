import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';

class BeatMarker {
  final int timeMs;
  final double strength;

  const BeatMarker({
    required this.timeMs,
    required this.strength,
  });
}

class BeatSyncService {
  // Uses FFmpeg loudness analysis and peak picking as a lightweight beat proxy.
  Future<List<BeatMarker>> detectBeatMarkers(
    File videoFile, {
    int maxMarkers = 32,
  }) async {
    final command =
        '-i "${videoFile.path}" -vn '
        '-af "aformat=channel_layouts=mono,aresample=11025,ebur128=framelog=verbose" '
        '-f null -';

    final session = await FFmpegKit.execute(command);
    final output = await session.getOutput() ?? '';
    if (output.isEmpty) {
      return const [];
    }

    final samplePattern = RegExp(
      r't:\s*([0-9]+(?:\.[0-9]+)?)\s+TARGET:.*?M:\s*([-]?[0-9]+(?:\.[0-9]+)?)',
    );

    final samples = <({int ms, double loudness})>[];
    for (final match in samplePattern.allMatches(output)) {
      final sec = double.tryParse(match.group(1) ?? '');
      final mLufs = double.tryParse(match.group(2) ?? '');
      if (sec == null || mLufs == null || mLufs <= -120) {
        continue;
      }
      samples.add((ms: (sec * 1000).round(), loudness: mLufs));
    }

    if (samples.length < 3) {
      return const [];
    }

    final rawPeaks = <BeatMarker>[];
    for (var i = 1; i < samples.length - 1; i++) {
      final prev = samples[i - 1].loudness;
      final curr = samples[i].loudness;
      final next = samples[i + 1].loudness;

      final peakOverNeighbors = curr > prev + 1.2 && curr > next + 1.2;
      final loudEnough = curr > -38;

      if (peakOverNeighbors && loudEnough) {
        rawPeaks.add(
          BeatMarker(timeMs: samples[i].ms, strength: curr),
        );
      }
    }

    if (rawPeaks.isEmpty) {
      return const [];
    }

    // Debounce nearby peaks so cuts are editor-friendly.
    final spaced = <BeatMarker>[];
    for (final marker in rawPeaks) {
      if (spaced.isEmpty || marker.timeMs - spaced.last.timeMs >= 220) {
        spaced.add(marker);
      }
    }

    if (spaced.length <= maxMarkers) {
      return spaced;
    }

    final stride = spaced.length / maxMarkers;
    final reduced = <BeatMarker>[];
    for (var i = 0; i < maxMarkers; i++) {
      reduced.add(spaced[(i * stride).floor()]);
    }
    return reduced;
  }
}
