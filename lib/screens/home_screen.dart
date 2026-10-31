import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/design_tokens.dart';
import '../widgets/ui/db_ui.dart';
import '../routes/app_routes.dart';
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../services/firebase_service.dart';
import '../models/account_config.dart';
import '../widgets/driving_buddy_app_bar.dart';
import '../features/nearby_places/nearby_places.dart';
import '../services/theme_service.dart';

// ============================================================================
// HOME SCREEN / COCKPIT (Beranda Telemetri Amber Accent — Luxury GT)
// ============================================================================

typedef HomeScreen = CockpitScreen;

class CockpitScreen extends StatefulWidget {
  final bool isActive;
  final VoidCallback? onStartMonitoring;
  final NearbyPlacesController? nearbyController;

  const CockpitScreen({
    super.key,
    this.isActive = true,
    this.onStartMonitoring,
    this.nearbyController,
  });

  @override
  State<CockpitScreen> createState() => _CockpitScreenState();
}

class _CockpitScreenState extends State<CockpitScreen>
    with SingleTickerProviderStateMixin {
  String _driverName = 'Pengemudi';
  late final NearbyPlacesController _nearby;
  late final bool _ownsNearby;

  // Realtime Sessions from Firestore
  List<Map<String, dynamic>> _userSessions = [];
  bool _isLoadingSessions = true;
  StreamSubscription? _sessionsSub;

  // Animation Controller for Gauge & Stats
  late AnimationController _animController;
  late Animation<double> _gaugeAnimation;

  // Camera Preview in Cockpit
  CameraController? _previewCamera;
  bool _isPreviewReady = false;
  bool _faceDetected = false;
  String _previewStatus = 'Menghubungkan sensor optik...';
  bool _isCameraExpanded = false;

  @override
  void initState() {
    super.initState();
    _ownsNearby = widget.nearbyController == null;
    _nearby = widget.nearbyController ?? NearbyPlacesController();
    if (_ownsNearby) {
      _nearby.start(askPermission: false);
    }

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _gaugeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );

    _loadDriverName();
    _listenSessions();
    if (widget.isActive) {
      _initPreviewCamera();
    }
    AccountConfig.nameNotifier.addListener(_onProfileNameChanged);
  }

  void _onProfileNameChanged() {
    if (mounted && AccountConfig.nameNotifier.value.isNotEmpty) {
      setState(() => _driverName = AccountConfig.nameNotifier.value);
    }
  }

  @override
  void didUpdateWidget(covariant CockpitScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _loadDriverName();
      if (_previewCamera == null || !_previewCamera!.value.isInitialized) {
        _initPreviewCamera();
      }
    } else if (!widget.isActive && oldWidget.isActive) {
      _previewCamera?.dispose();
      _previewCamera = null;
      if (mounted) {
        setState(() {
          _isPreviewReady = false;
          _previewStatus = 'Kamera siaga';
        });
      }
    }
  }

  @override
  void dispose() {
    AccountConfig.nameNotifier.removeListener(_onProfileNameChanged);
    _animController.dispose();
    _sessionsSub?.cancel();
    _previewCamera?.dispose();
    if (_ownsNearby) {
      _nearby.dispose();
    }
    super.dispose();
  }

  Future<void> _initPreviewCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _previewStatus = 'Kamera tidak ditemukan');
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _previewCamera = CameraController(
        front,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: kIsWeb ? null : ImageFormatGroup.nv21,
      );
      await _previewCamera!.initialize();
      if (mounted) {
        setState(() {
          _isPreviewReady = true;
          _faceDetected = false;
          _previewStatus = 'Kamera siaga • Arahkan wajah ke lensa untuk kalibrasi';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPreviewReady = false;
          _previewStatus = 'Wajah tidak terdeteksi / Kamera belum diizinkan';
        });
      }
    }
  }

  void _listenSessions() {
    _sessionsSub = SessionService.getUserSessionsStream().listen((sessions) {
      if (mounted) {
        setState(() {
          _userSessions = sessions;
          _isLoadingSessions = false;
        });
        _animController.forward(from: 0.0);
      }
    }, onError: (_) {
      if (mounted) setState(() => _isLoadingSessions = false);
    });
  }

  Future<void> _loadDriverName() async {
    try {
      if (AccountConfig.nameNotifier.value.isNotEmpty) {
        if (mounted) setState(() => _driverName = AccountConfig.nameNotifier.value);
        return;
      }
      final profile = await AccountConfig.getProfile();
      final localName = profile['name'];
      if (localName != null && localName.trim().isNotEmpty) {
        if (mounted) setState(() => _driverName = localName.trim());
        return;
      }
      final name = await AuthService.getUserName();
      if (mounted && name.isNotEmpty) {
        setState(() => _driverName = name);
      }
    } catch (_) {}
  }

  int get _avgScore {
    if (_userSessions.isEmpty) return 0;
    final total = _userSessions.fold<int>(
      0,
      (sum, s) => sum + ((s['driving_score'] ?? s['drivingScore'] ?? 100) as num).toInt(),
    );
    return (total / _userSessions.length).round();
  }

  double get _totalDurationHours {
    final totalSec = _userSessions.fold<int>(
      0,
      (sum, s) => sum + ((s['duration_seconds'] ?? s['durationSeconds'] ?? 0) as num).toInt(),
    );
    return double.parse((totalSec / 3600.0).toStringAsFixed(1));
  }

  double get _totalDistanceKm {
    final totalKm = _userSessions.fold<double>(
      0.0,
      (sum, s) => sum + ((s['distance_km'] ?? s['distanceKm'] ?? 0.0) as num).toDouble(),
    );
    return double.parse(totalKm.toStringAsFixed(1));
  }

  int get _totalMicrosleeps {
    return _userSessions.fold<int>(
      0,
      (sum, s) => sum + ((s['total_microsleeps'] ?? s['totalMicrosleeps'] ?? 0) as num).toInt(),
    );
  }

  String _greetingText() {
    final hour = DateTime.now().hour;
    if (hour >= 4 && hour < 11) return 'Selamat Pagi';
    if (hour >= 11 && hour < 15) return 'Selamat Siang';
    if (hour >= 15 && hour < 18) return 'Selamat Sore';
    return 'Selamat Malam';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final isDark = ThemeService.instance.isDarkMode;

        return Scaffold(
          backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
          appBar: const DrivingBuddyAppBar(title: 'Beranda'),
          body: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDriverGreetingBar(),
                const SizedBox(height: 16),
                _buildGuardianMeshLaunchCard(context),
                const SizedBox(height: 20),
                _buildWeeklyTelemetryDialCard(),
                const SizedBox(height: 20),
                _buildRecentActivitiesSection(context),
                const SizedBox(height: 20),
                _buildRestAreaQuickCard(context),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 1. DRIVER GREETING & LIVE STATUS BAR
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildDriverGreetingBar() {
    final isDark = ThemeService.instance.isDarkMode;
    final initial = _driverName.trim().isNotEmpty ? _driverName.trim()[0].toUpperCase() : 'P';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCardBg : DbColors.pureWhite,
        borderRadius: BorderRadius.circular(DbRadius.r20),
        border: Border.all(
          color: isDark ? AppColors.darkCardBorder : DbColors.hairline,
        ),
        boxShadow: isDark ? DbShadow.cardDark : DbShadow.card,
      ),
      child: Row(
        children: [
          // Driver Avatar Initial
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [DbColors.navy, Color(0xFF1E293B)],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: DbColors.orange.withValues(alpha: 0.35),
                width: 1.2,
              ),
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Greeting & Name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      _greetingText(),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.darkTextSecondary : DbColors.inkMuted,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkTextSecondary : DbColors.inkSubtle,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'GT TELEMETRI',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: DbColors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _driverName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? AppColors.darkTextPrimary : DbColors.ink,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Online Indicator Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSuccessBg : const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(DbRadius.pill),
              border: Border.all(
                color: isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                const Text(
                  'ONLINE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF065F46),
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 2. GUARDIAN MESH READY LAUNCH CARD
  // ──────────────────────────────────────────────────────────────────────────
  // ──────────────────────────────────────────────────────────────────────────
  // 2. GUARDIAN MESH READY LAUNCH CARD (With Real Camera Preview & Detection Test)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildGuardianMeshLaunchCard(BuildContext context) {
    final isDark = ThemeService.instance.isDarkMode;
    final statusColor = _faceDetected ? const Color(0xFF059669) : const Color(0xFFD94126);
    final statusBg = _faceDetected
        ? (isDark ? AppColors.darkSuccessBg : const Color(0xFFECFDF5))
        : (isDark ? AppColors.darkDangerBg : const Color(0xFFFEF2F2));
    final statusBorder = _faceDetected
        ? (isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0))
        : (isDark ? const Color(0xFFD94126) : const Color(0xFFFECACA));

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCardBg : null,
        gradient: isDark
            ? null
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
              ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.darkCardBorder : const Color(0xFFECEEF2),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : const Color(0xFFF26B1D).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 3,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              gradient: LinearGradient(
                colors: [Colors.transparent, Color(0xFFF26B1D), Colors.transparent],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkCardBgSoft : const Color(0xFFFFF1E8),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDark ? AppColors.darkCardBorder : const Color(0xFFECEEF2),
                              ),
                            ),
                            child: const Icon(
                              Icons.videocam_rounded,
                              color: Color(0xFFF26B1D),
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Guardian Mesh Status',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A),
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusBorder),
                      ),
                      child: Text(
                        _faceDetected ? 'SENSOR AKTIF' : 'SENSOR SIAGA',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Live Camera Preview — expandable on tap
                GestureDetector(
                  onTap: () => setState(() => _isCameraExpanded = !_isCameraExpanded),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    height: _isCameraExpanded ? 300 : 180,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isCameraExpanded
                            ? const Color(0xFFF26B1D)
                            : const Color(0xFFFFF1E8),
                        width: _isCameraExpanded ? 1.5 : 1.0,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_isPreviewReady && _previewCamera != null && _previewCamera!.value.isInitialized)
                          ClipRect(
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: _previewCamera!.value.previewSize != null
                                    ? _previewCamera!.value.previewSize!.height.toDouble()
                                    : 360,
                                height: _previewCamera!.value.previewSize != null
                                    ? _previewCamera!.value.previewSize!.width.toDouble()
                                    : 480,
                                child: CameraPreview(_previewCamera!),
                              ),
                            ),
                          )
                        else
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.videocam_off_rounded, color: Colors.white70, size: 26),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Pratinjau Sensor Kamera',
                                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Ketuk untuk memperbesar',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                                ),
                              ],
                            ),
                          ),

                        // ── Expand / collapse hint icon ──────────────
                        Positioned(
                          top: 8,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _isCameraExpanded
                                  ? Icons.fullscreen_exit_rounded
                                  : Icons.fullscreen_rounded,
                              color: Colors.white70,
                              size: 16,
                            ),
                          ),
                        ),

                        // ── Status bar at bottom ─────────────────────
                        Positioned(
                          bottom: 10,
                          left: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _faceDetected ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                                  color: statusColor,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _previewStatus,
                                    style: TextStyle(
                                      color: _faceDetected ? Colors.white : const Color(0xFFFCA5A5),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _isCameraExpanded ? 'Ketuk untuk kecilkan' : 'Ketuk untuk perbesar',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                DbPressable(
                  onTap: () {
                    if (widget.onStartMonitoring != null) {
                      widget.onStartMonitoring!();
                    } else {
                      Navigator.pushNamed(context, AppRoutes.monitor);
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [DbColors.orange, Color(0xFFE05615)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(DbRadius.r16),
                      boxShadow: [
                        BoxShadow(
                          color: DbColors.orange.withValues(alpha: 0.38),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.speed_rounded, size: 24, color: Colors.white),
                        SizedBox(width: 10),
                        Text(
                          'MULAI PERJALANAN',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 3. WEEKLY TELEMETRY DIAL & REALTIME PERFORMANCE METRICS (Animated Dial & Stats)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildWeeklyTelemetryDialCard() {
    return AnimatedBuilder(
      animation: _gaugeAnimation,
      builder: (context, _) {
        final isDark = ThemeService.instance.isDarkMode;
        final animatedScore = (_avgScore * _gaugeAnimation.value).round();
        final animatedScoreFraction = (_avgScore / 100.0) * _gaugeAnimation.value;
        final animatedDuration = (_totalDurationHours * _gaugeAnimation.value).toStringAsFixed(1);
        final animatedDistance = (_totalDistanceKm * _gaugeAnimation.value).toStringAsFixed(0);

        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCardBg : null,
            gradient: isDark
                ? null
                : const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
                  ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? AppColors.darkCardBorder : const Color(0xFFECEEF2),
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.25)
                    : const Color(0xFFF26B1D).withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ANALISIS TELEMETRI REALTIME',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: Color(0xFFD9560F),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Skor Kewaspadaan Rata-rata',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCardBgSoft : const Color(0xFFFFF1E8),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark ? AppColors.darkCardBorder : const Color(0xFFECEEF2),
                      ),
                    ),
                    child: const Icon(
                      Icons.insights_rounded,
                      color: Color(0xFFF26B1D),
                      size: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              Center(
                child: SizedBox(
                  width: 170,
                  height: 170,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(170, 170),
                        painter: _CircularGaugePainter(
                          score: animatedScoreFraction.clamp(0.0, 1.0),
                          trackColor: isDark ? const Color(0xFF253042) : const Color(0xFFFFF1E8),
                          activeColor: const Color(0xFFF26B1D),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            animatedScore >= 80 ? Icons.visibility_rounded : Icons.warning_amber_rounded,
                            color: animatedScore >= 80 ? const Color(0xFF059669) : const Color(0xFFF26B1D),
                            size: 22,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '$animatedScore',
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                  color: isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A),
                                  letterSpacing: -1.0,
                                ),
                              ),
                              const Text(
                                '%',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFF26B1D),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: animatedScore >= 80
                                  ? (isDark ? AppColors.darkSuccessBg : const Color(0xFFECFDF5))
                                  : (isDark ? AppColors.darkCardBgSoft : const Color(0xFFFFF1E8)),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: animatedScore >= 80 ? const Color(0xFFA7F3D0) : const Color(0xFFECEEF2),
                              ),
                            ),
                            child: Text(
                              _userSessions.isEmpty ? 'BELUM ADA DATA' : (animatedScore >= 80 ? 'STATUS PRIMA' : 'PERLU ISTIRAHAT'),
                              style: TextStyle(
                                fontSize: 7.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                                color: _userSessions.isEmpty
                                    ? (isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B))
                                    : (animatedScore >= 80 ? const Color(0xFF065F46) : const Color(0xFFD9560F)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),

              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCardBgSoft : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? AppColors.darkCardBorder : const Color(0xFFFFF1E8),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                      blurRadius: 6,
                    )
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildStravaMetricCol(
                        label: 'DURASI TOTAL',
                        value: animatedDuration,
                        unit: 'jam',
                        valueColor: isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A),
                      ),
                    ),
                    Container(
                      height: 36,
                      width: 1,
                      color: isDark ? AppColors.darkCardBorder : const Color(0xFFFFF1E8),
                    ),
                    Expanded(
                      child: _buildStravaMetricCol(
                        label: 'JARAK TEMPUH',
                        value: animatedDistance,
                        unit: 'km',
                        valueColor: isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A),
                      ),
                    ),
                    Container(
                      height: 36,
                      width: 1,
                      color: isDark ? AppColors.darkCardBorder : const Color(0xFFFFF1E8),
                    ),
                    Expanded(
                      child: _buildStravaMetricCol(
                        label: 'MICROSLEEP',
                        value: '$_totalMicrosleeps',
                        unit: 'insiden',
                        valueColor: _totalMicrosleeps == 0 ? const Color(0xFF059669) : const Color(0xFFD94126),
                        unitColor: _totalMicrosleeps == 0 ? const Color(0xFF059669) : const Color(0xFFD94126),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStravaMetricCol({
    required String label,
    required String value,
    required String unit,
    required Color valueColor,
    Color? unitColor,
  }) {
    final isDark = ThemeService.instance.isDarkMode;
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: valueColor,
            letterSpacing: -0.5,
          ),
        ),
        Text(
          unit,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: unitColor ?? const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 4. AKTIVITAS TERAKHIR (Realtime Firestore Sessions — Animated Waves)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildRecentActivitiesSection(BuildContext context) {
    final isDark = ThemeService.instance.isDarkMode;
    if (_isLoadingSessions) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(color: Color(0xFFF26B1D), strokeWidth: 2),
        ),
      );
    }

    final recentList = _userSessions.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      'Aktivitas Terakhir',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCardBgSoft : const Color(0xFFFFF1E8),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark ? AppColors.darkCardBorder : const Color(0xFFECEEF2),
                      ),
                    ),
                    child: Text(
                      '${_userSessions.length} Selesai',
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFD9560F),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, AppRoutes.history),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Lihat Semua',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFF26B1D),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: Color(0xFFF26B1D), size: 16),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (recentList.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCardBg : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppColors.darkCardBorder : const Color(0xFFECEEF2),
              ),
            ),
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.route_rounded, color: Color(0xFFF26B1D), size: 36),
                  const SizedBox(height: 8),
                  Text(
                    'Belum Ada Riwayat Perjalanan',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Mulai sesi berkendara pertamamu dengan menekan tombol di atas!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...recentList.asMap().entries.map((entry) {
            final idx = entry.key;
            final s = entry.value;

            final score = ((s['driving_score'] ?? s['drivingScore'] ?? 100) as num).toInt();
            final durSec = ((s['duration_seconds'] ?? s['durationSeconds'] ?? 0) as num).toInt();
            final distKm = ((s['distance_km'] ?? s['distanceKm'] ?? 0.0) as num).toDouble();
            final avgSpd = ((s['avg_speed_kmh'] ?? s['avgSpeedKmh'] ?? 0.0) as num).toDouble();
            final avgEar = ((s['avg_ear'] ?? s['avgEar'] ?? 0.28) as num).toDouble();
            final micro = ((s['total_microsleeps'] ?? s['totalMicrosleeps'] ?? 0) as num).toInt();
            final yawns = ((s['total_yawns'] ?? s['totalYawns'] ?? 0) as num).toInt();

            final min = (durSec % 3600) ~/ 60;
            final hr = durSec ~/ 3600;
            final durStr = hr > 0 ? '${hr}j ${min}m' : '${min}m';

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildRealTripCard(
                tripIndex: idx + 1,
                dateStr: _formatSessionDate(s['started_at']?.toString()),
                score: score,
                distanceKm: distKm,
                durationStr: durStr,
                avgSpeedKmh: avgSpd,
                avgEar: avgEar,
                microsleeps: micro,
                yawns: yawns,
              ),
            );
          }),
      ],
    );
  }

  String _formatSessionDate(String? iso) {
    if (iso == null) return 'Baru Saja';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return 'Baru Saja';
    final now = DateTime.now();
    if (now.difference(dt).inDays == 0) return 'Hari ini';
    if (now.difference(dt).inDays == 1) return 'Kemarin';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Widget _buildRealTripCard({
    required int tripIndex,
    required String dateStr,
    required int score,
    required double distanceKm,
    required String durationStr,
    required double avgSpeedKmh,
    required double avgEar,
    required int microsleeps,
    required int yawns,
  }) {
    final isDark = ThemeService.instance.isDarkMode;
    final isGood = score >= 80;
    final scoreColor = isGood ? const Color(0xFF059669) : DbColors.orange;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCardBg : DbColors.pureWhite,
        borderRadius: BorderRadius.circular(DbRadius.r16),
        border: Border.all(
          color: isDark ? AppColors.darkCardBorder : DbColors.hairline,
        ),
        boxShadow: isDark ? DbShadow.cardDark : DbShadow.card,
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'SESI PERJALANAN #$tripIndex',
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: DbColors.orange,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkCardBorder : DbColors.inkSubtle,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            dateStr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.darkTextSecondary : DbColors.inkMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Telemetri: EAR ${avgEar.toStringAsFixed(2)} · ${avgSpeedKmh.toStringAsFixed(0)} km/jam',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isDark ? AppColors.darkTextPrimary : DbColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isGood
                      ? (isDark ? AppColors.darkSuccessBg : const Color(0xFFECFDF5))
                      : (isDark ? AppColors.darkCardBgSoft : const Color(0xFFFFF1E8)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isGood ? const Color(0xFFA7F3D0) : const Color(0xFFECEEF2),
                  ),
                ),
                child: Text(
                  '$score%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: scoreColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              _buildTripStatCol('JARAK', '${distanceKm.toStringAsFixed(1)} km'),
              _buildTripStatCol('WAKTU', durationStr),
              _buildTripStatCol('KECEPATAN', '${avgSpeedKmh.toStringAsFixed(0)} km/h'),
              _buildTripStatCol(
                'STATUS',
                microsleeps > 0 ? '$microsleeps Sleep' : (yawns > 0 ? '$yawns Menguap' : 'Aman'),
                color: microsleeps > 0 ? const Color(0xFFD94126) : (yawns > 0 ? DbColors.orange : const Color(0xFF059669)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          SizedBox(
            height: 28,
            width: double.infinity,
            child: CustomPaint(
              painter: _RouteSparklinePainter(color: scoreColor, animationValue: _gaugeAnimation.value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripStatCol(String label, String value, {Color? color}) {
    final isDark = ThemeService.instance.isDarkMode;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.darkTextSecondary : const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: color ?? (isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A)),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
  Widget _buildRestAreaQuickCard(BuildContext context) {
    return PitstopCard(controller: _nearby);
  }
}

// ────────────────────────────────────────────────────────────────────────────
// CUSTOM PAINTER: Circular Dial Gauge
// ────────────────────────────────────────────────────────────────────────────
class _CircularGaugePainter extends CustomPainter {
  final double score; // 0.0 - 1.0
  final Color trackColor;
  final Color activeColor;

  _CircularGaugePainter({
    required this.score,
    required this.trackColor,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 24) / 2;

    // Background track circle
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11;
    canvas.drawCircle(center, radius, trackPaint);

    // Active arc
    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 11;

    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * score;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(_CircularGaugePainter old) =>
      old.score != score || old.trackColor != trackColor || old.activeColor != activeColor;
}

// ────────────────────────────────────────────────────────────────────────────
// CUSTOM PAINTER: Mini Route Sparkline
// ────────────────────────────────────────────────────────────────────────────
class _RouteSparklinePainter extends CustomPainter {
  final Color color;
  final double animationValue;

  _RouteSparklinePainter({required this.color, this.animationValue = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    path.moveTo(0, size.height * 0.75);
    path.cubicTo(
      size.width * 0.25, size.height * 0.7,
      size.width * 0.35, size.height * 0.2,
      size.width * 0.5, size.height * 0.35,
    );
    path.cubicTo(
      size.width * 0.65, size.height * 0.5,
      size.width * 0.8, size.height * 0.1,
      size.width, size.height * 0.2,
    );

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    // Fill underneath
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    // Endpoint dot
    final dotPaint = Paint()..color = color;
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.35), 3.5, dotPaint);
  }

  @override
  bool shouldRepaint(_RouteSparklinePainter old) => old.color != color;
}


