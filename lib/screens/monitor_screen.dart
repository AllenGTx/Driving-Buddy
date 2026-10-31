import '../services/theme_service.dart';
import '../services/language_service.dart';
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../core/app_colors.dart';
import '../core/thresholds.dart';
import '../models/detection_result.dart';
import '../services/alert_config.dart';
import '../services/firebase_service.dart';
import '../services/sos_service.dart';
import '../services/alert_service.dart';
import '../services/camera_image_converter.dart';
import '../services/drowsiness_detector.dart';
import '../services/face_mesh_service.dart';
import '../supabase_service.dart';
import '../driving_card_screen.dart';
import '../widgets/driving_buddy_app_bar.dart';
import '../features/nearby_places/nearby_places.dart';

// ============================================================================
// MONITOR SCREEN (Active HUD Berkendara Telemetri — Luxury GT)
// ============================================================================

typedef MonitoringScreen = MonitorScreen;

class MonitorScreen extends StatefulWidget {
  final bool isActive;
  final NearbyPlacesController? nearbyController;

  const MonitorScreen({
    super.key,
    this.isActive = true,
    this.nearbyController,
  });

  @override
  MonitorScreenState createState() => MonitorScreenState();
}

class MonitorScreenState extends State<MonitorScreen> {
  bool get isMonitoring => _isMonitoring;

  // Timer kemudi
  Timer? _drivingTimer;
  int _elapsedSeconds = 0;
  bool _isMonitoring = false;

  // Kamera & On-Device AI
  CameraController? _cameraController;
  CameraDescription? _frontCamera;
  bool _busy = false;
  int _frameCount = 0;

  // ML Kit Services (Offline Face Mesh)
  final FaceMeshService _mesh = FaceMeshService();
  final DrowsinessDetector _detector = DrowsinessDetector();
  final AlertService _alert = AlertService();

  // Tempat terdekat (Maps API): kartu rekomendasi pitstop & tombol rest area
  late final NearbyPlacesController _nearby;
  late final bool _ownsNearby;

  // Posture Detection Toggle Preferences
  bool _enableHeadTilt = true;
  bool _enableHeadBob = true;

  // Hasil deteksi real-time
  DetectionResult _result = DetectionResult.initial;
  bool _eyeDetected = false;
  String _cameraMode = 'Standby';

  // EAR rolling history untuk waveform graph
  final List<double> _earHistory = [0.32, 0.31, 0.33, 0.30, 0.32, 0.34, 0.32, 0.31, 0.33, 0.32];

  // GPS & Telemetry Tracking
  double _totalDistanceMeters = 0.0;
  double _currentSpeedKmh = 0.0;
  double _topSpeedKmh = 0.0;
    bool _showCameraModal = false;
  final List<double> _sessionEarSamples = [];
  final List<double> _sessionMarSamples = [];
  final List<double> _sessionTiltSamples = [];
  final List<double> _sessionSpeedSamples = [];
  DriverFix? _lastDriverFix;

  // Snooze alert state
  DateTime? _snoozeUntil;

  // Alert guard
  bool _isAlertShowing = false;
  bool _isNightVisionEnabled = false;
  double? _previousBrightness;
  Timer? _sosTimer;
  double? _startLat;
  double? _startLng;
  final List<Map<String, double>> _routeBreadcrumbs = [];

  // === Supabase Session Tracking ===
  String? _currentSessionId;
  DateTime? _sessionStartTime;
  int _drowsyCount = 0;
  int _yawnCount = 0;
  int _microsleepCount = 0;
  bool _isCurrentlySleeping = false;
  bool _isCurrentlyDrowsy = false;

  @override
  void initState() {
    super.initState();
    _ownsNearby = widget.nearbyController == null;
    _nearby = widget.nearbyController ?? NearbyPlacesController();
    if (_ownsNearby) {
      _nearby.start(askPermission: false);
    }
    _nearby.addListener(_onNearbyUpdate);
    _loadPostureSettings();
  }

  void _onNearbyUpdate() {
    if (!mounted) return;
    final fix = _nearby.fix;
    if (fix != null) {
      final mps = fix.speedMps;
      // Filter noise GPS saat diam: threshold 0.8 m/s ≈ 2.88 km/jam
      if (mps != null && mps >= 0.8) {
        _currentSpeedKmh = mps * 3.6;
        if (_currentSpeedKmh > _topSpeedKmh) {
          _topSpeedKmh = _currentSpeedKmh;
        }
      } else {
        _currentSpeedKmh = 0.0;
      }

      if (_lastDriverFix != null && _isMonitoring) {
        final dMeters = haversineM(_lastDriverFix!.lat, _lastDriverFix!.lng, fix.lat, fix.lng);
        // Hanya akumulasi jarak jika kendaraan benar-benar bergerak (speed >= 2.5 km/j atau delta > 12m)
        if ((_currentSpeedKmh >= 2.5 || dMeters >= 12.0) && dMeters < 500.0) {
          _totalDistanceMeters += dMeters;
          // Rekam breadcrumb jika berpindah minimal 8 meter
          if (_routeBreadcrumbs.isEmpty ||
              haversineM(_routeBreadcrumbs.last['lat']!, _routeBreadcrumbs.last['lng']!, fix.lat, fix.lng) >= 8.0) {
            _routeBreadcrumbs.add({'lat': fix.lat, 'lng': fix.lng});
          }
        }
      } else if (_isMonitoring && _routeBreadcrumbs.isEmpty && fix.lat != 0.0) {
        _routeBreadcrumbs.add({'lat': fix.lat, 'lng': fix.lng});
      }
      _lastDriverFix = fix;

      if (_isMonitoring) {
        setState(() {});
      }
    }
  }



  @override
  void didUpdateWidget(covariant MonitorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _loadPostureSettings();
      if (_isMonitoring) _resumeTimer();
    }
    if (!widget.isActive && oldWidget.isActive) {
      _pauseTimer();
      if (_isNightVisionEnabled) {
        try {
          ScreenBrightness.instance.resetScreenBrightness();
        } catch (_) {}
      }
    } else if (widget.isActive && !oldWidget.isActive && _isNightVisionEnabled) {
      try {
        ScreenBrightness.instance.setScreenBrightness(1.0);
      } catch (_) {}
    }
  }

  Future<void> _loadPostureSettings() async {
    final tilt = await AlertConfig.isHeadTiltEnabled();
    final bob = await AlertConfig.isHeadBobEnabled();
    if (mounted) {
      setState(() {
        _enableHeadTilt = tilt;
        _enableHeadBob = bob;
      });
    }
  }

  @override
  void dispose() {
    if (_isNightVisionEnabled) {
      try {
        ScreenBrightness.instance.resetScreenBrightness();
      } catch (_) {}
    }
    _sosTimer?.cancel();
    _nearby.removeListener(_onNearbyUpdate);
    _drivingTimer?.cancel();
    _cameraController?.dispose();
    _mesh.dispose();
    _alert.dispose();
    if (_ownsNearby) {
      _nearby.dispose();
    }
    WakelockPlus.disable();
    super.dispose();
  }

  // Public method to trigger monitoring from external button (e.g. CockpitScreen)
  void startFromExternal() {
    if (!_isMonitoring && mounted) {
      _startMonitoring();
    }
  }

  // ---------- Runtime Camera Permission ----------
  Future<bool> _requestCameraPermission() async {
    if (kIsWeb) return true;

    final status = await Permission.camera.status;
    if (status.isGranted) return true;
    if (status.isDenied) return (await Permission.camera.request()).isGranted;
    if (status.isPermanentlyDenied && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Izin kamera ditolak permanen. Buka Pengaturan > Aplikasi untuk mengaktifkannya.'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Buka Pengaturan',
            textColor: Colors.white,
            onPressed: () => openAppSettings(),
          ),
        ),
      );
    }
    return false;
  }

  // ---------- Mulai Monitoring ----------
  Future<void> _startMonitoring() async {
    // Muat ulang pengaturan Head Tilt/Bob terbaru sebelum sesi dimulai.
    // Pengaturan dibuka sebagai halaman terpisah sehingga tab tidak
    // menerima sinyal isActive saat kembali.
    await _loadPostureSettings();
    _detector.resetAllAlerts();
    setState(() {
      _isMonitoring = true;
      _isCurrentlySleeping = false;
      _isCurrentlyDrowsy = false;
      _totalDistanceMeters = 0.0;
      _currentSpeedKmh = 0.0;
      _topSpeedKmh = 0.0;
      _sessionEarSamples.clear();
      _sessionMarSamples.clear();
      _sessionTiltSamples.clear();
      _sessionSpeedSamples.clear();
      _lastDriverFix = _nearby.fix;
      _elapsedSeconds = 0;
      _cameraMode = 'Memuat AI...';
      _result = DetectionResult.initial;
      _drowsyCount = 0;
      _yawnCount = 0;
      _microsleepCount = 0;
      _currentSessionId = null;
    });
    _sessionStartTime = DateTime.now();

    final hasPermission = await _requestCameraPermission();
    if (!hasPermission) {
      if (mounted) setState(() { _isMonitoring = false; _cameraMode = 'Standby'; });
      return;
    }

    // Cek status GPS / Lokasi dan Kontak SOS
    Future.microtask(() async {
      if (!mounted) return;
      if (_nearby.fix == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📍 Sinyal GPS / Lokasi belum aktif. Telemetri kecepatan & rute peta mungkin terbatas.'),
            backgroundColor: Color(0xFFD97706),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 5),
          ),
        );
      }

      final curEmail = AuthService.currentUser?.email;
      final savedPhone = await SosService.getSosPhone(userEmail: curEmail);
      if (savedPhone.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Kontak Darurat SOS belum diisi di Pengaturan! Atur sekarang demi keselamatan Anda.'),
            backgroundColor: Color(0xFFD94126),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 6),
          ),
        );
      }
    });

    // Simpan titik awal GPS perjalanan & inisialisasi breadcrumbs rute
    _startLat = _nearby.fix?.lat;
    _startLng = _nearby.fix?.lng;
    _routeBreadcrumbs.clear();
    if (_startLat != null && _startLng != null) {
      _routeBreadcrumbs.add({'lat': _startLat!, 'lng': _startLng!});
    }

    // Mulai sesi di Supabase (jika login)
    if (AuthService.isLoggedIn) {
      try {
        _currentSessionId = await SessionService.startSession();
        debugPrint('✅ Sesi Supabase dimulai ID: $_currentSessionId');
      } catch (e) {
        debugPrint('Supabase startSession error: $e');
      }
    }

    try {
      await WakelockPlus.enable();

      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('Tidak ada kamera tersedia di perangkat ini.');
      _frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.external,
          orElse: () => cameras.first,
        ),
      );

      _cameraController = CameraController(
        _frontCamera!,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await _cameraController!.initialize();
      await _cameraController!.startImageStream(_onFrame);

      if (!mounted) return;
      setState(() {
        _cameraMode = 'ML Kit Aktif';
      });
      _resumeTimer();

      // Tempat terdekat: ikuti posisi selama sesi berjalan. Semua error ditangani di dalam
      // controller dan tidak pernah mengganggu deteksi kantuk.
      unawaited(_nearby.start());
    } catch (e) {
      debugPrint('Init kamera gagal: $e');
      if (mounted) {
        setState(() {
          _isMonitoring = false;
          _cameraMode = 'Standby';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memulai kamera: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ---------- ML Kit Frame Processing (Offline 100%) ----------
  Future<void> _onFrame(CameraImage image) async {
    if (_busy) return;
    if (++_frameCount % Thresholds.processEveryNthFrame != 0) return;
    _busy = true;

    try {
      final controller = _cameraController;
      if (controller == null || _frontCamera == null) return;

      final input = cameraImageToInputImage(
        image,
        _frontCamera!,
        controller.value.deviceOrientation,
      );
      if (input == null) return;

      final points = await _mesh.detect(input);
      final result = _detector.update(
        points,
        enableHeadTilt: _enableHeadTilt,
        enableHeadBob: _enableHeadBob,
      );

      // Catat riwayat EAR untuk waveform & agregat sesi
      if (result.ear > 0.05) {
        _earHistory.add(result.ear);
        if (_earHistory.length > 25) _earHistory.removeAt(0);
        _sessionEarSamples.add(result.ear);
      }
      if (result.mar > 0.01) {
        _sessionMarSamples.add(result.mar);
      }
      _sessionTiltSamples.add(result.rollAngle.abs());
      if (_currentSpeedKmh > 0) {
        _sessionSpeedSamples.add(_currentSpeedKmh);
      }

      // Cek apakah sedang dalam masa snooze
      final isSnoozed = _snoozeUntil != null && DateTime.now().isBefore(_snoozeUntil!);

      // Cek kondisi bahaya
      final isSleep = result.status == DriverStatus.sleep;
      final isExcessiveYawn = result.yawnCount >= Thresholds.yawnAlertFreq;
      final isDrowsy = result.status == DriverStatus.drowsy;

      // Catat event hanya saat terjadi kenaikan diskrit (bukan setiap frame)
      if (result.yawnCount > _yawnCount) {
        _yawnCount = result.yawnCount;
        if (AuthService.isLoggedIn && _currentSessionId != null) {
          SessionService.logEvent(
            sessionId: _currentSessionId!,
            eventType: 'yawn',
          );
        }
      }

      // Event Microsleep (Hanya dihitung 1x per episode penutupan mata, bukan berulang tiap frame)
      if (isSleep) {
        if (!_isCurrentlySleeping) {
          _isCurrentlySleeping = true;
          _microsleepCount++;
          if (AuthService.isLoggedIn && _currentSessionId != null) {
            SessionService.logEvent(
              sessionId: _currentSessionId!,
              eventType: 'microsleep',
            );
          }
        }
      } else {
        _isCurrentlySleeping = false;
      }

      // Event Kantuk / Drowsy (Hanya dihitung 1x per episode)
      if (isDrowsy && !isSleep) {
        if (!_isCurrentlyDrowsy) {
          _isCurrentlyDrowsy = true;
          _drowsyCount++;
          if (AuthService.isLoggedIn && _currentSessionId != null) {
            SessionService.logEvent(
              sessionId: _currentSessionId!,
              eventType: 'drowsy',
            );
          }
        }
      } else if (!isDrowsy) {
        _isCurrentlyDrowsy = false;
      }

      if (!isSnoozed && (isSleep || isExcessiveYawn) && !_isAlertShowing) {
        await _alert.playAlert();
        if (isSleep) {
          String alertTitle = 'MATA TERPEJAM!\nISTIRAHAT SEKARANG';
          String alertSub = 'PERINGATAN MICROSLEEP';
          String alertReason =
              'Mata terpejam melebihi ${Thresholds.eyeClosedLimit} detik. Segera cari tempat aman untuk berhenti.';

          if (_enableHeadTilt && result.isHeadTiltAlert) {
            alertTitle = 'KEPALA MIRING!\nISTIRAHAT SEKARANG';
            alertSub = 'PERINGATAN HEAD TILT';
            alertReason =
                'Kepala miring ${result.rollAngle.abs().toStringAsFixed(0)}° lebih dari ${Thresholds.headTiltDurationLimit}s. Otot leher kehilangan kendali!';
          } else if (_enableHeadBob && result.isHeadBobAlert) {
            alertTitle = 'KEPALA TERSENTAK!\nBAHAYA MICROSLEEP';
            alertSub = 'PERINGATAN HEAD BOBBING';
            alertReason =
                'Terdeteksi ${result.headBobCount}x sentakan kepala jatuh dalam 5 menit. Segera menepi dan istirahat!';
          }

          _triggerSafetyAlert(
            title: alertTitle,
            subtitle: alertSub,
            reason: alertReason,
            resetYawnsOnDismiss: true,
          );
        } else {
          _triggerSafetyAlert(
            title: 'TERLALU SERING\nMENGUAP!',
            subtitle: 'INDIKASI KELELAHAN BERAT',
            reason:
                'Terdeteksi ${result.yawnCount}x menguap dalam 5 menit terakhir. Tingkat kantuk Anda sangat tinggi!',
            resetYawnsOnDismiss: true,
          );
        }
      }

      if (mounted) {
        setState(() {
          _result = result;
          _eyeDetected = result.status != DriverStatus.noFace;
        });
      }
    } catch (e) {
      debugPrint('[FaceMesh] Error deteksi frame: $e');
    } finally {
      _busy = false;
    }
  }

  void _resumeTimer() {
    _drivingTimer?.cancel();
    _drivingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds++;
      });
    });
  }

  void _pauseTimer() {
    _drivingTimer?.cancel();
  }

  Future<void> _stopMonitoring() async {
    _pauseTimer();

    final int finalDuration = _elapsedSeconds;
    final int finalDrowsy = _drowsyCount;
    final int finalYawn = _result.yawnCount > _yawnCount ? _result.yawnCount : _yawnCount;
    final int finalMicro = _microsleepCount;
    final double avgBlink = _result.blinkCount.toDouble();
    final DateTime sessionStart = _sessionStartTime ?? DateTime.now();

    // Hitung kecepatan rata-rata:
    // Proteksi sesi pendek (< 15 detik atau jarak < 50 meter) dari artefak pembagian waktu kecil
    double calculatedAvgSpeed = _currentSpeedKmh;
    if (_totalDistanceMeters > 50.0 && finalDuration >= 15) {
      final speedFromDistance = (_totalDistanceMeters / 1000.0) / (finalDuration / 3600.0);
      if (calculatedAvgSpeed <= 1.0 || speedFromDistance > calculatedAvgSpeed) {
        calculatedAvgSpeed = speedFromDistance;
      }
    } else if (finalDuration < 15 && _totalDistanceMeters < 50.0) {
      // Sesi uji coba sangat singkat / diam: bersihkan jitter koordinat
      if (_sessionSpeedSamples.isEmpty || _sessionSpeedSamples.every((s) => s < 2.5)) {
        calculatedAvgSpeed = 0.0;
        _totalDistanceMeters = 0.0;
        _topSpeedKmh = 0.0;
      }
    }

    // Hitung rata-rata telemetri sesi
    final double computedAvgEar = _sessionEarSamples.isNotEmpty
        ? _sessionEarSamples.reduce((a, b) => a + b) / _sessionEarSamples.length
        : 0.28;
    final double computedAvgMar = _sessionMarSamples.isNotEmpty
        ? _sessionMarSamples.reduce((a, b) => a + b) / _sessionMarSamples.length
        : 0.12;
    final double computedAvgTilt = _sessionTiltSamples.isNotEmpty
        ? _sessionTiltSamples.reduce((a, b) => a + b) / _sessionTiltSamples.length
        : 3.5;

    if (_sessionSpeedSamples.isNotEmpty) {
      final spdAvg = _sessionSpeedSamples.reduce((a, b) => a + b) / _sessionSpeedSamples.length;
      if (spdAvg > calculatedAvgSpeed) calculatedAvgSpeed = spdAvg;
    }
    double realTopSpeed = _topSpeedKmh;
    if (calculatedAvgSpeed > 0 && realTopSpeed < calculatedAvgSpeed) {
      realTopSpeed = calculatedAvgSpeed * 1.15;
    } else if (calculatedAvgSpeed == 0.0 && _totalDistanceMeters < 30.0) {
      realTopSpeed = 0.0;
    }

    // Hitung driving score (0-100)
    int score = 100;
    score -= (finalDrowsy * 5).clamp(0, 40);
    score -= (finalYawn * 2).clamp(0, 20);
    score -= (finalMicro * 10).clamp(0, 40);
    score = score.clamp(0, 100);

    // Simpan sesi ke Firestore jika login
    if (AuthService.isLoggedIn && _currentSessionId != null) {
      try {
        await SessionService.endSession(
          sessionId: _currentSessionId!,
          durationSeconds: finalDuration,
          avgSpeedKmh: calculatedAvgSpeed,
          maxSpeedKmh: realTopSpeed,
          distanceKm: (_totalDistanceMeters / 1000.0).clamp(0.0, 9999.0),
          drivingScore: score,
          avgBlinkRate: avgBlink,
          totalYawns: finalYawn,
          totalDrowsyEvents: finalDrowsy,
          totalMicrosleeps: finalMicro,
          avgEar: computedAvgEar,
          avgMar: computedAvgMar,
          avgHeadTilt: computedAvgTilt,
          startLat: _startLat,
          startLng: _startLng,
          endLat: _nearby.fix?.lat ?? _startLat,
          endLng: _nearby.fix?.lng ?? _startLng,
          routePoints: List.from(_routeBreadcrumbs),
        );
        debugPrint('✅ Sesi tersimpan ke Supabase! Score: $score');
      } catch (e) {
        debugPrint('❌ Gagal simpan sesi ke Supabase: $e');
      }
    }

    try {
      await _cameraController?.stopImageStream();
    } catch (_) {}
    await _cameraController?.dispose();
    _cameraController = null;
    await _alert.stop();
    if (_ownsNearby) {
      _nearby.stop();
      _nearby.start(askPermission: false);
    }
    await WakelockPlus.disable();
    if (_isNightVisionEnabled) {
      try {
        await ScreenBrightness.instance.resetScreenBrightness();
      } catch (_) {}
    }

    setState(() {
      _isMonitoring = false;
      _elapsedSeconds = 0;
      _result = DetectionResult.initial;
      _eyeDetected = false;
      _cameraMode = 'Standby';
      _isAlertShowing = false;
      _frameCount = 0;
      _currentSessionId = null;
    });

    // Dialog konfirmasi selesai perjalanan: Pilihan Lihat Kartu Sekarang atau Nanti Saja
    if (mounted) {
      final wantCard = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Sesi Selesai!', style: TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Skor Keselamatan Anda: ' + score.toString() + '/100',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFF26B1D)),
              ),
              const SizedBox(height: 8),
              Text('Durasi: ' + _formatDuration(finalDuration)),
              Text('Kantuk: ' + finalDrowsy.toString() + 'x  ·  Menguap: ' + finalYawn.toString() + 'x  ·  Microsleep: ' + finalMicro.toString() + 'x'),
              const SizedBox(height: 12),
              const Text('Buka Kartu Pencapaian untuk dibagikan ke teman?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Nanti Saja', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF26B1D),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Lihat Kartu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (wantCard == true && mounted) {
        final hasNet = await SessionService.hasInternetConnection();
        if (!hasNet && mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.wifi_off_rounded, color: Color(0xFFF26B1D)),
                  SizedBox(width: 8),
                  Text('Koneksi Diperlukan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ],
              ),
              content: const Text(
                'Kartu Berkendara membutuhkan koneksi internet (WiFi atau Data Seluler) untuk memuat citra peta OpenStreetMap.\n\nSesi Anda sudah tersimpan aman di HP dan akan otomatis disinkronkan saat online.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF26B1D),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Mengerti', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
          return;
        }

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DrivingCardScreen(
              durationSeconds: finalDuration,
              drivingScore: score,
              totalMicrosleeps: finalMicro,
              totalDrowsy: finalDrowsy,
              totalYawns: finalYawn,
              startedAt: sessionStart,
              distanceKm: (_totalDistanceMeters / 1000.0),
              avgSpeedKmh: calculatedAvgSpeed,
              maxSpeedKmh: realTopSpeed,
              lastLat: _nearby.fix?.lat,
              lastLng: _nearby.fix?.lng,
              startLat: _startLat,
              startLng: _startLng,
              routePoints: List.from(_routeBreadcrumbs),
            ),
          ),
        );
      }
    }
  }

  void _snoozeAlert() {
    setState(() {
      _snoozeUntil = DateTime.now().add(const Duration(minutes: 15));
    });
    _alert.stop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(LanguageService.instance.isEnglish ? 'Alert snoozed for 15 minutes.' : 'Peringatan ditunda selama 15 menit.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatDuration(int totalSeconds) {
    final h = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  void _triggerSafetyAlert({
    required String title,
    required String subtitle,
    required String reason,
    required bool resetYawnsOnDismiss,
  }) {
    if (!_isMonitoring || _isAlertShowing) return;
    _isAlertShowing = true;
    if (_showCameraModal) { setState(() => _showCameraModal = false); }

    // Alarm bunyi: langsung cari tempat berhenti terdekat (apa pun jenisnya) untuk kartu di dialog.
    unawaited(_nearby.requestUrgent());

    // Otomatis picu SOS WhatsApp jika pengemudi tidak menekan 'Saya Sudah Bangun' dalam 1 menit penuh
    _sosTimer?.cancel();
    _sosTimer = Timer(const Duration(seconds: 60), () {
      if (_isAlertShowing && mounted) {
        _dispatchSosEmergency();
      }
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => MicrosleepAlertDialog(
        title: title,
        subtitle: subtitle,
        reason: reason,
        nearby: _nearby,
        onDismiss: () async {
          _sosTimer?.cancel();
          await _alert.stop();
          _detector.resetAllAlerts();
          _snoozeUntil = DateTime.now().add(const Duration(seconds: 5));
        },
        onRestArea: () async {
          _sosTimer?.cancel();
          final target = _nearby.best;
          await _alert.stop();
          _detector.resetAllAlerts();
          _snoozeUntil = DateTime.now().add(const Duration(seconds: 10));
          // Buka Google Maps (mode mobil) ke tempat berhenti terdekat dari server.
          final opened = target != null
              ? await _nearby.navigateTo(target)
              : await _nearby.navigateToBest();
          if (!opened && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Belum ada tempat berhenti yang ditemukan. Menepi di tempat yang aman ya.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),
    ).then((_) {
      _sosTimer?.cancel();
      _isAlertShowing = false;
      _nearby.clearUrgent();
    });
  }

  // Dynamic fatigue index calculation (0 - 100%)
  int _calculateFatigueIndex() {
    if (!_isMonitoring) return 0;
    if (_result.status == DriverStatus.sleep) return 94;
    if (_result.status == DriverStatus.drowsy) return 68;
    int index = 12; // Nominal baseline
    index += (_result.yawnCount * 8);
    if (_result.ear < 0.26) index += 15;
    return index.clamp(0, 99);
  }

  @override
  Widget build(BuildContext context) {
    final fatigueIndex = _calculateFatigueIndex();

    return Scaffold(
      backgroundColor: AppColors.dynamicBackground,
      appBar: DrivingBuddyAppBar(
        title: LanguageService.instance.s.drivingTitle,
        showProfileButton: !_isMonitoring,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Top Live HUD Bar (3-column telemetry cards)
            _buildTopLiveHudBar(fatigueIndex),
            const SizedBox(height: 10),

            // Toggle Night Vision / Flash Penerangan Wajah (Di atas Kamera Standby & Di bawah HUD Telemetri)
            _buildNightVisionToggleBar(),
            const SizedBox(height: 10),

            // 2. AI Face Monitoring Glass Cockpit Card
            _buildGlassCockpitCameraCard(),
            const SizedBox(height: 14),

            // 3. Rekomendasi Pitstop Assistant Card
            _buildPitstopAssistantCard(),
            const SizedBox(height: 14),

            // 4. Cockpit Drive Control Action Buttons
            _buildCockpitDriveControls(),
            const SizedBox(height: 16),
          ],
        ),
      ),
      if (_showCameraModal && _cameraController != null && _cameraController!.value.isInitialized)
        _buildCameraFocusModal(),
    ],
  ),
);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 1. TOP LIVE HUD BAR (3 Columns: Kecepatan, Jarak, Index Lelah)
  // ──────────────────────────────────────────────────────────────────────────

  // ──────────────────────────────────────────────────────────────────────────
  // FLOATING CAMERA POP-UP MODAL (3/4 Screen Window dengan Efek Bokeh)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildCameraFocusModal() {
    return Positioned.fill(
      child: Stack(
        children: [
          // 1. Efek Bokeh / Blur Latar Belakang Cockpit
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: GestureDetector(
                onTap: () => setState(() => _showCameraModal = false),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.72),
                ),
              ),
            ),
          ),

          // 2. Centered Floating Window (~75% Tinggi Layar)
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.90,
              height: MediaQuery.of(context).size.height * 0.74,
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 620),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFF26B1D),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.85),
                    blurRadius: 32,
                    spreadRadius: 4,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18.5),
                child: Column(
                  children: [
                    // Window Header Bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      color: const Color(0xFF1E293B),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                LanguageService.instance.isEnglish ? 'Cabin Camera' : 'Kamera Kabin',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                            ),
                            child: const Text(
                              'LIVE AI',
                              style: TextStyle(
                                color: Color(0xFF10B981),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Center Viewport: Letterboxed Black Background dengan Kamera Proporsional
                    Expanded(
                      child: Container(
                        color: Colors.black, // Letterbox bars atas/bawah
                        alignment: Alignment.center,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: SizedBox(
                            width: _cameraController!.value.previewSize?.height.toDouble() ?? 360,
                            height: _cameraController!.value.previewSize?.width.toDouble() ?? 480,
                            child: _isNightVisionEnabled
                                ? ColorFiltered(
                                    colorFilter: const ColorFilter.matrix(<double>[
                                      0.45, 0.65, 0.15, 0, 45,
                                      0.35, 1.35, 0.25, 0, 70,
                                      0.15, 0.45, 0.55, 0, 35,
                                      0,    0,    0,    1, 0,
                                    ]),
                                    child: CameraPreview(_cameraController!),
                                  )
                                : CameraPreview(_cameraController!),
                          ),
                        ),
                      ),
                    ),

                  // Window Footer Bar dengan Telemetri Wajah & Tombol Kembali
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    color: const Color(0xFF1E293B),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildPopupStatTag('EAR', _result.ear > 0.05 ? _result.ear.toStringAsFixed(2) : '0.28'),
                        _buildPopupStatTag('MAR', _result.mar > 0.01 ? _result.mar.toStringAsFixed(2) : '0.12'),
                        _buildPopupStatTag('TILT', '${_result.rollAngle.abs().toStringAsFixed(1)}°'),
                        ElevatedButton.icon(
                          onPressed: () => setState(() => _showCameraModal = false),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF26B1D),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: const Size(0, 32),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.fullscreen_exit_rounded, size: 15),
                          label: Text(LanguageService.instance.s.back, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      ),
    );
  }

  Widget _buildPopupStatTag(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFF94A3B8),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildTopLiveHudBar(int fatigueIndex) {
    final isDark = ThemeService.instance.isDarkMode;
    final distanceKm = (_totalDistanceMeters / 1000.0).toStringAsFixed(1);
    final speedStr = _isMonitoring ? _currentSpeedKmh.toStringAsFixed(0) : '0';

    String fatigueLabel = 'RENDAH';
    Color fatigueColor = const Color(0xFF059669);
    if (fatigueIndex >= 65) {
      fatigueLabel = 'BAHAYA';
      fatigueColor = const Color(0xFFD94126);
    } else if (fatigueIndex >= 40) {
      fatigueLabel = 'WASPADA';
      fatigueColor = const Color(0xFFE5A938);
    }

    return Row(
      children: [
        // Kecepatan
        Expanded(
          child: _buildHudCell(
            label: LanguageService.instance.isEnglish ? 'SPEED' : 'KECEPATAN',
            value: speedStr,
            unit: LanguageService.instance.s.speedUnit,
            isDark: isDark,
            bottomWidget: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSuccessBg : const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.trending_flat_rounded, size: 12, color: Color(0xFF059669)),
                  const SizedBox(width: 2),
                  Text(
                    LanguageService.instance.isEnglish ? 'STEADY' : 'STABIL',
                    style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: Color(0xFF065F46)),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Jarak (Realtime GPS)
        Expanded(
          child: _buildHudCell(
            label: LanguageService.instance.s.distance.toUpperCase(),
            value: distanceKm,
            unit: LanguageService.instance.s.distUnit,
            isDark: isDark,
            bottomWidget: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCardBgSoft : const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: isDark ? AppColors.darkCardBorder : const Color(0xFFCBD5E1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.gps_fixed_rounded, size: 10, color: Color(0xFFF26B1D)),
                  const SizedBox(width: 2),
                  Text(
                    _totalDistanceMeters > 0 ? ' ${LanguageService.instance.s.speedUnit}' : (LanguageService.instance.isEnglish ? 'GPS READY' : 'GPS SIAGA'),
                    style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Index Lelah
        Expanded(
          child: _buildHudCell(
            label: LanguageService.instance.isEnglish ? 'FATIGUE INDEX' : 'INDEX LELAH',
            value: '$fatigueIndex',
            unit: '%',
            valueColor: const Color(0xFFF26B1D),
            isDark: isDark,
            bottomWidget: Text(
              '$fatigueLabel · ${LanguageService.instance.isEnglish ? "THRESH 65%" : "AMBANG 65%"}',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: fatigueColor,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHudCell({
    required String label,
    required String value,
    required String unit,
    Color? valueColor,
    required Widget bottomWidget,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCardBg : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? AppColors.darkCardBorder : const Color(0xFFECEEF2)),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top accent amber bar
          Container(
            height: 2.5,
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF26B1D),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: valueColor ?? (isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A)),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          bottomWidget,
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 2. AI FACE MONITORING GLASS COCKPIT
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildGlassCockpitCameraCard() {
    final isDark = ThemeService.instance.isDarkMode;
    final isDanger = _result.status == DriverStatus.sleep || _result.status == DriverStatus.drowsy;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCardBg : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkCardBorder : const Color(0xFFECEEF2)),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.25) : const Color(0xFFF26B1D).withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Ambient copper line
          Container(
            height: 3,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Color(0xFFF26B1D), Colors.transparent],
              ),
            ),
          ),

          // Header Bar di atas viewport kamera: Status Deteksi Wajah & Tombol Perbesar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCardBgSoft : const Color(0xFFF8FAFC),
              border: Border(
                bottom: BorderSide(
                  color: isDark ? AppColors.darkCardBorder : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Status Deteksi Wajah
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                  decoration: BoxDecoration(
                    color: !_isMonitoring
                        ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9))
                        : (isDanger
                            ? (isDark ? const Color(0xFF7F1D1D).withValues(alpha: 0.5) : const Color(0xFFFEF2F2))
                            : (_eyeDetected
                                ? (isDark ? const Color(0xFF064E3B).withValues(alpha: 0.5) : const Color(0xFFECFDF5))
                                : (isDark ? const Color(0xFF7F1D1D).withValues(alpha: 0.5) : const Color(0xFFFEF2F2)))),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: !_isMonitoring
                          ? const Color(0xFF94A3B8)
                          : (isDanger
                              ? const Color(0xFFEF4444)
                              : (_eyeDetected ? const Color(0xFF10B981) : const Color(0xFFEF4444))),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: !_isMonitoring
                              ? const Color(0xFF94A3B8)
                              : (isDanger
                                  ? const Color(0xFFEF4444)
                                  : (_eyeDetected ? const Color(0xFF10B981) : const Color(0xFFEF4444))),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        !_isMonitoring
                            ? (LanguageService.instance.isEnglish ? 'Camera Sensor Ready' : 'Sensor Kamera Siaga')
                            : (isDanger
                                ? (LanguageService.instance.isEnglish ? 'Drowsiness Warning!' : 'Peringatan Kantuk!')
                                : (_eyeDetected ? LanguageService.instance.s.faceDetected : LanguageService.instance.s.faceNotDetected)),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: !_isMonitoring
                              ? (isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B))
                              : (isDanger
                                  ? const Color(0xFFEF4444)
                                  : (_eyeDetected
                                      ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                                      : const Color(0xFFEF4444))),
                        ),
                      ),
                    ],
                  ),
                ),

                // Tombol Perbesar (Hanya aktif saat monitoring)
                if (_isMonitoring)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _showCameraModal = true;
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF26B1D).withValues(alpha: isDark ? 0.2 : 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFF26B1D).withValues(alpha: 0.6),
                            width: 1,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.fullscreen_rounded,
                              color: Color(0xFFF26B1D),
                              size: 16,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Perbesar',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFF26B1D),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),

          // Camera Viewport Box
          Container(
            height: 240,
            width: double.infinity,
            color: isDark ? AppColors.darkCardBgSoft : const Color(0xFFEDF2F7),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Soft Illumination Glow Border when Night Vision is enabled
                if (_isNightVisionEnabled)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFFFFFFFF),
                            width: 18,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.95),
                              blurRadius: 36,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                // 1. Live camera preview with proper Aspect Ratio & Night Vision Phosphor / Flash Boost
                if (_cameraController != null && _cameraController!.value.isInitialized)
                  ClipRect(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeInOutCubic,
                      width: double.infinity,
                      height: 240,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _cameraController!.value.previewSize?.height.toDouble() ?? 360,
                          height: _cameraController!.value.previewSize?.width.toDouble() ?? 480,
                          child: _isNightVisionEnabled
                              ? ColorFiltered(
                                  // Matrix pencerah sensor malam: menguatkan kanal hijau & gamma pencahayaan wajah
                                  colorFilter: const ColorFilter.matrix(<double>[
                                    0.45, 0.65, 0.15, 0, 45,  // Red channel boosted
                                    0.35, 1.35, 0.25, 0, 70,  // Green phosphor sensitivity (night vision glow)
                                    0.15, 0.45, 0.55, 0, 35,  // Blue channel lifted
                                    0,    0,    0,    1, 0,   // Alpha
                                  ]),
                                  child: CameraPreview(_cameraController!),
                                )
                              : CameraPreview(_cameraController!),
                        ),
                      ),
                    ),
                  )
                else
                  // 2. Standby / Loading state in the center (bersih, rapi, dan tombol bisa langsung diklik)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isMonitoring) ...[
                            const CircularProgressIndicator(color: Color(0xFFF26B1D)),
                            const SizedBox(height: 12),
                            const Text(
                              'Memuat Kamera Live...',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ] else ...[
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF26B1D).withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.videocam_rounded,
                                size: 26,
                                color: Color(0xFFF26B1D),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              LanguageService.instance.isEnglish ? 'Camera Standby' : 'Kamera Siaga',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: isDark ? AppColors.darkTextPrimary : const Color(0xFF334155),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              LanguageService.instance.isEnglish ? 'Tap button below to start detection' : 'Tekan tombol untuk mulai deteksi',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: _startMonitoring,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF26B1D),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 3,
                                  shadowColor: const Color(0xFFF26B1D).withValues(alpha: 0.35),
                                ),
                                icon: const Icon(Icons.play_arrow_rounded, size: 24),
                                label: const Text(
                                  'MULAI PERJALANAN',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                // 3. Live HUD Overlays (HANYA MUNCUL SAAT MONITORING AKTIF, AGAR FRAME STANDBY BERSIH)
                if (_isMonitoring) ...[

                  IgnorePointer(
                    child: CustomPaint(
                      painter: _CockpitHudOverlayPainter(
                        isMonitoring: _isMonitoring,
                        isDanger: isDanger,
                        leftEyePct: (100 - (_result.ear < 0.2 ? 50 : 2)).toInt(),
                        rightEyePct: (100 - (_result.ear < 0.2 ? 50 : 1)).toInt(),
                      ),
                    ),
                  ),





                  // Bottom Pose Telemetry Line
                  Positioned(
                    bottom: 8,
                    left: 14,
                    right: 14,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'TILT: ${_isMonitoring ? "${_result.rollAngle.toStringAsFixed(1)}°" : "0.0°"}',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: (_enableHeadTilt && _result.rollAngle.abs() >= Thresholds.headTiltRollAngle)
                                ? const Color(0xFFD94126)
                                : const Color(0xFF334155),
                            fontFamily: 'monospace',
                          ),
                        ),
                        Text(
                          'BOB: ${_result.headBobCount}x / 5m',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: (_enableHeadBob && _result.headBobCount >= 2)
                                ? const Color(0xFFD94126)
                                : const Color(0xFF334155),
                            fontFamily: 'monospace',
                          ),
                        ),
                        Text(
                          isDanger ? 'STATUS: WASPADA' : 'STATUS: AMAN',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: isDanger ? const Color(0xFFD94126) : const Color(0xFF059669),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Lower Telemetry Panel inside Cockpit
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                // EAR Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF1E8),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFECEEF2)),
                            ),
                            child: const Icon(
                              Icons.visibility_rounded,
                              size: 16,
                              color: Color(0xFFF26B1D),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Flexible(
                            child: Text(
                              'EYE ASPECT RATIO (EAR)',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: Color(0xFF64748B),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isMonitoring ? _result.ear.toStringAsFixed(2) : '0.32',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF059669),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _result.ear < 0.22 ? '(Rendah)' : '(Optimal)',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF065F46),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // EAR Real-time Waveform Graph
                Container(
                  height: 36,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCardBgSoft : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isDark ? AppColors.darkCardBorder : const Color(0xFFFFF1E8)),
                  ),
                  child: CustomPaint(
                    painter: _EarWaveformPainter(history: _earHistory),
                  ),
                ),
                const SizedBox(height: 10),

                // 2 Telemetry Chips
                Row(
                  children: [
                    // Frekuensi Kedip
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkCardBgSoft : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isDark ? AppColors.darkCardBorder : const Color(0xFFFFF1E8)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF1E8),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFECEEF2)),
                              ),
                              child: const Icon(
                                Icons.lens_blur_rounded,
                                size: 15,
                                color: Color(0xFFF26B1D),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'FREKUENSI KEDIP',
                                    style: TextStyle(
                                      fontSize: 7.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF64748B),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '${_result.blinkCount}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A),
                                          ),
                                        ),
                                        const TextSpan(
                                          text: ' / mnt',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Deteksi Menguap
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkCardBgSoft : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isDark ? AppColors.darkCardBorder : const Color(0xFFFFF1E8)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFA7F3D0)),
                              ),
                              child: const Icon(
                                Icons.sentiment_satisfied_rounded,
                                size: 15,
                                color: Color(0xFF059669),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'DETEKSI MENGUAP',
                                    style: TextStyle(
                                      fontSize: 7.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF64748B),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '${_result.yawnCount}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF059669),
                                          ),
                                        ),
                                        const TextSpan(
                                          text: ' dlm 30m',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Posture Indicators Bar (Head Tilt & Head Bob Status)
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkCardBgSoft : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: (_enableHeadTilt && _result.rollAngle.abs() >= Thresholds.headTiltRollAngle)
                                ? const Color(0xFFFECACA)
                                : (isDark ? AppColors.darkCardBorder : const Color(0xFFFFF1E8)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.screen_rotation_rounded,
                              size: 15,
                              color: _enableHeadTilt ? const Color(0xFFF26B1D) : const Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'HEAD TILT (${_enableHeadTilt ? "ON" : "OFF"})',
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w800,
                                      color: _enableHeadTilt ? (isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B)) : const Color(0xFF94A3B8),
                                    ),
                                  ),
                                  Text(
                                    _isMonitoring
                                        ? '${_result.rollAngle.abs().toStringAsFixed(1)}°'
                                        : 'Siaga',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: (_enableHeadTilt && _result.rollAngle.abs() >= Thresholds.headTiltRollAngle)
                                          ? const Color(0xFFD94126)
                                          : (isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkCardBgSoft : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: (_enableHeadBob && _result.headBobCount >= 2)
                                ? const Color(0xFFFECACA)
                                : (isDark ? AppColors.darkCardBorder : const Color(0xFFFFF1E8)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.airline_seat_recline_extra_rounded,
                              size: 15,
                              color: _enableHeadBob ? const Color(0xFFF26B1D) : const Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'HEAD BOB (${_enableHeadBob ? "ON" : "OFF"})',
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w800,
                                      color: _enableHeadBob ? (isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B)) : const Color(0xFF94A3B8),
                                    ),
                                  ),
                                  Text(
                                    _isMonitoring
                                        ? '${_result.headBobCount}x / 5 mnt'
                                        : 'Siaga',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: (_enableHeadBob && _result.headBobCount >= 2)
                                          ? const Color(0xFFD94126)
                                          : (isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 3. REKOMENDASI PITSTOP ASSISTANT CARD
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildPitstopAssistantCard() {
    // Rekomendasi pitstop dari Maps API (desain Stitch yang sama): tombol kanan = buka
    // Google Maps, ketuk kartu = daftar rest area / minimarket / hotel-motel / SPBU terdekat.
    return PitstopCard(controller: _nearby);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 4. COCKPIT DRIVE CONTROL ACTION BUTTONS
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildCockpitDriveControls() {
    final isDark = ThemeService.instance.isDarkMode;
    return Column(
      children: [
        // Sub-actions: Snooze & Auto pilot status
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton.icon(
              onPressed: _snoozeAlert,
              style: OutlinedButton.styleFrom(
                backgroundColor: isDark ? AppColors.darkCardBgSoft : Colors.white,
                side: BorderSide(color: isDark ? AppColors.darkCardBorder : const Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              icon: Icon(Icons.snooze_rounded, size: 16, color: isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B)),
              label: Text(
                '${LanguageService.instance.s.snoozeAlert.toUpperCase()} (15 ${LanguageService.instance.s.minShort.toUpperCase()})',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: isDark ? AppColors.darkTextPrimary : const Color(0xFF334155),
                  letterSpacing: 0.5,
                ),
              ),
            ),

          ],
        ),
        const SizedBox(height: 12),

        // Tombol Selesaikan Perjalanan (hanya tampil saat monitoring aktif, tombol mulai sudah di tengah)
        if (_isMonitoring)
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () async {
                await _stopMonitoring();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF26B1D),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 4,
                shadowColor: const Color(0xFFF26B1D).withValues(alpha: 0.35),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.flag_rounded, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    LanguageService.instance.s.finishTrip.toUpperCase(),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

Future<void> _toggleNightVision() async {
    final nextState = !_isNightVisionEnabled;
    setState(() => _isNightVisionEnabled = nextState);

    // 1. Hardware Screen Brightness Flashlight (100% max brightness)
    try {
      if (nextState) {
        try {
          _previousBrightness = await ScreenBrightness.instance.system;
        } catch (_) {}
        await ScreenBrightness.instance.setScreenBrightness(1.0);
      } else {
        if (_previousBrightness != null) {
          await ScreenBrightness.instance.setScreenBrightness(_previousBrightness!);
        } else {
          await ScreenBrightness.instance.resetScreenBrightness();
        }
      }
    } catch (e) {
      debugPrint('ScreenBrightness error: ');
    }

    // 2. Hardware Camera Flash & Sensor Exposure Boost (Kompensasi Pencahayaan Lensa Kamera Depan)
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        await _cameraController!.setFlashMode(
          nextState ? FlashMode.torch : FlashMode.off,
        );
      } catch (_) {}

      try {
        if (nextState) {
          final maxExp = await _cameraController!.getMaxExposureOffset();
          await _cameraController!.setExposureOffset(maxExp.clamp(0.0, 2.0));
        } else {
          await _cameraController!.setExposureOffset(0.0);
        }
      } catch (_) {}
    }
  }

  Widget _buildNightVisionToggleBar() {
    final isDark = ThemeService.instance.isDarkMode;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _isNightVisionEnabled ? const Color(0xFF1E293B) : (isDark ? AppColors.darkCardBg : Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isNightVisionEnabled ? const Color(0xFFF59E0B) : (isDark ? AppColors.darkCardBorder : const Color(0xFFECEEF2)),
          width: _isNightVisionEnabled ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: _isNightVisionEnabled
                ? const Color(0xFFF59E0B).withValues(alpha: 0.25)
                : (isDark ? Colors.black.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.03)),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: _isNightVisionEnabled
                  ? const Color(0xFFFEF3C7)
                  : (isDark ? AppColors.darkCardBgSoft : const Color(0xFFFFF1E8)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _isNightVisionEnabled
                  ? Icons.flashlight_on_rounded
                  : Icons.nightlight_round,
              size: 20,
              color: _isNightVisionEnabled
                  ? const Color(0xFFD97706)
                  : const Color(0xFFF26B1D),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  LanguageService.instance.s.nightGlowTitle,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _isNightVisionEnabled ? Colors.white : (isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A)),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _isNightVisionEnabled
                      ? 'Lampu aktif · Wajah terang di kabin gelap'
                      : 'Bantu deteksi sensor AI di kondisi gelap',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: _isNightVisionEnabled ? const Color(0xFF94A3B8) : (isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B)),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OrangeSlidingToggle(
            value: _isNightVisionEnabled,
            onChanged: (val) {
              if (val != _isNightVisionEnabled) {
                _toggleNightVision();
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _dispatchSosEmergency() async {
    try {
      final user = AuthService.currentUser;
      final email = user?.email ?? 'buzzerbeater006@gmail.com';
      final name = AuthService.currentUserName ?? 'Pengemudi DrivingBuddy';
      final phone = await SosService.getSosPhone(userEmail: email);

      if (phone.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Kontak Darurat SOS belum diatur di Pengaturan! Pesan darurat tidak dapat dikirim.'),
              backgroundColor: Color(0xFFD94126),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 8),
            ),
          );
        }
        return;
      }

      final fix = _nearby.fix;
      final lat = fix?.lat ?? -6.2088;
      final lng = fix?.lng ?? 106.8456;

      await SosService.sendEmergencySos(
        rawPhone: phone,
        driverName: name,
        email: email,
        lat: lat,
        lng: lng,
        speedKmh: _currentSpeedKmh,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🚨 Darurat SOS terkirim otomatis ke WhatsApp $phone!'),
            backgroundColor: const Color(0xFFD94126),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error dispatching automated SOS: $e');
    }
  }
}

// ────────────────────────────────────────────────────────────────────────────
// CUSTOM PAINTER: Cockpit HUD Wireframe Overlay
// ────────────────────────────────────────────────────────────────────────────
class _CockpitHudOverlayPainter extends CustomPainter {
  final bool isMonitoring;
  final bool isDanger;
  final int leftEyePct;
  final int rightEyePct;

  _CockpitHudOverlayPainter({
    required this.isMonitoring,
    required this.isDanger,
    required this.leftEyePct,
    required this.rightEyePct,
  });

  @override
  void paint(Canvas canvas, Size size) {
// Center HUD brackets

    // Corner HUD brackets
    final bracketPaint = Paint()
      ..color = const Color(0xFF334155).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    const cornerLen = 16.0;
    const pad = 12.0;

    // Top-Left
    canvas.drawLine(const Offset(pad, pad + cornerLen), const Offset(pad, pad), bracketPaint);
    canvas.drawLine(const Offset(pad, pad), const Offset(pad + cornerLen, pad), bracketPaint);
    // Top-Right
    canvas.drawLine(Offset(size.width - pad - cornerLen, pad), Offset(size.width - pad, pad), bracketPaint);
    canvas.drawLine(Offset(size.width - pad, pad), Offset(size.width - pad, pad + cornerLen), bracketPaint);
    // Bottom-Left
    canvas.drawLine(Offset(pad, size.height - pad - cornerLen), Offset(pad, size.height - pad), bracketPaint);
    canvas.drawLine(Offset(pad, size.height - pad), Offset(pad + cornerLen, size.height - pad), bracketPaint);
    // Bottom-Right
    canvas.drawLine(Offset(size.width - pad - cornerLen, size.height - pad), Offset(size.width - pad, size.height - pad), bracketPaint);
    canvas.drawLine(Offset(size.width - pad, size.height - pad - cornerLen), Offset(size.width - pad, size.height - pad), bracketPaint);

// Wireframe wajah dihilangkan sesuai permintaan pengguna
    if (!isMonitoring) return;
  }

  @override
  bool shouldRepaint(_CockpitHudOverlayPainter old) =>
      old.isMonitoring != isMonitoring ||
      old.isDanger != isDanger ||
      old.leftEyePct != leftEyePct ||
      old.rightEyePct != rightEyePct;
}

// ────────────────────────────────────────────────────────────────────────────
// CUSTOM PAINTER: Real-time EAR Waveform Graph
// ────────────────────────────────────────────────────────────────────────────
class _EarWaveformPainter extends CustomPainter {
  final List<double> history;

  _EarWaveformPainter({required this.history});

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;

    final path = Path();
    final step = size.width / (history.length - 1).clamp(1, 99);

    for (int i = 0; i < history.length; i++) {
      // Map EAR (0.15 - 0.40) to Y (size.height to 0)
      final ear = history[i].clamp(0.15, 0.40);
      final norm = (ear - 0.15) / (0.40 - 0.15);
      final y = size.height - (norm * size.height * 0.8) - (size.height * 0.1);
      final x = i * step;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    // Gradient fill underneath
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillPaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(_EarWaveformPainter old) => true;
}

// ============================================================================
// PERINGATAN KRITIS (Alert Microsleep — Luxury Emergency HUD Dialog)
// Meme/Tok Dalang sepenuhnya dihapus sesuai permintaan pengguna
// ============================================================================

class MicrosleepAlertDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final String reason;
  final VoidCallback? onDismiss;
  final VoidCallback? onRestArea;

  /// Sumber tempat berhenti terdekat (Maps API). `null` = kartu contoh bawaan.
  final NearbyPlacesController? nearby;

  const MicrosleepAlertDialog({
    super.key,
    this.title = 'MATA TERPEJAM!\nISTIRAHAT SEKARANG',
    this.subtitle = 'SISTEM KESELAMATAN AKTIF',
    this.reason = 'Microsleep terdeteksi. Segera cari tempat aman untuk berhenti.',
    this.onDismiss,
    this.onRestArea,
    this.nearby,
  });

  @override
  State<MicrosleepAlertDialog> createState() => _MicrosleepAlertDialogState();
}

class _MicrosleepAlertDialogState extends State<MicrosleepAlertDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  AlertImageMode _imageMode = AlertImageMode.none;
  String? _customImagePath;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    HapticFeedback.heavyImpact();
    _loadAlertImageConfig();
  }

  Future<void> _loadAlertImageConfig() async {
    final mode = await AlertConfig.getImageMode();
    final path = await AlertConfig.getCustomImagePath();
    if (mounted) {
      setState(() {
        _imageMode = mode;
        _customImagePath = path;
      });
    }
  }


  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF14100E), // Obsidian Dark Canvas
              Color(0xFF2A140F),
              Color(0xFF171210),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildAlertHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 16),
                        _buildWarningVisual(),
                        const SizedBox(height: 20),
                        _buildAlertMessage(),
                        const SizedBox(height: 24),
                        _buildEmergencyTelemetryMetrics(),
                        const SizedBox(height: 20),
                        _buildRecommendationCard(),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                _buildAlertActions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlertHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFD94126).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD94126).withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFFD94126),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            widget.subtitle,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFFFFB4AB),
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  // Visual peringatan (MEME DIHAPUS: Hanya Custom atau High-Tech Hazard Halo)
  Widget _buildWarningVisual() {
    if (_imageMode == AlertImageMode.custom &&
        _customImagePath != null &&
        File(_customImagePath!).existsSync()) {
      return Container(
        height: 160,
        width: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD94126), width: 3),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD94126).withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.file(
          File(_customImagePath!),
          fit: BoxFit.cover,
        ),
      );
    }

    // Default: High-tech pulsing double-ring hazard emblem (No meme)
    return ScaleTransition(
      scale: _pulseAnimation,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFD94126).withValues(alpha: 0.18),
          border: Border.all(color: const Color(0xFFD94126), width: 3),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD94126).withValues(alpha: 0.4),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFFFB4AB),
            size: 68,
          ),
        ),
      ),
    );
  }

  Widget _buildAlertMessage() {
    return Column(
      children: [
        Text(
          widget.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: Color(0xFFFFDAD6),
            height: 1.15,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          widget.reason,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFFDCC1B4),
            height: 1.4,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildEmergencyTelemetryMetrics() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1916),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF564339)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(
            children: [
              Text('PERCLOS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFB8ACA4))),
              SizedBox(height: 2),
              Text('0.85', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFFFB4AB))),
              Text('KRITIS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFD94126))),
            ],
          ),
          Column(
            children: [
              Text('DURASI PEJAM', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFB8ACA4))),
              SizedBox(height: 2),
              Text('> 2.0 dtk', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFFFB4AB))),
              Text('MICROSLEEP', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFD94126))),
            ],
          ),
          Column(
            children: [
              Text('SIRENE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFB8ACA4))),
              SizedBox(height: 2),
              Text('AKTIF', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFF26B1D))),
              Text('LOOPING', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFF26B1D))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationCard() {
    final nearby = widget.nearby;
    if (nearby == null) {
      return _buildRecommendationBox(
        icon: Icons.local_cafe_rounded,
        title: 'Rest Area KM 57 (4.2 km lagi)',
      );
    }
    // Tempat berhenti terdekat dari server (mode darurat), dengan desain kartu yang sama.
    // Navigasinya lewat tombol "ARAHKAN KE REST AREA TERDEKAT" di bawah.
    return ListenableBuilder(
      listenable: nearby,
      builder: (context, _) {
        final view = PitstopView.from(nearby, urgent: true);
        return _buildRecommendationBox(
          icon: view.icon,
          title: view.title,
          subtitle: view.subtitle,
          busy: view.busy,
        );
      },
    );
  }

  Widget _buildRecommendationBox({
    required IconData icon,
    required String title,
    String? subtitle,
    bool busy = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF231F1C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF26B1D).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF26B1D).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFF26B1D),
                    ),
                  )
                : Icon(icon, color: const Color(0xFFF26B1D), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'REKOMENDASI PITSTOP AMAN',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFF26B1D),
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFEAE0DD),
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFB8A9A2),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertActions() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: () {
              widget.onDismiss?.call();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF26B1D),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 4,
            ),
            icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
            label: const Text(
              'SAYA SUDAH WASPADA (STOP ALARM)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.5),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: () {
              widget.onRestArea?.call();
              Navigator.of(context).pop();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFEAE0DD),
              side: const BorderSide(color: Color(0xFF564339)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.navigation_rounded, size: 18),
            label: const Text(
              'ARAHKAN KE REST AREA TERDEKAT',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// CUSTOM ORANGE SLIDING CAPSULE TOGGLE SWITCH (Tap & Drag Geser Kanan/Kiri)
// ────────────────────────────────────────────────────────────────────────────
class OrangeSlidingToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const OrangeSlidingToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const width = 56.0;
    const height = 28.0;
    const thumbSize = 22.0;
    const padding = 3.0;

    return GestureDetector(
      onTap: () => onChanged(!value),
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null) {
          if (details.primaryVelocity! > 50 && !value) {
            onChanged(true); // Geser ke kanan: Nyalakan
          } else if (details.primaryVelocity! < -50 && value) {
            onChanged(false); // Geser ke kiri: Matikan
          }
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: value
              ? const LinearGradient(
                  colors: [Color(0xFFF26B1D), Color(0xFFF97316)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: value ? null : const Color(0xFFCBD5E1),
          boxShadow: value
              ? [
                  BoxShadow(
                    color: const Color(0xFFF26B1D).withValues(alpha: 0.45),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              left: value ? (width - thumbSize - padding) : padding,
              child: Container(
                width: thumbSize,
                height: thumbSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
