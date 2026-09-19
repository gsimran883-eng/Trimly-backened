import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class AIVoiceService {
  static const String _apiKey = String.fromEnvironment('OPENAI_API_KEY');
  static const String _endpoint = String.fromEnvironment(
    'OPENAI_TTS_ENDPOINT',
    defaultValue: 'https://api.openai.com/v1/audio/speech',
  );

  bool get isConfigured => _apiKey.isNotEmpty;

  /// Generates an MP3 file from text and returns the local file.
  Future<File?> generateVoiceover({
    required String text,
    String model = 'tts-1',
    String voice = 'onyx',
  }) async {
    if (!isConfigured) {
      throw StateError(
        'AIVoiceService is not configured. Set OPENAI_API_KEY with --dart-define.',
      );
    }

    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer $_apiKey',
        HttpHeaders.contentTypeHeader: 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'input': text,
        'voice': voice,
        'format': 'mp3',
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Voice generation failed: ${response.statusCode} ${response.body}',
        uri: Uri.parse(_endpoint),
      );
    }

    final tempDir = await getTemporaryDirectory();
    final filePath =
        '${tempDir.path}/voiceover_${DateTime.now().millisecondsSinceEpoch}.mp3';
    final file = File(filePath);
    await file.writeAsBytes(response.bodyBytes);
    return file;
  }
}
