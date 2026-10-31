import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/design_tokens.dart';
import '../widgets/ui/db_ui.dart';
import '../features/nearby_places/nearby_places.dart';
import '../services/theme_service.dart';
import 'home_screen.dart';
import 'monitor_screen.dart';
import 'history_screen.dart';
import '../models/account_config.dart';
import '../services/firebase_service.dart';

// ============================================================================
// MAIN SHELL — Navigasi bawah
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
          content: Text('Selesaikan perjalanan terlebih dahulu sebelum berpindah halaman.'),
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
        final driveActive = _currentIndex == 1;

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
              color: AppColors.dynamicSurface,
              border: Border(top: BorderSide(color: AppColors.dynamicBorderLight)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 68,
                child: Row(
                  children: [
                    Expanded(
                      child: _NavItem(
                        icon: Icons.home_outlined,
                        activeIcon: Icons.home_rounded,
                        label: 'Beranda',
                        isSelected: _currentIndex == 0,
                        onTap: () => _switchToTab(0),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: 'Mode berkendara',
                      child: DbPressable(
                        onTap: () => _switchToTab(1),
                        pressedScale: 0.92,
                        child: AnimatedContainer(
                          duration: DbMotion.of(context, DbMotion.base),
                          curve: DbMotion.out,
                          width: 64,
                          height: 46,
                          decoration: BoxDecoration(
                            color: driveActive
                                ? (isDark ? Colors.white : DbColors.ink)
                                : DbColors.orange,
                            borderRadius: BorderRadius.circular(DbRadius.pill),
                          ),
                          child: Icon(
                            driveActive ? Icons.videocam_rounded : Icons.play_arrow_rounded,
                            color: driveActive && isDark ? DbColors.ink : Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _NavItem(
                        icon: Icons.insights_outlined,
                        activeIcon: Icons.insights_rounded,
                        label: 'Aktivitas',
                        isSelected: _currentIndex == 2,
                        onTap: () => _switchToTab(2),
                      ),
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
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppColors.dynamicTextPrimary : AppColors.dynamicTextMuted;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isSelected ? activeIcon : icon, color: color, size: 24),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          AnimatedContainer(
            duration: DbMotion.of(context, DbMotion.fast),
            width: isSelected ? 4 : 0,
            height: 4,
            decoration: const BoxDecoration(color: DbColors.orange, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}
