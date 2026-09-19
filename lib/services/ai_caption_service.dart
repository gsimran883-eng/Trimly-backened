import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

class CaptionSegment {
  final String text;
  final int startMs;

  const CaptionSegment({
    required this.text,
    required this.startMs,
  });
}

class AiCaptionService {
  static const String _endpoint = String.fromEnvironment('AI_CAPTION_ENDPOINT');
  static const String _apiKey = String.fromEnvironment('AI_CAPTION_API_KEY');

  bool get isConfigured => _endpoint.isNotEmpty && _apiKey.isNotEmpty;

  Future<List<CaptionSegment>> generateCaptionsFromVideo(File videoFile) async {
    if (!isConfigured) {
      throw StateError(
        'AI caption service is not configured. Set AI_CAPTION_ENDPOINT and AI_CAPTION_API_KEY.',
      );
    }

    final wavFile = await _extractAudio(videoFile);
    final audioBytes = await wavFile.readAsBytes();

    final payload = jsonEncode({
      'audio_base64': base64Encode(audioBytes),
      'mime_type': 'audio/wav',
      'language': 'en',
      'timestamps': true,
    });

    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(_endpoint));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_apiKey');
      request.write(payload);

      final response = await request.close();
      final responseText = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Caption API failed: ${response.statusCode} $responseText',
          uri: Uri.parse(_endpoint),
        );
      }

      final decoded = jsonDecode(responseText);
      return _parseSegments(decoded);
    } finally {
      client.close(force: true);
      if (await wavFile.exists()) {
        await wavFile.delete();
      }
    }
  }

  Future<File> _extractAudio(File videoFile) async {
    final tmpDir = await getTemporaryDirectory();
    final outputFile = File(
      '${tmpDir.path}/caption_audio_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    final command =
        '-y -i "${videoFile.path}" -vn -acodec pcm_s16le -ar 16000 -ac 1 "${outputFile.path}"';
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode) || !await outputFile.exists()) {
      throw StateError('Failed to extract audio for captions.');
    }

    return outputFile;
  }

  List<CaptionSegment> _parseSegments(dynamic decoded) {
    if (decoded is! Map<String, dynamic>) {
      return const [];
    }

    final rawSegments = decoded['segments'];
    if (rawSegments is List) {
      final segments = <CaptionSegment>[];
      for (final item in rawSegments) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final text = (item['text'] ?? '').toString().trim();
        if (text.isEmpty) {
          continue;
        }
        final startMs = _asStartMs(item);
        segments.add(CaptionSegment(text: text, startMs: startMs));
      }
      return segments;
    }

    final plainText = (decoded['text'] ?? '').toString().trim();
    if (plainText.isNotEmpty) {
      return [CaptionSegment(text: plainText, startMs: 0)];
    }

    return const [];
  }

  int _asStartMs(Map<String, dynamic> item) {
    final direct = item['startMs'] ?? item['start_ms'];
    if (direct is int) {
      return direct;
    }
    if (direct is double) {
      return direct.round();
    }

    final seconds = item['start'] ?? item['startSec'] ?? item['start_seconds'];
    if (seconds is int) {
      return seconds * 1000;
    }
    if (seconds is double) {
      return (seconds * 1000).round();
    }

    return 0;
  }
}
