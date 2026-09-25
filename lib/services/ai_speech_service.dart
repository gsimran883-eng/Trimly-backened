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
            ),
        _provider = _detectProvider(
          apiKey: apiKey,
          baseUrl: baseUrl,
        );

  final String _apiKey;
  final String _baseUrl;
  final String _provider;

  bool get isConfigured => _apiKey.isNotEmpty;

  static String _detectProvider({String? apiKey, String? baseUrl}) {
    final explicitApiKey = apiKey ??
        const String.fromEnvironment(
          'ELEVENLABS_API_KEY',
          defaultValue: '',
        );
    if (explicitApiKey.isNotEmpty) {
      return 'elevenlabs';
    }

    final openAiKey = const String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');
    if (openAiKey.isNotEmpty) {
      return 'openai';
    }

    final configuredBase = baseUrl ??
        const String.fromEnvironment(
          'ELEVENLABS_BASE_URL',
          defaultValue: '',
        );
    if (configuredBase.isNotEmpty && configuredBase.contains('openai')) {
      return 'openai';
    }

    return 'elevenlabs';
  }

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
        'AISpeechService is not configured. Set ELEVENLABS_API_KEY or OPENAI_API_KEY with --dart-define.',
      );
    }

    if (_provider == 'openai') {
      return _generateWithOpenAI(
        text: text,
        outputFormat: outputFormat,
      );
    }

    return _generateWithElevenLabs(
      text: text,
      voiceId: voiceId,
      modelId: modelId,
      outputFormat: outputFormat,
    );
  }

  Future<File?> _generateWithOpenAI({
    required String text,
    required String outputFormat,
  }) async {
    final endpoint = const String.fromEnvironment(
      'OPENAI_TTS_ENDPOINT',
      defaultValue: 'https://api.openai.com/v1/audio/speech',
    );

    final response = await http.post(
      Uri.parse(endpoint),
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer $_apiKey',
        HttpHeaders.contentTypeHeader: 'application/json',
      },
      body: jsonEncode({
        'model': 'tts-1',
        'input': text,
        'voice': 'onyx',
        'response_format': outputFormat,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'OpenAI TTS failed: ${response.statusCode} ${response.body}',
        uri: Uri.parse(endpoint),
      );
    }

    final tempDir = await getTemporaryDirectory();
    final filePath =
        '${tempDir.path}/speech_${DateTime.now().millisecondsSinceEpoch}.$outputFormat';
    final file = File(filePath);
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file;
  }

  Future<File?> _generateWithElevenLabs({
    required String text,
    required String voiceId,
    required String modelId,
    required String outputFormat,
  }) async {
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
