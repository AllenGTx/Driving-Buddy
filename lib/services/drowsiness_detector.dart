import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../core/thresholds.dart';
import '../models/detection_result.dart';

/// Port dari logika Python (EAR, MAR, head pitch, head roll/tilt, head bobbing, timer, status bertingkat).
/// Tidak bergantung pada kamera / ML Kit langsung, sehingga dapat dites di unit test & web simulation.
class DrowsinessDetector {
  // Indeks landmark MediaPipe Face Mesh (468 titik)
  static const rightEye = [33, 160, 158, 133, 153, 144];
  static const leftEye = [362, 385, 387, 263, 373, 380];

  double? _eyeClosedStart, _yawnStart, _headDropStart, _headTiltStart;
  double _lastBlink = 0, _yawnDisplayUntil = 0;
  bool _eyeClosed = false, _yawnCounted = false;
  final _yawns = Queue<double>();
  final _blinks = Queue<double>();

  // Head Bobbing & Head Tilt Tracker
  final _headBobs = Queue<double>();
  double _smoothPitch = 0.5;
  double _peakPitch = 0.5;
  double _peakPitchTime = 0.0;
  bool _bobPeakDetected = false;
  double _bobCooldownUntil = 0.0;

  double _d(Offset a, Offset b) => (a - b).distance;

  double _ear(List<Offset> p, List<int> i) {
    final h = _d(p[i[0]], p[i[3]]);
    if (h == 0) return 0;
    return (_d(p[i[1]], p[i[5]]) + _d(p[i[2]], p[i[4]])) / (2 * h);
  }

  double _mar(List<Offset> p) {
    final w = _d(p[61], p[291]);
    return w == 0 ? 0 : _d(p[13], p[14]) / w;
  }

  double _pitch(List<Offset> p) {
    final faceH = _d(p[10], p[199]);
    return faceH > 0 ? _d(p[1], p[199]) / faceH : 0.5;
  }

  /// Menghitung sudut kemiringan mata / kepala (Roll / Tilt) dalam derajat
  double _roll(List<Offset> p) {
    final rEye = Offset((p[33].dx + p[133].dx) * 0.5, (p[33].dy + p[133].dy) * 0.5);
    final lEye = Offset((p[362].dx + p[263].dx) * 0.5, (p[362].dy + p[263].dy) * 0.5);
    final dy = lEye.dy - rEye.dy;
    final dx = lEye.dx - rEye.dx;
    if (dx == 0 && dy == 0) return 0.0;
    return (math.atan2(dy, dx) * 180.0 / math.pi);
  }

  /// Panggil tiap frame. Kirim null kalau wajah tidak terdeteksi.
  /// [enableHeadTilt] dan [enableHeadBob] untuk toggle on/off fitur posture
  DetectionResult update(
    List<Offset>? p, {
    bool enableHeadTilt = true,
    bool enableHeadBob = true,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;

    while (_yawns.isNotEmpty && now - _yawns.first > Thresholds.yawnWindow) {
      _yawns.removeFirst();
    }
    while (_blinks.isNotEmpty && now - _blinks.first > 60) {
      _blinks.removeFirst();
    }
    while (_headBobs.isNotEmpty && now - _headBobs.first > Thresholds.headBobWindow) {
      _headBobs.removeFirst();
    }

    if (p == null) {
      _headTiltStart = null;
      _bobPeakDetected = false;
      return DetectionResult(
        status: DriverStatus.noFace,
        subStatus: 'WAJAH TIDAK TERDETEKSI / MENENGOK',
        ear: 0,
        mar: 0,
        blinkCount: _blinks.length,
        yawnCount: _yawns.length,
        headBobCount: _headBobs.length,
      );
    }

    final ear = (_ear(p, rightEye) + _ear(p, leftEye)) / 2;
    final mar = _mar(p);
    final pitch = _pitch(p);
    final roll = _roll(p);
    double eyeDur = 0, yawnDur = 0;

    // --- Mata terpejam (abaikan kalau mulut sedang menguap) ---
    if (ear < Thresholds.earClosed && mar < Thresholds.marYawn) {
      if (!_eyeClosed) {
        _eyeClosed = true;
        if (now - _lastBlink >= Thresholds.minBlinkInterval) {
          _blinks.add(now);
          _lastBlink = now;
        }
      }
      _eyeClosedStart ??= now;
      eyeDur = now - _eyeClosedStart!;
    } else {
      _eyeClosed = false;
      _eyeClosedStart = null;
    }

    // --- Menguap (1x per siklus buka-tutup mulut) ---
    if (mar > Thresholds.marYawn) {
      _yawnStart ??= now;
      yawnDur = now - _yawnStart!;
      if (yawnDur >= Thresholds.yawnLimit && !_yawnCounted) {
        _yawns.add(now);
        _yawnDisplayUntil = now + 3.0;
        _yawnCounted = true;
      }
    } else {
      _yawnStart = null;
      _yawnCounted = false;
    }

    // --- Kepala menunduk (Head Drop statis) ---
    if (pitch > Thresholds.headDrop) {
      _headDropStart ??= now;
    } else {
      _headDropStart = null;
    }

    // --- Fitur 1: HEAD TILT (Kemiringan Kepala ke Kiri/Kanan) ---
    bool isHeadTiltTriggered = false;
    if (enableHeadTilt && roll.abs() >= Thresholds.headTiltRollAngle) {
      _headTiltStart ??= now;
      if (now - _headTiltStart! >= Thresholds.headTiltDurationLimit) {
        isHeadTiltTriggered = true;
      }
    } else {
      _headTiltStart = null;
    }

    // --- Fitur 2: HEAD BOBBING (Sensitif & Akurat: deteksi gerak sentakan menunduk-kembali) ---
    bool isHeadBobTriggered = false;
    if (enableHeadBob) {
      // Exponential moving average untuk baseline pitch yang stabil
      _smoothPitch = _smoothPitch * 0.85 + pitch * 0.15;
      final diff = pitch - _smoothPitch;

      // 1. Cek lonjakan pitch ke bawah (gerak kepala terkulai / menunduk cepat)
      if (diff >= 0.055) {
        _bobPeakDetected = true;
        _peakPitch = pitch;
        _peakPitchTime = now;
      }

      // 2. Cek sentakan recoil kembali naik (driver tersentak bangun kembali ke posisi semula)
      if (_bobPeakDetected && (now - _peakPitchTime <= 1.2)) {
        if (pitch <= _peakPitch - 0.040) {
          if (now >= _bobCooldownUntil) {
            _headBobs.add(now);
            _bobCooldownUntil = now + 1.2; // debounce agar 1 gerakan bob dihitung tepat 1x
          }
          _bobPeakDetected = false;
        }
      }

      // Timeout peak jika lebih dari 1.2 detik tanpa recoil
      if (now - _peakPitchTime > 1.2) {
        _bobPeakDetected = false;
      }

      if (_headBobs.length >= Thresholds.headBobAlertFreq) {
        isHeadBobTriggered = true;
      }
    }

    // --- Penentuan status (prioritas bertingkat) ---
    var status = DriverStatus.awake;
    var sub = 'Pengemudi Fokus & Segar';

    if (eyeDur >= Thresholds.eyeClosedLimit) {
      status = DriverStatus.sleep;
      sub = 'BAHAYA: MATA TERPEJAM (${eyeDur.toStringAsFixed(1)}s)!';
    } else if (isHeadTiltTriggered) {
      status = DriverStatus.sleep;
      sub = 'BAHAYA: KEPALA MIRING (${roll.abs().toStringAsFixed(0)}° > ${Thresholds.headTiltDurationLimit}s)!';
    } else if (isHeadBobTriggered) {
      status = DriverStatus.sleep;
      sub = 'BAHAYA: HEAD BOBBING (${_headBobs.length}x dalam 5 Menit)!';
    } else if (now < _yawnDisplayUntil || yawnDur >= Thresholds.yawnLimit) {
      status = DriverStatus.yawn;
      sub = 'MENGUAP TERDETEKSI (${_yawns.length}x Total)';
    } else if (_headDropStart != null &&
        now - _headDropStart! >= Thresholds.headDropLimit) {
      status = DriverStatus.drowsy;
      sub = 'PERINGATAN: KEPALA MENUNDUK / TERLELAP';
    } else if (_yawns.length >= Thresholds.yawnAlertFreq) {
      status = DriverStatus.drowsy;
      sub = 'LELAH: ${_yawns.length}x Menguap dalam 5 Mnt';
    } else if (_blinks.length >= Thresholds.highBlinkRate) {
      status = DriverStatus.drowsy;
      sub = 'LELAH: Frekuensi Kedip Tinggi (${_blinks.length}/mnt)';
    }

    return DetectionResult(
      status: status,
      subStatus: sub,
      ear: ear,
      mar: mar,
      blinkCount: _blinks.length,
      yawnCount: _yawns.length,
      rollAngle: roll,
      pitchRatio: pitch,
      headBobCount: _headBobs.length,
      isHeadTiltAlert: isHeadTiltTriggered,
      isHeadBobAlert: isHeadBobTriggered,
    );
  }

  /// Reset data akumulasi menguap & bobbing (misal saat driver istirahat / dismiss alert)
  void resetYawns() {
    _yawns.clear();
    _yawnStart = null;
    _yawnCounted = false;
    _yawnDisplayUntil = 0;
  }

  void resetHeadBobs() {
    _headBobs.clear();
    _bobPeakDetected = false;
    _bobCooldownUntil = (DateTime.now().millisecondsSinceEpoch / 1000.0) + 3.0; // cooldown 3 detik setelah dismiss
  }

  void resetAllAlerts() {
    resetYawns();
    resetHeadBobs();
    _headTiltStart = null;
    _eyeClosedStart = null;
  }
}
