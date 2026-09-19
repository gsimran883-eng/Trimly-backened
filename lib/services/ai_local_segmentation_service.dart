import 'package:flutter/services.dart';

class AILocalSegmentationService {
  static const MethodChannel _channel = MethodChannel('clipsnap/ai');

  Future<Uint8List> segmentSubject(Uint8List imageBytes) async {
    final response = await _channel.invokeMethod<Object?>('segmentSubject', {
      'imageBytes': imageBytes,
    });

    if (response is! Map) {
      throw const FormatException('segmentSubject response must be a map.');
    }

    final bytes = response['imageBytes'];
    if (bytes is Uint8List) {
      return bytes;
    }
    if (bytes is List<int>) {
      return Uint8List.fromList(bytes);
    }

    throw const FormatException('segmentSubject response missing imageBytes.');
  }
}
