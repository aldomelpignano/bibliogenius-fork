import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class CoverCameraHelper {
  static final _picker = ImagePicker();

  /// Whether the current platform supports camera capture.
  static bool get isCameraAvailable =>
      _picker.supportsImageSource(ImageSource.camera);

  /// Opens the camera, saves the photo into covers/ and returns the local path.
  /// Returns null if the user cancelled or the camera is unavailable.
  /// When [bookId] is known (edit flow), the file is named `<bookId>.jpg`.
  /// When [bookId] is null (add flow), a temp UUID name is used.
  static Future<String?> takePhotoAndSave({int? bookId}) async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1200,
      maxHeight: 1800,
      imageQuality: 85,
    );
    if (photo == null) return null;

    final appDir = await getApplicationSupportDirectory();
    final coversDir = Directory('${appDir.path}/covers');
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }

    final fileName = bookId != null ? '$bookId.jpg' : 'temp_${const Uuid().v4()}.jpg';
    final targetPath = '${coversDir.path}/$fileName';

    final sourceFile = File(photo.path);
    await sourceFile.copy(targetPath);

    return targetPath;
  }

  /// Renames a temp cover file to use the real book ID after creation.
  /// Returns the new path, or null if the source file does not exist.
  static Future<String?> renameTempCover(String tempPath, int bookId) async {
    final file = File(tempPath);
    if (!await file.exists()) return null;

    final dir = file.parent.path;
    final newPath = '$dir/$bookId.jpg';
    await file.rename(newPath);
    return newPath;
  }

  /// Deletes a temp cover file (e.g. when the user cancels adding a book).
  static Future<void> cleanupTempCover(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Failed to clean up temp cover: $e');
    }
  }
}
