import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class AIImageCloudService {
  static const String _apiKey = String.fromEnvironment('AI_IMAGE_API_KEY');
  static const String _upscaleEndpoint = String.fromEnvironment(
    'AI_IMAGE_UPSCALE_ENDPOINT',
  );
  static const String _skyReplaceEndpoint = String.fromEnvironment(
    'AI_IMAGE_SKY_ENDPOINT',
  );

  bool get isConfigured =>
      _apiKey.isNotEmpty &&
      _upscaleEndpoint.isNotEmpty &&
      _skyReplaceEndpoint.isNotEmpty;

  Future<Uint8List> upscaleImage({
    required Uint8List imageBytes,
    required String multiplier,
    Uint8List? maskBytes,
  }) async {
    _ensureConfigured();

    final payload = <String, dynamic>{
      'imageBase64': base64Encode(imageBytes),
      'scale': multiplier,
      'format': 'png',
      if (maskBytes != null) 'maskBase64': base64Encode(maskBytes),
    };

    return _postAndExtractImage(
      endpoint: _upscaleEndpoint,
      payload: payload,
      operation: 'upscale',
    );
  }

  Future<Uint8List> replaceSky({
    required Uint8List imageBytes,
    required String preset,
    Uint8List? subjectMaskBytes,
  }) async {
    _ensureConfigured();

    final payload = <String, dynamic>{
      'imageBase64': base64Encode(imageBytes),
      'preset': preset,
      'format': 'png',
      if (subjectMaskBytes != null)
        'subjectMaskBase64': base64Encode(subjectMaskBytes),
    };

    return _postAndExtractImage(
      endpoint: _skyReplaceEndpoint,
      payload: payload,
      operation: 'sky_replace',
    );
  }

  Future<Uint8List> _postAndExtractImage({
    required String endpoint,
    required Map<String, dynamic> payload,
    required String operation,
  }) async {
    final response = await http.post(
      Uri.parse(endpoint),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Cloud AI $operation failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Cloud AI response must be a JSON object.');
    }

    final imageBase64 = decoded['imageBase64']?.toString();
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      return base64Decode(imageBase64);
    }

    final imageUrl = decoded['imageUrl']?.toString();
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final fetch = await http.get(Uri.parse(imageUrl));
      if (fetch.statusCode < 200 || fetch.statusCode >= 300) {
        throw StateError(
          'Cloud AI image fetch failed: ${fetch.statusCode} ${fetch.body}',
        );
      }
      return fetch.bodyBytes;
    }

    throw const FormatException(
      'Cloud AI response missing imageBase64 or imageUrl fields.',
    );
  }

  void _ensureConfigured() {
    if (isConfigured) {
      return;
    }
    throw StateError(
      'AIImageCloudService is not configured. Set AI_IMAGE_API_KEY, AI_IMAGE_UPSCALE_ENDPOINT, and AI_IMAGE_SKY_ENDPOINT via --dart-define.',
    );
  }
}
