import 'dart:ui' show Offset;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';

/// Pembungkus model face mesh on-device (pengganti mp_face_mesh.FaceMesh).
/// Menggunakan pengecekan kIsWeb agar tidak crash saat dijalankan di Chrome/Web.
class FaceMeshService {
  FaceMeshDetector? _detector;

  FaceMeshDetector get _safeDetector {
    _detector ??= FaceMeshDetector(option: FaceMeshDetectorOptions.faceMesh);
    return _detector!;
  }

  /// Mengembalikan 468 titik wajah, atau null kalau tidak ada wajah.
  Future<List<Offset>?> detect(InputImage image) async {
    if (kIsWeb) return null;
    try {
      final meshes = await _safeDetector.processImage(image);
      if (meshes.isEmpty) return null;

      final pts = List<Offset>.filled(468, Offset.zero);
      for (final p in meshes.first.points) {
        if (p.index >= 0 && p.index < 468) {
          pts[p.index] = Offset(p.x, p.y);
        }
      }
      return pts;
    } catch (e) {
      debugPrint('FaceMesh detect error: ');
      return null;
    }
  }

  Future<void> dispose() async {
    if (kIsWeb) return;
    try {
      await _detector?.close();
    } catch (e) {
      debugPrint('FaceMesh close error: ');
    }
  }
}
