import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class AISpeechService {
  AISpeechService({
    String? apiKey,
    String? baseUrl,
  })  : _apiKey = apiKey ??
            const String.fromEnvironment(
              'ELEVENLABS_API_KEY',
              defaultValue: String.fromEnvironment(
                'OPENAI_API_KEY',
                defaultValue: '',
              ),
            ),
        _baseUrl = baseUrl ??
            const String.fromEnvironment(
              'ELEVENLABS_BASE_URL',
              defaultValue: String.fromEnvironment(
                'OPENAI_TTS_ENDPOINT',
                defaultValue: 'https://api.elevenlabs.io/v1',
              ),
            );

  final String _apiKey;
  final String _baseUrl;

  bool get isConfigured => _apiKey.isNotEmpty;

  /// Generates speech from text and saves it as an audio file on device.
  Future<File?> generateSpeech({
    required String text,
    required String voiceId,
    String modelId = 'eleven_multilingual_v2',
    String outputFormat = 'mp3',
  }) async {
    if (text.trim().isEmpty) {
      throw ArgumentError.value(text, 'text', 'Text cannot be empty.');
    }

    if (!isConfigured) {
      throw StateError(
        'AISpeechService is not configured. Set ELEVENLABS_API_KEY with --dart-define.',
      );
    }

    final url = Uri.parse('$_baseUrl/text-to-speech/$voiceId');

    final response = await http.post(
      url,
      headers: {
        HttpHeaders.acceptHeader: 'audio/$outputFormat',
        HttpHeaders.contentTypeHeader: 'application/json',
        'xi-api-key': _apiKey,
      },
      body: jsonEncode({
        'text': text,
        'model_id': modelId,
        'voice_settings': {
          'stability': 0.5,
          'similarity_boost': 0.75,
        },
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 402) {
        throw StateError(
          'ElevenLabs text-to-speech needs available credits or an active billing plan.',
        );
      }
      throw HttpException(
        'AI speech generation failed: ${response.statusCode} ${response.body}',
        uri: url,
      );
    }

    final tempDir = await getTemporaryDirectory();
    final filePath =
        '${tempDir.path}/speech_${DateTime.now().millisecondsSinceEpoch}.$outputFormat';
    final file = File(filePath);
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file;
  }
}
