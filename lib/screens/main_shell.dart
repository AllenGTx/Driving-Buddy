import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../features/nearby_places/nearby_places.dart';
import '../services/theme_service.dart';
import 'home_screen.dart';
import 'monitor_screen.dart';
import 'history_screen.dart';
import '../models/account_config.dart';
import '../services/firebase_service.dart';

// ============================================================================
// MAIN SHELL — Luxury GT Navigation Bar
// ============================================================================

class MainShell extends StatefulWidget {
  final int initialIndex;

  const MainShell({super.key, this.initialIndex = 0});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _currentIndex;
  final GlobalKey<MonitorScreenState> _monitorKey = GlobalKey();
  final NearbyPlacesController _nearbyController = NearbyPlacesController();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    // Otomatis aktifkan pencarian tempat terdekat saat aplikasi dibuka.
    _nearbyController.start(askPermission: false);
    // Muat foto profil awal agar tersinkron di semua tab spesifik user aktif
    final curEmail = AuthService.currentUser?.email;
    AccountConfig.getPhotoUrl(userEmail: curEmail);
    // Auto-sync sesi offline ke Firestore jika internet aktif
    SessionService.syncPendingOfflineSessions();
  }

  @override
  void dispose() {
    _nearbyController.dispose();
    super.dispose();
  }

  void _switchToTab(int index) {
    if (_currentIndex == 1 && index != 1 && _monitorKey.currentState?.isMonitoring == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Selesaikan perjalanan terlebih dahulu sebelum berpindah halaman/pengaturan.'),
          backgroundColor: Color(0xFFE57A38),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final isDark = ThemeService.instance.isDarkMode;

        return Scaffold(
          backgroundColor: AppColors.dynamicBackground,
          body: IndexedStack(
            index: _currentIndex,
            children: [
              CockpitScreen(
                isActive: _currentIndex == 0,
                onStartMonitoring: () {
                  _switchToTab(1);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _monitorKey.currentState?.startFromExternal();
                  });
                },
                nearbyController: _nearbyController,
              ),
              MonitorScreen(
                key: _monitorKey,
                isActive: _currentIndex == 1,
                nearbyController: _nearbyController,
              ),
              const HistoryScreen(),
            ],
          ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: AppColors.dynamicSurface.withValues(alpha: 0.97),
              border: Border(
                top: BorderSide(
                  color: AppColors.dynamicCardBorder.withValues(alpha: 0.8),
                  width: 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.35)
                      : const Color(0xFFE57A38).withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 72,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _NavItem(
                      icon: Icons.dashboard_rounded,
                      label: 'Beranda',
                      isSelected: _currentIndex == 0,
                      onTap: () => _switchToTab(0),
                    ),
                    // Center Floating Drive / Monitoring Button
                    GestureDetector(
                      onTap: () => _switchToTab(1),
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE57A38), Color(0xFFC25E21)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE57A38).withValues(alpha: 0.45),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(
                          _currentIndex == 1
                              ? Icons.videocam_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                    _NavItem(
                      icon: Icons.analytics_rounded,
                      label: 'Aktivitas',
                      isSelected: _currentIndex == 2,
                      onTap: () => _switchToTab(2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppColors.primary : AppColors.dynamicTextSecondary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: color,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: color,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
