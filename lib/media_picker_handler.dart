import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class SafeMediaPicker {
  final ImagePicker _picker = ImagePicker();

  static bool shouldUseNativeGalleryPicker(TargetPlatform platform) {
    return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  }

  Future<File?> _pickViaFilePicker({
    required bool allowImages,
    required bool allowVideos,
  }) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        if (allowImages) ...[
          'jpg',
          'jpeg',
          'png',
          'webp',
          'gif',
          'heic',
          'heif'
        ],
        if (allowVideos) ...['mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm'],
      ],
      allowMultiple: false,
      withData: false,
      lockParentWindow: true,
    );

    final path = result?.files.first.path;
    if (path == null || path.isEmpty) {
      return null;
    }

    return File(path);
  }

  Future<File?> _pickViaImagePicker({
    required bool allowImages,
    required bool allowVideos,
  }) async {
    if (allowImages && !allowVideos) {
      final image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) {
        return null;
      }
      return File(image.path);
    }

    if (allowVideos && !allowImages) {
      final video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video == null) {
        return null;
      }
      return File(video.path);
    }

    return null;
  }

  Future<File?> pickMediaFile({
    bool allowImages = true,
    bool allowVideos = true,
  }) async {
    try {
      final picked = await _pickViaFilePicker(
        allowImages: allowImages,
        allowVideos: allowVideos,
      );
      if (picked != null) {
        return picked;
      }

      return await _pickViaImagePicker(
        allowImages: allowImages,
        allowVideos: allowVideos,
      );
    } catch (error) {
      debugPrint('Error picking media: $error');
      try {
        return await _pickViaImagePicker(
          allowImages: allowImages,
          allowVideos: allowVideos,
        );
      } catch (fallbackError) {
        debugPrint('Fallback image_picker error: $fallbackError');
        return null;
      }
    }
  }

  Future<File?> selectImageFromGallery() async {
    return pickMediaFile(allowImages: true, allowVideos: false);
  }

  Future<File?> selectVideoFromGallery() async {
    return pickMediaFile(allowImages: false, allowVideos: true);
  }

  Future<File?> recordVideoWithCamera() async {
    try {
      final video = await _picker.pickVideo(source: ImageSource.camera);
      if (video == null) {
        return null;
      }
      return File(video.path);
    } catch (error) {
      debugPrint('Error recording video: $error');
      return null;
    }
  }

  Future<File?> retrieveLostMedia() async {
    if (!Platform.isAndroid) {
      return null;
    }

    final LostDataResponse response = await _picker.retrieveLostData();
    if (response.isEmpty) {
      return null;
    }

    if (response.file != null) {
      return File(response.file!.path);
    }

    debugPrint('Lost data error: ${response.exception}');
    return null;
  }
}
