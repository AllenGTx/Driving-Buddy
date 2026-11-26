import 'dart:ui' show Offset;
import 'package:flutter_test/flutter_test.dart';

import 'package:driving_buddy/models/detection_result.dart';
import 'package:driving_buddy/services/drowsiness_detector.dart';

List<Offset> _buildMockFace({required double ear, required double mar}) {
  final pts = List<Offset>.filled(468, const Offset(100, 100));
  // Nose & chin for stable neutral pitch (~0.45)
  pts[10] = const Offset(100, 50);
  pts[1] = const Offset(100, 105);
  pts[199] = const Offset(100, 150);

  // Right eye [33, 160, 158, 133, 153, 144], width = 20 -> v = ear * 20
  final eyeV = ear * 20.0;
  pts[33] = const Offset(60, 80);
  pts[133] = const Offset(80, 80);
  pts[160] = Offset(66, 80 - eyeV / 2);
  pts[144] = Offset(66, 80 + eyeV / 2);
  pts[158] = Offset(74, 80 - eyeV / 2);
  pts[153] = Offset(74, 80 + eyeV / 2);

  // Left eye [362, 385, 387, 263, 373, 380], width = 20, level y = 80 (0 deg roll)
  pts[362] = const Offset(120, 80);
  pts[263] = const Offset(140, 80);
  pts[385] = Offset(126, 80 - eyeV / 2);
  pts[380] = Offset(126, 80 + eyeV / 2);
  pts[387] = Offset(134, 80 - eyeV / 2);
  pts[373] = Offset(134, 80 + eyeV / 2);

  // Mouth [61, 291] width = 40, [13, 14] height = mar * 40
  final mouthV = mar * 40.0;
  pts[61] = const Offset(80, 130);
  pts[291] = const Offset(120, 130);
  pts[13] = Offset(100, 130 - mouthV / 2);
  pts[14] = Offset(100, 130 + mouthV / 2);
  return pts;
}

void main() {
  test('Droopy eyes (EAR 0.18) accumulated >= 4s in 10s window marks Drowsy, not Sleep', () {
    final det = DrowsinessDetector();
    double t = 100.0;
    // Feed 4.4s of droopy eyes (EAR = 0.18, between 0.15 and 0.21) in 0.2s steps
    DetectionResult last = DetectionResult.initial;
    for (int i = 0; i <= 22; i++) {
      last = det.update(_buildMockFace(ear: 0.18, mar: 0.1), nowSec: t);
      t += 0.2;
    }
    expect(last.status, DriverStatus.drowsy);
  });

  test('2 yawns within 5 minutes marks Drowsy after yawn display window finishes', () {
    final det = DrowsinessDetector();
    double t = 200.0;
    // Yawn 1 (hold 1.4s)
    for (int i = 0; i < 8; i++) {
      det.update(_buildMockFace(ear: 0.30, mar: 0.50), nowSec: t);
      t += 0.2;
    }
    // Close mouth for 5 seconds
    for (int i = 0; i < 25; i++) {
      det.update(_buildMockFace(ear: 0.30, mar: 0.10), nowSec: t);
      t += 0.2;
    }
    // Yawn 2 (hold 1.4s)
    for (int i = 0; i < 8; i++) {
      det.update(_buildMockFace(ear: 0.30, mar: 0.50), nowSec: t);
      t += 0.2;
    }
    // Wait 4s past yawn banner display
    t += 4.0;
    final res = det.update(_buildMockFace(ear: 0.30, mar: 0.10), nowSec: t);
    expect(res.yawnCount, 2);
    expect(res.status, DriverStatus.drowsy);
  });

  test('Full eye closure (EAR 0.11) >= 1.7s still triggers Sleep critical status', () {
    final det = DrowsinessDetector();
    double t = 300.0;
    DetectionResult last = DetectionResult.initial;
    for (int i = 0; i <= 10; i++) {
      last = det.update(_buildMockFace(ear: 0.11, mar: 0.10), nowSec: t);
      t += 0.2;
    }
    expect(last.status, DriverStatus.sleep);
  });
}
