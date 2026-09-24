import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class AIGenerativeTemplateService {
  static const String _backendEndpoint = String.fromEnvironment(
    'RAMBO_BACKEND_ENDPOINT',
  );
  static const String _backendToken = String.fromEnvironment(
    'RAMBO_BACKEND_TOKEN',
  );
  static const String _apiKey = String.fromEnvironment('OPENAI_API_KEY');
  static const String _endpoint = String.fromEnvironment(
    'OPENAI_IMAGE_EDIT_ENDPOINT',
    defaultValue: 'https://api.openai.com/v1/images/edits',
  );
  static const String _model = String.fromEnvironment(
    'OPENAI_IMAGE_MODEL',
    defaultValue: 'gpt-image-1.5',
  );
  static const String _localEndpoint = String.fromEnvironment(
    'CLIPSNAP_LOCAL_AI_ENDPOINT',
    defaultValue: 'http://127.0.0.1:7861/v1/rambo',
  );

  static const String ramboPrompt =
      'Transform the uploaded person into a photorealistic premium jungle '
      'commando movie portrait. Preserve only the uploaded person identity: '
      'keep their exact face, facial structure, skin tone, eyes, expression, '
      'facial hair, hairstyle, and head position recognizable. Do not copy or '
      'introduce any celebrity face. Regenerate everything below the jawline '
      'as an athletic action-hero body in a weathered black tactical tank top, '
      'dark headband, utility harness, arm wraps, and realistic distressed '
      'fabric. Place a large fictional cinematic machine-gun prop naturally '
      'across both hands with correct grip and anatomy. Replace the full '
      'background with a dense rain-soaked tropical jungle battle scene: deep '
      'teal foliage, heavy mist, rainfall, smoke, drifting embers, warm orange '
      'fire and explosions in the distance, dramatic teal-and-orange rim '
      'lighting, shallow depth, and atmospheric perspective. Match generated '
      'neck, body, lighting, shadows, skin texture, and color to the preserved '
      'face with no visible seam. Vertical cinematic poster composition, '
      'subject centered from thighs upward, high dynamic range, sharp face, '
      'realistic pores, detailed fabric and metal, premium 4K movie key art. '
      'No text, no logo, no watermark, no duplicate person, no extra fingers, '
      'no extra limbs, no deformed weapon, no plastic skin, no face change.';

  final http.Client _client;

  AIGenerativeTemplateService({http.Client? client})
      : _client = client ?? http.Client();

  bool get usesCloudProvider => _apiKey.isNotEmpty;

    bool get usesBackend => _backendEndpoint.isNotEmpty;

  String get modelName =>
      usesBackend || usesCloudProvider ? 'ClipSnap AI Backend' : 'Local Realistic Vision V6';

  Future<Uint8List> generateRamboPortrait({
    required Uint8List imageBytes,
    required Uint8List maskBytes,
    String fileName = 'portrait.png',
  }) async {
    if (usesBackend) {
      return _generateThroughBackend(
        imageBytes: imageBytes,
        maskBytes: maskBytes,
        fileName: fileName,
      );
    }
    if (!usesCloudProvider) {
      return _generateLocally(
        imageBytes: imageBytes,
        maskBytes: maskBytes,
        fileName: fileName,
      );
    }

    final request = http.MultipartRequest('POST', Uri.parse(_endpoint))
      ..headers['Authorization'] = 'Bearer $_apiKey'
      ..fields['model'] = _model
      ..fields['prompt'] = ramboPrompt
      ..fields['size'] = '1024x1536'
      ..fields['quality'] = 'high'
      ..fields['input_fidelity'] = 'high'
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: fileName,
        ),
      );

    final streamedResponse = await _client.send(request).timeout(
          const Duration(minutes: 3),
        );
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(_providerError(response));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Image edit response must be a JSON object.');
    }
    final data = decoded['data'];
    if (data is! List || data.isEmpty || data.first is! Map) {
      throw const FormatException(
          'Image edit response has no generated image.');
    }

    final result = Map<String, dynamic>.from(data.first as Map);
    final base64Image = result['b64_json']?.toString();
    if (base64Image != null && base64Image.isNotEmpty) {
      return base64Decode(base64Image);
    }

    final imageUrl = result['url']?.toString();
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final imageResponse = await _client.get(Uri.parse(imageUrl));
      if (imageResponse.statusCode >= 200 && imageResponse.statusCode < 300) {
        return imageResponse.bodyBytes;
      }
    }

    throw const FormatException('Image edit response contains no image data.');
  }

  Future<Uint8List> _generateThroughBackend({
    required Uint8List imageBytes,
    required Uint8List maskBytes,
    required String fileName,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(_backendEndpoint),
    )
      ..headers['Accept'] = 'image/png'
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: fileName,
        ),
      )
      ..files.add(
        http.MultipartFile.fromBytes(
          'mask',
          maskBytes,
          filename: 'mask.png',
        ),
      );
    if (_backendToken.isNotEmpty) {
      request.headers['X-ClipSnap-Token'] = _backendToken;
    }

    final streamedResponse = await _client.send(request).timeout(
          const Duration(minutes: 5),
        );
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'ClipSnap AI backend failed (${response.statusCode}): ${response.body}',
      );
    }
    if (response.bodyBytes.isEmpty) {
      throw const FormatException('ClipSnap AI backend returned no image.');
    }
    return response.bodyBytes;
  }

  Future<Uint8List> _generateLocally({
    required Uint8List imageBytes,
    required Uint8List maskBytes,
    required String fileName,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse(_localEndpoint))
      ..files.add(
        http.MultipartFile.fromBytes('image', imageBytes, filename: fileName),
      )
      ..files.add(
        http.MultipartFile.fromBytes('mask', maskBytes, filename: 'mask.png'),
      );
    final streamedResponse = await _client.send(request).timeout(
          const Duration(minutes: 15),
        );
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    throw StateError(
      'Local AI engine failed (${response.statusCode}). Start '
      'scripts/local_ai_server.py on the connected Mac.',
    );
  }

  String _providerError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          final message = error['message']?.toString();
          if (message != null && message.isNotEmpty) {
            return 'OpenAI image edit failed: $message';
          }
        }
      }
    } catch (_) {}
    return 'OpenAI image edit failed with status ${response.statusCode}.';
  }

  void dispose() {
    _client.close();
  }
}
