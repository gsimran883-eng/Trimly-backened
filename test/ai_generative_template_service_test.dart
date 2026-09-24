import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_app/services/ai_generative_template_service.dart';

void main() {
  test('no-key Rambo generation sends image and mask to local diffusion',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.toString(), 'http://127.0.0.1:7861/v1/rambo');
      expect(
          request.headers['content-type'], startsWith('multipart/form-data'));
      return http.Response.bytes(Uint8List.fromList([9, 8, 7]), 200);
    });
    final service = AIGenerativeTemplateService(client: client);

    final output = await service.generateRamboPortrait(
      imageBytes: Uint8List.fromList([1, 2, 3]),
      maskBytes: Uint8List.fromList([4, 5, 6]),
    );

    expect(service.modelName, 'Local Realistic Vision V6');
    expect(output, Uint8List.fromList([9, 8, 7]));
    service.dispose();
  });
}
