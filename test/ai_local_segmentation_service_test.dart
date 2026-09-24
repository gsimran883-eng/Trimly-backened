import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/services/ai_local_segmentation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('clipsnap/ai');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('face-preserve mask sends the source image to Android', () async {
    final source = Uint8List.fromList([1, 2, 3]);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'createFacePreserveMask');
      final arguments = call.arguments as Map<Object?, Object?>;
      expect(arguments['imageBytes'], source);
      return <String, Object?>{
        'imageBytes': Uint8List.fromList([7, 8, 9]),
      };
    });

    final result =
        await AILocalSegmentationService().createFacePreserveMask(source);

    expect(result, Uint8List.fromList([7, 8, 9]));
  });
}
