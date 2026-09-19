import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/media_picker_handler.dart';

void main() {
  group('SafeMediaPicker', () {
    test('uses native gallery picker on mobile platforms', () {
      expect(SafeMediaPicker.shouldUseNativeGalleryPicker(TargetPlatform.android), isTrue);
      expect(SafeMediaPicker.shouldUseNativeGalleryPicker(TargetPlatform.iOS), isTrue);
      expect(SafeMediaPicker.shouldUseNativeGalleryPicker(TargetPlatform.macOS), isFalse);
      expect(SafeMediaPicker.shouldUseNativeGalleryPicker(TargetPlatform.windows), isFalse);
    });
  });
}
