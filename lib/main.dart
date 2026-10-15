import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'supabase_service.dart';
import 'auth_screen.dart';
import 'driving_card_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'core/thresholds.dart';
import 'models/detection_result.dart';
import 'services/alert_service.dart';
import 'services/alert_config.dart';
import 'services/camera_image_converter.dart';
import 'services/drowsiness_detector.dart';
import 'services/face_mesh_service.dart';


// ============================================================================
// MAIN ENTRY POINT
// ============================================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const DrivingBuddyApp());
}

// ============================================================================
// THEME & CONSTANTS
// ============================================================================

class AppColors {
  static const Color primary = Color(0xFFD4842A);
  static const Color primaryDark = Color(0xFFB5691E);
  static const Color primaryLight = Color(0xFFF5E6D0);
  static const Color accent = Color(0xFFF5A623);
  static const Color background = Color(0xFFF8F5F0);
  static const Color surface = Colors.white;
  static const Color cardBg = Colors.white;
  static const Color textPrimary = Color(0xFF2D2D2D);
  static const Color textSecondary = Color(0xFF7A7A7A);
  static const Color cameraBg = Color(0xFF1A1A2E);
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color danger = Color(0xFFE53935);
  static const Color dangerBg = Color(0xFFFFF3E0);
  static const Color chipBg = Color(0xFFFFF8E1);
}

// ============================================================================
// KONFIGURASI SERVER — Disimpan permanen via SharedPreferences
// ============================================================================

// ACCOUNT CONFIG — Simpan profil user secara lokal
// ============================================================================

class AccountConfig {
  static const _keyName = 'account_name';
  static const _keyEmail = 'account_email';

  static Future<Map<String, String>> getProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'name': prefs.getString(_keyName) ?? '',
      'email': prefs.getString(_keyEmail) ?? '',
    };
  }

  static Future<void> saveProfile(String name, String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyName, name);
    await prefs.setString(_keyEmail, email);
  }

  static Future<void> clearProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyName);
    await prefs.remove(_keyEmail);
  }
}

// ============================================================================
// DATA MODELS
// ============================================================================

class TripRecord {
  final String routeName;
  final String dateInfo;
  final String timeRange;
  final String duration;
  final String warningLabel;
  final Color warningColor;
  final String driverStatus;
  final double avgEAR;
  final int avgSpeed;
  final List<double> earGraphData;

  TripRecord({
    required this.routeName,
    required this.dateInfo,
    required this.timeRange,
    required this.duration,
    required this.warningLabel,
    required this.warningColor,
    required this.driverStatus,
    required this.avgEAR,
    required this.avgSpeed,
    required this.earGraphData,
  });
}

class RestAreaRecommendation {
  final String name;
  final String distance;
  final List<String> facilities;

  RestAreaRecommendation({
    required this.name,
    required this.distance,
    required this.facilities,
  });
}

class WeeklySummary {
  int totalSessions;
  String totalDuration;
  int safetyScore;
  String comparisonText;

  WeeklySummary({
    required this.totalSessions,
    required this.totalDuration,
    required this.safetyScore,
    required this.comparisonText,
  });
}

// ============================================================================
// MOCK / DUMMY DATA — Untuk Riwayat & Cockpit (data historis, bukan real-time)
// ============================================================================

final List<TripRecord> dummyTripRecords = [
  TripRecord(
    routeName: 'Amphoreus (KM 72 – 120)',
    dateInfo: 'Malam ini',
    timeRange: '21:15 – 23:30',
    duration: '02:15:00',
    warningLabel: '1x Peringatan Ringan',
    warningColor: AppColors.warning,
    driverStatus: 'Kantuk halus m-34',
    avgEAR: 0.29,
    avgSpeed: 88,
    earGraphData: [0.32, 0.30, 0.28, 0.31, 0.27, 0.29, 0.26, 0.30, 0.28],
  ),
  TripRecord(
    routeName: 'Nodkrai – Snezhnaya (Eye of Graeae)',
    dateInfo: 'Kemarin',
    timeRange: '08:10 – 10:10',
    duration: '01:40:00',
    warningLabel: '0 Peringatan',
    warningColor: AppColors.success,
    driverStatus: 'Fokus Optimal',
    avgEAR: 0.35,
    avgSpeed: 78,
    earGraphData: [0.34, 0.35, 0.36, 0.34, 0.35, 0.33, 0.36, 0.35, 0.34],
  ),
  TripRecord(
    routeName: 'Monstadt – Liyue (Trans Star Rail)',
    dateInfo: '14 Okt',
    timeRange: '18:00 – 21:45',
    duration: '03:45:00',
    warningLabel: '2x Jeda Istirahat Direkomendasikan',
    warningColor: AppColors.danger,
    driverStatus: 'Rest Area KM 283',
    avgEAR: 0.27,
    avgSpeed: 94,
    earGraphData: [0.30, 0.28, 0.25, 0.27, 0.22, 0.26, 0.24, 0.28, 0.25],
  ),
  TripRecord(
    routeName: 'Amphoreus – Planarcadia',
    dateInfo: '12 Okt',
    timeRange: '06:30 – 08:45',
    duration: '02:15:00',
    warningLabel: '0 Peringatan',
    warningColor: AppColors.success,
    driverStatus: 'Fokus Optimal',
    avgEAR: 0.33,
    avgSpeed: 65,
    earGraphData: [0.33, 0.34, 0.32, 0.35, 0.33, 0.34, 0.33, 0.32, 0.34],
  ),
];

final RestAreaRecommendation dummyRestArea = RestAreaRecommendation(
  name: 'Rest Area KM 57',
  distance: '750 m ke depan',
  facilities: ['SPBU', 'Kopi', 'Istirahat'],
);

WeeklySummary dummyWeeklySummary = WeeklySummary(
  totalSessions: 12,
  totalDuration: '100j 40m',
  safetyScore: 95,
  comparisonText: '↓ 3 sesi dibanding pekan lalu.',
);

// ============================================================================
// APP ROOT
// ============================================================================

class DrivingBuddyApp extends StatelessWidget {
  const DrivingBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DrivingBuddy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
          primary: AppColors.primary,
          surface: AppColors.surface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: AppColors.cardBg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              letterSpacing: 0.3,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      home: AuthService.isLoggedIn ? const MainShell() : const LoginScreen(),
    );
  }
}

// ============================================================================
// MAIN SHELL — 3-Tab BottomNavigationBar
// ============================================================================

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  final GlobalKey<MonitorScreenState> _monitorKey = GlobalKey();

  void _switchToTab(int index) => setState(() => _currentIndex = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          CockpitScreen(onStartMonitoring: () => _switchToTab(1)),
          MonitorScreen(key: _monitorKey, isActive: _currentIndex == 1),
          const HistoryScreen(),
        ],
      ),
      // ── Floating pill bottom nav ──
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Container(
              height: 66,
            decoration: BoxDecoration(
              color: const Color(0xFF1C2333),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _NavItem(
                  icon: Icons.dashboard_rounded,
                  label: 'Cockpit',
                  index: 0,
                  current: _currentIndex,
                  onTap: _switchToTab,
                ),
                _NavItem(
                  icon: Icons.videocam_rounded,
                  label: 'Monitor',
                  index: 1,
                  current: _currentIndex,
                  onTap: _switchToTab,
                  isCenter: true,
                ),
                _NavItem(
                  icon: Icons.history_rounded,
                  label: 'Riwayat',
                  index: 2,
                  current: _currentIndex,
                  onTap: _switchToTab,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int current;
  final ValueChanged<int> onTap;
  final bool isCenter;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.current,
    required this.onTap,
    this.isCenter = false,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = current == index;

    if (isCenter) {
      return GestureDetector(
        onTap: () => onTap(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: isActive
                ? const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : const LinearGradient(
                    colors: [Color(0xFF252D3F), Color(0xFF252D3F)]),
            shape: BoxShape.circle,
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    )
                  ]
                : [],
          ),
          child: Icon(icon,
              color: isActive ? Colors.white : const Color(0xFF6B7280),
              size: 26),
        ),
      );
    }

    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.primary.withOpacity(0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon,
                  color: isActive
                      ? AppColors.primary
                      : const Color(0xFF6B7280),
                  size: 22),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color:
                    isActive ? AppColors.primary : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// SHARED APP BAR WIDGET
// ============================================================================

class DrivingBuddyAppBar extends StatelessWidget {
  final List<Widget>? trailing;
  const DrivingBuddyAppBar({super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          // Logo mark
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.directions_car_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'DrivingBuddy',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Pantau keselamatan',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),

          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: const Color(0xFF10B981).withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'On-Device AI',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF059669),
                  ),
                ),
              ],
            ),
          ),

          if (trailing != null) ...trailing!,
          const SizedBox(width: 8),

          // Profile / Settings button
          Builder(
            builder: (ctx) => GestureDetector(
              onTap: () => Navigator.push(
                ctx,
                MaterialPageRoute(
                    builder: (_) => const AccountSettingsScreen()),
              ),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                    )
                  ],
                ),
                child: const Icon(Icons.settings_rounded,
                    color: AppColors.textSecondary, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


// ============================================================================
// LAYAR 1 — COCKPIT (Dashboard Beranda — Tanpa Kamera)
// ============================================================================


class CockpitScreen extends StatelessWidget {
  final VoidCallback onStartMonitoring;

  const CockpitScreen({super.key, required this.onStartMonitoring});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              const DrivingBuddyAppBar(),
              const SizedBox(height: 12),
              _buildSystemReadyCard(),
              const SizedBox(height: 12),
              _buildStartMonitoringButton(context),
              const SizedBox(height: 16),
              _buildQuickStatsRow(),
              const SizedBox(height: 16),
              _buildLastTripCard(),
              const SizedBox(height: 16),
              _buildSafetyTipsCard(),
              const SizedBox(height: 16),
              _buildRestAreaButton(context),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSystemReadyCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A2E), Color(0xFF2D2B55)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A2E).withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.psychology_rounded,
                    color: AppColors.success, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI On-Device Siap',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tidak perlu server atau internet. Deteksi kantuk berjalan langsung di HP kamu.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.6),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildCheckRow(Icons.camera_alt_rounded, 'Kamera Depan',
              'Standby — siap diaktifkan'),
          const SizedBox(height: 8),
          _buildCheckRow(Icons.psychology_rounded, 'ML Kit Face Mesh',
              'On-device, tanpa internet'),
          const SizedBox(height: 8),
          _buildCheckRow(Icons.shield_rounded, 'Privasi Terjaga',
              'Data tidak keluar dari HP'),
        ],
      ),
    );
  }

  Widget _buildCheckRow(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Icon(icon, color: AppColors.success, size: 16),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(0.45),
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildStartMonitoringButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onStartMonitoring,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 4,
            shadowColor: AppColors.primary.withOpacity(0.35),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.videocam_rounded, size: 24),
              SizedBox(width: 10),
              Text(
                'Mulai Monitoring',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStatsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _QuickStatCard(
            icon: Icons.route_rounded,
            iconColor: AppColors.primary,
            value: '${dummyWeeklySummary.totalSessions}',
            label: 'Sesi Pekan Ini',
          ),
          const SizedBox(width: 10),
          _QuickStatCard(
            icon: Icons.access_time_rounded,
            iconColor: Colors.blue,
            value: dummyWeeklySummary.totalDuration,
            label: 'Total Waktu',
          ),
          const SizedBox(width: 10),
          _QuickStatCard(
            icon: Icons.verified_rounded,
            iconColor: AppColors.success,
            value: '${dummyWeeklySummary.safetyScore}%',
            label: 'Skor Aman',
          ),
        ],
      ),
    );
  }

  Widget _buildLastTripCard() {
    if (dummyTripRecords.isEmpty) return const SizedBox.shrink();
    final last = dummyTripRecords.first;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Perjalanan Terakhir',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                last.dateInfo,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      last.routeName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      last.timeRange,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  last.duration,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: last.warningColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: last.warningColor.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  last.warningColor == AppColors.success
                      ? Icons.check_circle_rounded
                      : Icons.warning_amber_rounded,
                  size: 12,
                  color: last.warningColor,
                ),
                const SizedBox(width: 4),
                Text(
                  last.warningLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: last.warningColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyTipsCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.chipBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.local_cafe_rounded,
                color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tips Keselamatan',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Istirahat 15 menit setiap 2 jam berkendara. Minum kopi atau cuci muka untuk membantu kewaspadaan.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRestAreaButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Mencari Rest Area terdekat...'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          icon: const Icon(Icons.local_parking_rounded, size: 18),
          label: const Text('Cari Rest Area Terdekat'),
        ),
      ),
    );
  }
}

class _QuickStatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _QuickStatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// LAYAR 2 — MONITOR (Kamera + Pemantauan Real-time)
//
//   • Timer berjalan saat isActive == true
//   • Kamera & WebSocket aktif saat user tekan "Mulai Sesi"
//   • Data EAR, status, dll dari Python server via WebSocket
// ============================================================================

class MonitorScreen extends StatefulWidget {
  final bool isActive;

  const MonitorScreen({super.key, required this.isActive});

  @override
  MonitorScreenState createState() => MonitorScreenState();
}

class MonitorScreenState extends State<MonitorScreen> {
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

  // Hasil deteksi real-time
  DetectionResult _result = DetectionResult.initial;
  bool _eyeDetected = false;
  String _cameraMode = 'Standby';

  // Alert guard
  bool _isAlertShowing = false;
  static const int _alertCooldownSeconds = 10;

  // === Supabase Session Tracking ===
  String? _currentSessionId;
  DateTime? _sessionStartTime;
  int _drowsyCount = 0;
  int _yawnCount = 0;
  int _microsleepCount = 0;

  @override
  void didUpdateWidget(covariant MonitorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive && _isMonitoring) _resumeTimer();
    if (!widget.isActive && oldWidget.isActive) _pauseTimer();
  }

  @override
  void dispose() {
    _drivingTimer?.cancel();
    _cameraController?.dispose();
    _mesh.dispose();
    _alert.dispose();
    WakelockPlus.disable();
    super.dispose();
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
    setState(() {
      _isMonitoring = true;
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
      final result = _detector.update(points);

      // Cek kondisi bahaya
      final isSleep = result.status == DriverStatus.sleep;
      final isExcessiveYawn = result.yawnCount >= Thresholds.yawnAlertFreq;
      final isDrowsy = result.status == DriverStatus.drowsy;

      if (isSleep) {
        _microsleepCount++;
        if (AuthService.isLoggedIn && _currentSessionId != null) {
          SessionService.logEvent(
            sessionId: _currentSessionId!,
            eventType: 'microsleep',
          );
        }
      } else if (isExcessiveYawn) {
        _yawnCount++;
        if (AuthService.isLoggedIn && _currentSessionId != null) {
          SessionService.logEvent(
            sessionId: _currentSessionId!,
            eventType: 'yawn',
          );
        }
      } else if (isDrowsy) {
        _drowsyCount++;
        if (AuthService.isLoggedIn && _currentSessionId != null) {
          SessionService.logEvent(
            sessionId: _currentSessionId!,
            eventType: 'drowsy',
          );
        }
      }

      if ((isSleep || isExcessiveYawn) && !_isAlertShowing) {
        await _alert.playAlert();
        if (isSleep) {
          _triggerSafetyAlert(
            title: 'MATA TERPEJAM!\nISTIRAHAT SEKARANG',
            subtitle: '🚨 PERINGATAN MICROSLEEP',
            reason:
                'Mata terpejam melebihi ${Thresholds.eyeClosedLimit} detik. Segera cari tempat aman untuk berhenti.',
            resetYawnsOnDismiss: false,
          );
        } else {
          _triggerSafetyAlert(
            title: 'TERLALU SERING\nMENGUAP!',
            subtitle: '⚠️ INDIKASI KELELAHAN BERAT',
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

    // Hitung driving score (0-100)
    int score = 100;
    score -= (finalDrowsy * 5).clamp(0, 40);
    score -= (finalYawn * 2).clamp(0, 20);
    score -= (finalMicro * 10).clamp(0, 40);
    score = score.clamp(0, 100);

    // Simpan sesi ke Supabase jika login
    if (AuthService.isLoggedIn && _currentSessionId != null) {
      try {
        await SessionService.endSession(
          sessionId: _currentSessionId!,
          durationSeconds: finalDuration,
          avgSpeedKmh: 0,
          maxSpeedKmh: 0,
          distanceKm: 0,
          drivingScore: score,
          avgBlinkRate: avgBlink,
          totalYawns: finalYawn,
          totalDrowsyEvents: finalDrowsy,
          totalMicrosleeps: finalMicro,
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
    await WakelockPlus.disable();

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

    // Dialog konfirmasi kartu berkendara
    if (mounted && finalDuration > 5) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      final wantCard = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1F2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.directions_car_rounded,
                  color: Color(0xFFFF6D00), size: 28),
              SizedBox(width: 10),
              Text('Sesi Selesai! 🎉',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Durasi: ${_formatDuration(finalDuration)}',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 6),
              Text(
                'Skor berkendaramu: $score / 100',
                style: TextStyle(
                  color: score >= 80
                      ? AppColors.success
                      : (score >= 50 ? AppColors.warning : AppColors.danger),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Mau lihat kartu pencapaian berkendaramu?',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Nanti saja',
                  style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6D00),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Lihat Kartu! 🏆',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

      if (wantCard == true && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DrivingCardScreen(
              durationSeconds: finalDuration,
              drivingScore: score,
              totalMicrosleeps: finalMicro,
              totalDrowsy: finalDrowsy,
              totalYawns: finalYawn,
              startedAt: sessionStart,
            ),
          ),
        );
      }
    }
  }

  void _togglePauseResume() {
    if (_drivingTimer?.isActive ?? false) {
      _pauseTimer();
      setState(() => _cameraMode = 'Dijeda');
    } else {
      _resumeTimer();
      setState(() => _cameraMode = 'ML Kit Aktif');
    }
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
    if (_isAlertShowing) return;
    _isAlertShowing = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => MicrosleepAlertDialog(
        title: title,
        subtitle: subtitle,
        reason: reason,
        onDismiss: () async {
          await _alert.stop();
          if (resetYawnsOnDismiss) {
            _detector.resetYawns();
          }
        },
        onRestArea: () async {
          await _alert.stop();
          if (resetYawnsOnDismiss) {
            _detector.resetYawns();
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Mengarahkan ke rest area terdekat...'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),
    ).whenComplete(() {
      _alert.stop();
      Future.delayed(const Duration(seconds: _alertCooldownSeconds), () {
        if (mounted) setState(() => _isAlertShowing = false);
      });
    });
  }

  Color _statusColor(DriverStatus s) {
    switch (s) {
      case DriverStatus.awake:  return AppColors.success;
      case DriverStatus.yawn:   return AppColors.warning;
      case DriverStatus.drowsy: return AppColors.danger;
      case DriverStatus.sleep:  return Colors.red.shade900;
      case DriverStatus.noFace: return AppColors.textSecondary;
    }
  }

  double _awarenessLevel(DriverStatus s) {
    switch (s) {
      case DriverStatus.awake:  return 0.99;
      case DriverStatus.yawn:   return 0.70;
      case DriverStatus.drowsy: return 0.40;
      case DriverStatus.sleep:  return 0.05;
      case DriverStatus.noFace: return 0.0;
    }
  }

  int _fatigueScore(DriverStatus s) {
    switch (s) {
      case DriverStatus.sleep:  return 95;
      case DriverStatus.drowsy: return 60;
      case DriverStatus.yawn:   return 35;
      default:                  return 5;
    }
  }

  String _fatigueLabel(DriverStatus s) {
    switch (s) {
      case DriverStatus.sleep:  return 'Kritis';
      case DriverStatus.drowsy: return 'Lelah';
      case DriverStatus.yawn:   return 'Mengantuk';
      default:                  return 'Segar';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _isMonitoring ? _statusColor(_result.status) : AppColors.textSecondary;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              const DrivingBuddyAppBar(),
              _buildCameraSection(),
              const SizedBox(height: 12),
              if (!_isMonitoring)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _startMonitoring,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                        shadowColor: AppColors.primary.withOpacity(0.35),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 24),
                      label: const Text(
                        'Mulai Sesi Monitoring',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                )
              else
                _buildActionButtons(),
              _buildConditionStatus(statusColor),
              _buildMetricsGrid(),
              const SizedBox(height: 10),
              if (_isMonitoring) _buildInfoBanner(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      height: 200,
      decoration: BoxDecoration(
        color: AppColors.cameraBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Stack(
        children: [
          if (_cameraController != null && _cameraController!.value.isInitialized)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _cameraController!.value.previewSize?.height ?? 640,
                    height: _cameraController!.value.previewSize?.width ?? 480,
                    child: CameraPreview(_cameraController!),
                  ),
                ),
              ),
            )
          else
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isMonitoring
                        ? Icons.videocam_rounded
                        : Icons.videocam_off_rounded,
                    size: 48,
                    color: Colors.white.withOpacity(_isMonitoring ? 0.3 : 0.15),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isMonitoring
                        ? 'Memuat Kamera...'
                        : 'Pratinjau Kamera Langsung',
                    style: TextStyle(
                      color: Colors.white.withOpacity(_isMonitoring ? 0.35 : 0.2),
                      fontSize: 13,
                    ),
                  ),
                  if (!_isMonitoring) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Tekan "Mulai Sesi" untuk mengaktifkan',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.15),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          // Top-left label
          Positioned(
            top: 12,
            left: 12,
            child: Row(
              children: [
                Icon(Icons.memory_rounded,
                    color: Colors.white.withOpacity(0.6), size: 14),
                const SizedBox(width: 4),
                Text(
                  _isMonitoring ? 'ML Kit Face Mesh • Aktif' : 'ML Kit Face Mesh • Standby',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Top-right mode badge
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (_isMonitoring
                            ? AppColors.success
                            : AppColors.textSecondary)
                        .withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _cameraMode,
                style: TextStyle(
                  color: _isMonitoring
                      ? AppColors.success
                      : Colors.white.withOpacity(0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (_isMonitoring)
            Positioned(
              top: 14,
              left: 0,
              right: 0,
              child: Center(child: _RecordingDot()),
            ),
          // Bottom face detection badge
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _eyeDetected
                      ? AppColors.success.withOpacity(0.15)
                      : Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _eyeDetected
                        ? AppColors.success.withOpacity(0.4)
                        : Colors.white.withOpacity(0.1),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _eyeDetected ? Icons.face_rounded : Icons.face_retouching_off_rounded,
                      color: _eyeDetected
                          ? AppColors.success
                          : Colors.white.withOpacity(0.3),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _eyeDetected ? 'WAJAH TERDETEKSI' : 'MENUNGGU DETEKSI',
                      style: TextStyle(
                        color: _eyeDetected
                            ? AppColors.success
                            : Colors.white.withOpacity(0.3),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
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

  Widget _buildConditionStatus(Color statusColor) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              const Text(
                'KONDISI PENGEMUDI',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _isMonitoring ? _result.status.name.toUpperCase() : 'MENUNGGU',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: statusColor,
              letterSpacing: 1,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            _isMonitoring
                ? _result.subStatus
                : 'Tekan tombol di bawah untuk memulai sesi monitoring.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _isMonitoring ? AppColors.primaryLight : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.shield_rounded,
                  color: _isMonitoring ? AppColors.primary : AppColors.textSecondary,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'Tingkat Kewaspadaan: ${(_awarenessLevel(_result.status) * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _isMonitoring ? AppColors.primaryDark : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.count(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.5,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _MetricCard(
            label: 'WAKTU KEMUDI',
            value: _formatDuration(_elapsedSeconds),
            subtitle: _isMonitoring
                ? ((_drivingTimer?.isActive ?? false) ? 'Berjalan...' : 'Dijeda')
                : 'Belum mulai',
            icon: Icons.timer_outlined,
            iconColor: AppColors.primary,
            dimmed: !_isMonitoring,
          ),
          _MetricCard(
            label: 'EAR MATA',
            value: _isMonitoring ? _result.ear.toStringAsFixed(2) : '0.00',
            subtitle: 'Ambang tutup: < ${Thresholds.earClosed}',
            icon: Icons.remove_red_eye_outlined,
            iconColor: Colors.blue,
            dimmed: !_isMonitoring,
          ),
          _MetricCard(
            label: 'FREKUENSI KEDIP',
            value: '${_result.blinkCount}',
            subtitle: _isMonitoring ? '/mnt  (limit: ${Thresholds.highBlinkRate})' : '—',
            icon: Icons.visibility_rounded,
            iconColor: AppColors.accent,
            dimmed: !_isMonitoring,
          ),
          _MetricCard(
            label: 'SKOR KELELAHAN',
            value: '${_fatigueScore(_result.status)}%',
            subtitle: _isMonitoring ? _fatigueLabel(_result.status) : '—',
            icon: Icons.battery_charging_full_rounded,
            iconColor: AppColors.success,
            dimmed: !_isMonitoring,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.memory_rounded,
              color: AppColors.primary.withOpacity(0.7), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '🤖 ML Kit Face Mesh Aktif (On-Device)\n'
              'Menguap ${_result.yawnCount}x · Kedip ${_result.blinkCount}/mnt · MAR ${_result.mar.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Mencari Rest Area terdekat...'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.local_parking_rounded, size: 18),
              label: const Text('Cari Rest Area Terdekat (4.2 km)'),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: _togglePauseResume,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 14),
                  ),
                  icon: Icon(
                    (_drivingTimer?.isActive ?? false)
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 18,
                  ),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      (_drivingTimer?.isActive ?? false) ? 'Jeda' : 'Lanjut',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        title: const Text('Selesai Perjalanan?'),
                        content: Text(
                          'Durasi: ${_formatDuration(_elapsedSeconds)}\nSesi monitoring akan dihentikan.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Batal'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _stopMonitoring();
                            },
                            child: const Text('Ya, Selesai'),
                          ),
                        ],
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 14),
                  ),
                  icon: const Icon(Icons.stop_rounded, size: 20),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Selesai Perjalanan',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- Recording Dot (animasi titik merah berkedip) ----
class _RecordingDot extends StatefulWidget {
  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: AppColors.danger,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.danger.withOpacity(0.5),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Metric Card Widget ----
class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final bool dimmed;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Opacity(
        opacity: dimmed ? 0.5 : 1.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: iconColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// LAYAR 2b — PERINGATAN KRITIS (Alert Microsleep) — Full-screen Dialog
// ============================================================================

class MicrosleepAlertDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final String reason;
  final VoidCallback? onDismiss;
  final VoidCallback? onRestArea;

  const MicrosleepAlertDialog({
    super.key,
    this.title = 'ISTIRAHAT\nSEKARANG',
    this.subtitle = '⚡ SISTEM KESELAMATAN AKTIF',
    this.reason = 'Microsleep terdeteksi. Segera cari tempat aman untuk berhenti.',
    this.onDismiss,
    this.onRestArea,
  });

  @override
  State<MicrosleepAlertDialog> createState() => _MicrosleepAlertDialogState();
}

class _MicrosleepAlertDialogState extends State<MicrosleepAlertDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  AlertImageMode _imageMode = AlertImageMode.defaultMeme;
  String? _customImagePath;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
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
              Color(0xFFFFF3E0),
              Color(0xFFFFE0B2),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 20),
                _buildAlertHeader(),
                const SizedBox(height: 30),
                _buildWarningSection(),
                const SizedBox(height: 24),
                _buildRecommendationCard(),
                const SizedBox(height: 32),
                _buildAlertActions(),
                const SizedBox(height: 16),
                Text(
                  'Alarm audio keselamatan aktif • Ketuk tombol saat aman',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlertHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 2),
            ),
            child: const CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primaryLight,
              child: Icon(Icons.remove_red_eye_rounded,
                  color: AppColors.primary, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DrivingBuddy — Peringatan Kritis',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                'Sistem Keselamatan Aktif',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWarningSection() {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _pulseAnimation.value,
              child: child,
            );
          },
          child: Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.35),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Icon(
              Icons.warning_rounded,
              color: Colors.white,
              size: 44,
            ),
          ),
        ),
        if (_imageMode == AlertImageMode.defaultMeme) ...[
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/images/meme_tidur.png',
              width: 200,
              fit: BoxFit.cover,
            ),
          ),
        ] else if (_imageMode == AlertImageMode.custom &&
            _customImagePath != null &&
            File(_customImagePath!).existsSync()) ...[
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              File(_customImagePath!),
              width: 220,
              fit: BoxFit.cover,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            widget.subtitle,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
            height: 1.1,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          widget.reason,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendationCard() {
    final rest = dummyRestArea;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.local_parking_rounded,
                    color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'REKOMENDASI AMAN TERDEKAT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      rest.distance,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                rest.name,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: rest.facilities.map((f) {
              IconData icon;
              switch (f) {
                case 'SPBU':
                  icon = Icons.local_gas_station_rounded;
                  break;
                case 'Kopi':
                  icon = Icons.local_cafe_rounded;
                  break;
                case 'Istirahat':
                  icon = Icons.hotel_rounded;
                  break;
                default:
                  icon = Icons.place_rounded;
              }
              return Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.chipBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: AppColors.primaryDark),
                    const SizedBox(width: 4),
                    Text(
                      f,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
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
          child: ElevatedButton.icon(
            onPressed: () {
              widget.onDismiss?.call();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
            label: const Text(
              'SAYA SUDAH AWAS (HENTIKAN ALARM)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              widget.onRestArea?.call();
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.navigation_rounded, size: 20),
            label: const Text(
              'ARAHKAN KE REST AREA TERDEKAT',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// LAYAR 3 — RIWAYAT (Trip Logs)
// ============================================================================

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;
  String? _userName;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final sessions = await SessionService.getUserSessions();
      final name = await AuthService.getUserName();
      if (mounted) {
        setState(() {
          _sessions = sessions;
          _userName = name;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error load history: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDuration(int seconds) {
    if (seconds == 0) return '0 mnt';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}j ${m}m';
    return '${m}m';
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '-';
    final dt = DateTime.tryParse(isoDate)?.toLocal();
    if (dt == null) return '-';
    final now = DateTime.now();
    final diff = now.difference(dt).inDays;
    if (diff == 0) return 'Hari ini';
    if (diff == 1) return 'Kemarin';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Color _scoreColor(int score) {
    if (score >= 80) return AppColors.success;
    if (score >= 50) return AppColors.warning;
    return AppColors.danger;
  }

  // Hitung total waktu semua sesi dalam detik
  int get _totalSeconds => _sessions.fold(0, (sum, s) => sum + ((s['duration_seconds'] as num?)?.toInt() ?? 0));

  // Rata-rata skor semua sesi
  int get _avgScore {
    if (_sessions.isEmpty) return 100;
    final total = _sessions.fold(0, (sum, s) => sum + ((s['driving_score'] as num?)?.toInt() ?? 100));
    return (total / _sessions.length).round();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: AppColors.primary,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: const DrivingBuddyAppBar(),
              ),

              // Summary card
              SliverToBoxAdapter(child: _buildSummaryCard()),

              // List header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Riwayat Perjalanan (${_sessions.length})',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded,
                            color: AppColors.primary, size: 20),
                        onPressed: _loadData,
                        tooltip: 'Refresh',
                      ),
                    ],
                  ),
                ),
              ),

              // Loading / empty / list
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              else if (_sessions.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.directions_car_outlined,
                            size: 64, color: AppColors.textSecondary.withOpacity(0.3)),
                        const SizedBox(height: 16),
                        const Text(
                          'Belum ada sesi perjalanan',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Mulai sesi monitoring untuk\nmenyimpan data perjalananmu',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.builder(
                    itemCount: _sessions.length,
                    itemBuilder: (context, index) {
                      final s = _sessions[index];
                      return _buildSessionCard(s);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📊  Ringkasan Semua Sesi',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const Spacer(),
              if (_userName != null)
                Text('👤 $_userName',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _SummaryStatItem(
                value: '${_sessions.length}',
                label: 'Sesi Total',
              ),
              Container(width: 1, height: 40, color: Colors.grey.shade200),
              _SummaryStatItem(
                value: _formatDuration(_totalSeconds),
                label: 'Total Waktu',
              ),
              Container(width: 1, height: 40, color: Colors.grey.shade200),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$_avgScore',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: _scoreColor(_avgScore),
                      ),
                    ),
                    const Text('Rata-rata Skor',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> session) {
    final score = (session['driving_score'] as num?)?.toInt() ?? 100;
    final duration = (session['duration_seconds'] as num?)?.toInt() ?? 0;
    final drowsy = (session['total_drowsy_events'] as num?)?.toInt() ?? 0;
    final yawn = (session['total_yawns'] as num?)?.toInt() ?? 0;
    final micro = (session['total_microsleeps'] as num?)?.toInt() ?? 0;
    final date = _formatDate(session['started_at'] as String?);
    final startedAt = session['started_at'] as String?;
    String timeStr = '-';
    if (startedAt != null) {
      final dt = DateTime.tryParse(startedAt)?.toLocal();
      if (dt != null) {
        timeStr =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    }

    final scoreColor = _scoreColor(score);
    final totalEvents = drowsy + yawn + micro;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scoreColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Skor $score',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scoreColor,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '$date  $timeStr',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MiniStat(
                  icon: Icons.timer_outlined,
                  value: _formatDuration(duration),
                  label: 'Durasi'),
              const SizedBox(width: 16),
              _MiniStat(
                  icon: Icons.warning_amber_rounded,
                  value: '$totalEvents',
                  label: 'Event',
                  color: totalEvents > 0 ? AppColors.warning : AppColors.success),
              const SizedBox(width: 16),
              _MiniStat(
                  icon: Icons.bedtime_outlined,
                  value: '$micro',
                  label: 'Microsleep',
                  color: micro > 0 ? AppColors.danger : AppColors.success),
            ],
          ),
          if (totalEvents > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 14, color: AppColors.danger),
                  const SizedBox(width: 6),
                  Text(
                    '${drowsy}x kantuk · ${yawn}x menguap · ${micro}x microsleep',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.danger),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DrivingCardScreen(
                      durationSeconds: duration,
                      drivingScore: score,
                      totalMicrosleeps: micro,
                      totalDrowsy: drowsy,
                      totalYawns: yawn,
                      startedAt: session['started_at'] != null
                          ? DateTime.tryParse(session['started_at'] as String)
                          : null,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.workspace_premium_rounded,
                  size: 16, color: Color(0xFFFF6D00)),
              label: const Text(
                'Lihat Kartu Berkendara',
                style: TextStyle(
                    color: Color(0xFFFF6D00),
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFFF6D00), width: 1),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
    this.color = AppColors.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color)),
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary)),
          ],
        ),
      ],
    );
  }
}



// ---- Summary Stat Item ----

class _SummaryStatItem extends StatelessWidget {
  final String value;
  final String label;

  const _SummaryStatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ---- Trip Card ----
class _TripCard extends StatelessWidget {
  final TripRecord trip;

  const _TripCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.routeName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${trip.dateInfo} · ${trip.timeRange}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trip.duration,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: trip.warningColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: trip.warningColor.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      trip.warningColor == AppColors.success
                          ? Icons.check_circle_rounded
                          : Icons.warning_amber_rounded,
                      size: 12,
                      color: trip.warningColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      trip.warningLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: trip.warningColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  trip.driverStatus,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _EarGraphPlaceholder(data: trip.earGraphData),
          const SizedBox(height: 14),
          Row(
            children: [
              _TripStatChip(
                label: 'Rata-rata EAR',
                value: trip.avgEAR.toStringAsFixed(2),
                icon: Icons.remove_red_eye_outlined,
              ),
              const Spacer(),
              _TripStatChip(
                label: 'Kecepatan',
                value: '${trip.avgSpeed}',
                unit: 'km/j',
                icon: Icons.speed_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {},
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Lihat Detail Sesi',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 12, color: AppColors.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Trip Stat Chip ----
class _TripStatChip extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final IconData icon;

  const _TripStatChip({
    required this.label,
    required this.value,
    this.unit,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary)),
            Row(
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 3),
                  Text(unit!,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ],
        ),
      ],
    );
  }
}

// ---- EAR Graph (CustomPainter) ----
class _EarGraphPlaceholder extends StatelessWidget {
  final List<double> data;

  const _EarGraphPlaceholder({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CustomPaint(painter: _EarLinePainter(data: data)),
      ),
    );
  }
}

class _EarLinePainter extends CustomPainter {
  final List<double> data;

  _EarLinePainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final double minVal = data.reduce(min) - 0.05;
    final double maxVal = data.reduce(max) + 0.05;
    final double range = maxVal - minVal;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.primary.withOpacity(0.20),
          AppColors.primary.withOpacity(0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final linePaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height - ((data[i] - minVal) / range) * size.height;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        final prevX = ((i - 1) / (data.length - 1)) * size.width;
        final prevY =
            size.height - ((data[i - 1] - minVal) / range) * size.height;
        final cpX1 = prevX + (x - prevX) / 2;
        final cpX2 = prevX + (x - prevX) / 2;
        path.cubicTo(cpX1, prevY, cpX2, y, x, y);
        fillPath.cubicTo(cpX1, prevY, cpX2, y, x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // Threshold dashed line (EAR = 0.25)
    final thresholdY =
        size.height - ((0.25 - minVal) / range) * size.height;
    final thresholdPaint = Paint()
      ..color = AppColors.danger.withOpacity(0.25)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const dashWidth = 4.0;
    const dashSpace = 4.0;
    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, thresholdY.clamp(0, size.height)),
        Offset((startX + dashWidth).clamp(0, size.width),
            thresholdY.clamp(0, size.height)),
        thresholdPaint,
      );
      startX += dashWidth + dashSpace;
    }

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    // Dots
    final dotPaint = Paint()..color = AppColors.primary;
    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height - ((data[i] - minVal) / range) * size.height;
      canvas.drawCircle(Offset(x, y), 3, dotPaint);
      canvas.drawCircle(
        Offset(x, y),
        3,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ============================================================================
// SETTINGS SCREEN — Konfigurasi IP Server
// ============================================================================

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isSaving = false;
  bool _isLoggedIn = false;

  // --- Alert Settings State ---
  AlertAudioType _selectedAudioType = AlertAudioType.defaultSiren;
  String _audioDisplayName = 'Sirene Darurat (Bawaan)';
  String? _customAudioPath;
  final AudioPlayer _previewPlayer = AudioPlayer();
  bool _isPlayingPreview = false;

  AlertImageMode _selectedImageMode = AlertImageMode.defaultMeme;
  String? _customImagePath;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadAlertSettings();
  }

  Future<void> _loadAlertSettings() async {
    final audioType = await AlertConfig.getAudioType();
    final audioName = await AlertConfig.getAudioDisplayName();
    final customAudio = await AlertConfig.getCustomAudioPath();
    final imageMode = await AlertConfig.getImageMode();
    final customImage = await AlertConfig.getCustomImagePath();
    if (mounted) {
      setState(() {
        _selectedAudioType = audioType;
        _audioDisplayName = audioName;
        _customAudioPath = customAudio;
        _selectedImageMode = imageMode;
        _customImagePath = customImage;
      });
    }
  }

  Future<void> _togglePreviewAudio() async {
    if (_isPlayingPreview) {
      await _previewPlayer.stop();
      if (mounted) setState(() => _isPlayingPreview = false);
      return;
    }

    setState(() => _isPlayingPreview = true);
    try {
      if (_selectedAudioType == AlertAudioType.customFile &&
          _customAudioPath != null &&
          File(_customAudioPath!).existsSync()) {
        await _previewPlayer.play(DeviceFileSource(_customAudioPath!));
      } else if (_selectedAudioType == AlertAudioType.loudBeep) {
        await _previewPlayer.play(AssetSource('sounds/beep.wav'));
      } else if (_selectedAudioType == AlertAudioType.buzzer) {
        await _previewPlayer.play(AssetSource('sounds/buzzer.wav'));
      } else {
        await _previewPlayer.play(AssetSource('sounds/alarm.mp3'));
      }

      // Otomatis stop setelah 4 detik
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && _isPlayingPreview) {
          _previewPlayer.stop();
          setState(() => _isPlayingPreview = false);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _isPlayingPreview = false);
    }
  }

  Future<void> _selectAudioPreset(AlertAudioType type) async {
    if (_isPlayingPreview) await _previewPlayer.stop();
    await AlertConfig.setAudioPreset(type);
    await _loadAlertSettings();
  }

  Future<void> _pickCustomAudio() async {
    final controller = TextEditingController(text: _customAudioPath ?? '');
    List<File> foundAudios = [];
    try {
      final dirs = [
        Directory('/storage/emulated/0/Download'),
        Directory('/storage/emulated/0/Music'),
        Directory('/storage/emulated/0/Ringtones'),
        Directory('/sdcard/Download'),
      ];
      for (final dir in dirs) {
        if (dir.existsSync()) {
          final list = dir.listSync();
          for (final item in list) {
            if (item is File) {
              final ext = item.path.split('.').last.toLowerCase();
              if (['mp3', 'wav', 'm4a', 'aac', 'ogg'].contains(ext)) {
                foundAudios.add(item);
              }
            }
          }
        }
      }
    } catch (_) {}

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.audiotrack_rounded, color: AppColors.primary),
                const SizedBox(width: 10),
                const Text(
                  'Pilih Audio Kustom dari HP',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (foundAudios.isNotEmpty) ...[
              const Text(
                'File Audio Ditemukan di Folder HP:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: foundAudios.length,
                  itemBuilder: (_, idx) {
                    final f = foundAudios[idx];
                    final fname = f.path.split(Platform.pathSeparator).last;
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.music_note_rounded,
                          color: AppColors.primary, size: 20),
                      title: Text(fname,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      onTap: () async {
                        Navigator.pop(ctx);
                        if (_isPlayingPreview) await _previewPlayer.stop();
                        await AlertConfig.setCustomAudio(f.path, fname);
                        await _loadAlertSettings();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text('✅ Suara alarm berhasil diganti: $fname'),
                              backgroundColor: AppColors.success,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Text(
              'Atau Masukkan Path File Audio:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: '/storage/emulated/0/Download/alarm.mp3',
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final text = controller.text.trim();
                  if (text.isNotEmpty) {
                    final f = File(text);
                    if (f.existsSync()) {
                      Navigator.pop(ctx);
                      if (_isPlayingPreview) await _previewPlayer.stop();
                      final fname = text.split(Platform.pathSeparator).last;
                      await AlertConfig.setCustomAudio(text, fname);
                      await _loadAlertSettings();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content:
                                Text('✅ Suara alarm berhasil diganti: $fname'),
                            backgroundColor: AppColors.success,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'File tidak ditemukan di path tersebut. Pastikan path benar.'),
                          backgroundColor: AppColors.danger,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Terapkan File Audio'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        await AlertConfig.setImageMode(AlertImageMode.custom,
            customPath: picked.path);
        await _loadAlertSettings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Gambar alert berhasil diperbarui'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memilih gambar: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _removeAlertImage() async {
    await AlertConfig.removeCustomImage();
    await _loadAlertSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gambar alert dihapus (Mode Hanya Teks & Ikon)'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _restoreDefaultMeme() async {
    await AlertConfig.setImageMode(AlertImageMode.defaultMeme);
    await _loadAlertSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Meme tidur bawaan diaktifkan kembali'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _loadProfile() async {
    if (AuthService.isLoggedIn) {
      final user = AuthService.currentUser;
      final name = AuthService.currentUserName ?? '';
      final email = user?.email ?? '';
      if (mounted) {
        setState(() {
          _nameController.text = name;
          _emailController.text = email;
          _isLoggedIn = true;
        });
      }
    } else {
      final profile = await AccountConfig.getProfile();
      if (mounted) {
        setState(() {
          _nameController.text = profile['name'] ?? '';
          _emailController.text = profile['email'] ?? '';
          _isLoggedIn =
              _nameController.text.isNotEmpty || _emailController.text.isNotEmpty;
        });
      }
    }
  }

  @override
  void dispose() {
    _previewPlayer.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    setState(() => _isSaving = true);
    await AccountConfig.saveProfile(name, email);
    setState(() {
      _isSaving = false;
      _isLoggedIn = name.isNotEmpty || email.isNotEmpty;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Profil tersimpan'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _signOut() async {
    if (AuthService.isLoggedIn) {
      await AuthService.logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } else {
      await AccountConfig.clearProfile();
      _nameController.clear();
      _emailController.clear();
      setState(() => _isLoggedIn = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Berhasil keluar'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Akun & Pengaturan',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.accent],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _nameController.text.isNotEmpty
                          ? _nameController.text[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _isLoggedIn
                      ? (_nameController.text.isNotEmpty
                          ? _nameController.text
                          : 'Pengemudi')
                      : 'Tamu / Offline',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isLoggedIn
                        ? AppColors.success.withOpacity(0.1)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _isLoggedIn ? '● Supabase Terhubung' : '○ Mode Tamu (Offline)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _isLoggedIn
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.psychology_rounded,
                    color: AppColors.accent, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'DrivingBuddy berjalan sepenuhnya On-Device (Google ML Kit Face Mesh). '
                    'Deteksi wajah & kantuk tidak butuh internet.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.85),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Nama Pengemudi',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _nameController,
            hint: 'Masukkan nama kamu',
            icon: Icons.person_rounded,
          ),
          const SizedBox(height: 16),
          const Text(
            'Email',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _emailController,
            hint: 'email@contoh.com',
            icon: Icons.email_rounded,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveProfile,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(_isSaving ? 'Menyimpan...' : 'Simpan Profil'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 20),
          _buildAlertSettingsSection(),
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 20),
          const Text(
            'Informasi Sistem',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.memory_rounded, 'AI Engine',
              'Google ML Kit Face Mesh 468 (On-Device Offline)'),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.cloud_done_rounded, 'Database Cloud',
              'Supabase PostgreSQL (Sinkronisasi Riwayat)'),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.security_rounded, 'Privasi',
              'Kamera diproses lokal 100%, frame video tidak dikirim'),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.info_outline_rounded, 'Versi',
              'DrivingBuddy v1.0.0 — Capstone UIUX'),
          const SizedBox(height: 24),
          if (_isLoggedIn) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout_rounded,
                    size: 18, color: AppColors.danger),
                label: const Text(
                  'Keluar dari Akun',
                  style: TextStyle(color: AppColors.danger),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.danger),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: Colors.grey.shade400,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Icon(icon, color: AppColors.primary),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Kustomisasi Peringatan (Alert & Alarm)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Atur nada suara alarm dan gambar yang ditampilkan saat bahaya',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),

        // ── 1. SUARA ALARM CARD ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.volume_up_rounded,
                        color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Suara Alarm Keselamatan',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Diputar saat kantuk atau microsleep terdeteksi',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildAudioOptionTile(
                title: 'Sirene Darurat (Bawaan)',
                subtitle: 'Suara sirene alarm standar',
                isSelected: _selectedAudioType == AlertAudioType.defaultSiren,
                onTap: () => _selectAudioPreset(AlertAudioType.defaultSiren),
              ),
              const SizedBox(height: 6),
              _buildAudioOptionTile(
                title: 'Beep Peringatan Cepat',
                subtitle: 'Nada beep berulang frekuensi tinggi (1050 Hz)',
                isSelected: _selectedAudioType == AlertAudioType.loudBeep,
                onTap: () => _selectAudioPreset(AlertAudioType.loudBeep),
              ),
              const SizedBox(height: 6),
              _buildAudioOptionTile(
                title: 'Klakson / Buzzer Peringatan',
                subtitle: 'Suara buzzer ganda kendaraan darurat',
                isSelected: _selectedAudioType == AlertAudioType.buzzer,
                onTap: () => _selectAudioPreset(AlertAudioType.buzzer),
              ),
              const SizedBox(height: 6),
              _buildAudioOptionTile(
                title: _selectedAudioType == AlertAudioType.customFile
                    ? 'File Kustom: $_audioDisplayName'
                    : 'Pilih Audio dari File HP...',
                subtitle: _selectedAudioType == AlertAudioType.customFile
                    ? 'Audio kustom tersimpan dari memori HP'
                    : 'Cari atau masukkan path file audio MP3/WAV',
                isSelected: _selectedAudioType == AlertAudioType.customFile,
                onTap: _pickCustomAudio,
                trailingIcon: Icons.folder_open_rounded,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _togglePreviewAudio,
                      icon: Icon(
                        _isPlayingPreview
                            ? Icons.stop_circle_rounded
                            : Icons.play_circle_fill_rounded,
                        size: 18,
                        color: _isPlayingPreview
                            ? AppColors.danger
                            : AppColors.primary,
                      ),
                      label: Text(
                        _isPlayingPreview ? 'Hentikan Contoh' : 'Tes Bunyi Alarm',
                        style: TextStyle(
                          color: _isPlayingPreview
                              ? AppColors.danger
                              : AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: _isPlayingPreview
                              ? AppColors.danger
                              : AppColors.primary,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  if (_selectedAudioType == AlertAudioType.customFile) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Kembalikan ke suara bawaan',
                      onPressed: () =>
                          _selectAudioPreset(AlertAudioType.defaultSiren),
                      icon: const Icon(Icons.refresh_rounded,
                          color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── 2. GAMBAR ALERT CARD ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.image_rounded,
                        color: AppColors.accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gambar Peringatan Visual',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Gambar di layar modal saat alarm berbunyi',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Image Preview Area
              Center(
                child: Container(
                  height: 130,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildImagePreviewWidget(),
                ),
              ),

              const SizedBox(height: 14),

              // Action buttons for Image
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _pickCustomImage,
                      icon: const Icon(Icons.photo_library_rounded, size: 16),
                      label: const Text(
                        'Ganti Gambar',
                        style:
                            TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        backgroundColor: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_selectedImageMode != AlertImageMode.defaultMeme) ...[
                    OutlinedButton.icon(
                      onPressed: _restoreDefaultMeme,
                      icon: const Icon(Icons.restore_rounded, size: 16),
                      label:
                          const Text('Meme Bawaan', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 11),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (_selectedImageMode != AlertImageMode.none) ...[
                    OutlinedButton.icon(
                      onPressed: _removeAlertImage,
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 16, color: AppColors.danger),
                      label: const Text('Hapus',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.danger)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.danger),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 11),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImagePreviewWidget() {
    if (_selectedImageMode == AlertImageMode.none) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.hide_image_rounded, size: 36, color: Color(0xFF9CA3AF)),
          SizedBox(height: 6),
          Text(
            'Gambar Peringatan Dinonaktifkan',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
          Text(
            'Hanya menampilkan teks peringatan & tombol istirahat',
            style: TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
          ),
        ],
      );
    } else if (_selectedImageMode == AlertImageMode.custom &&
        _customImagePath != null &&
        File(_customImagePath!).existsSync()) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(_customImagePath!), fit: BoxFit.cover),
          Positioned(
            bottom: 6,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Gambar Kustom Aktif',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      );
    } else {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/meme_tidur.png', fit: BoxFit.cover),
          Positioned(
            bottom: 6,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Meme Tidur Bawaan',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildAudioOptionTile({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
    IconData? trailingIcon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withOpacity(0.4)
                : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? AppColors.primary : const Color(0xFF9CA3AF),
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected
                          ? AppColors.primaryDark
                          : AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 8),
              Icon(trailingIcon, size: 18, color: AppColors.primary),
            ],
          ],
        ),
      ),
    );
  }
}