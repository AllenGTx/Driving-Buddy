import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/design_tokens.dart';
import '../features/nearby_places/nearby_places.dart';
import '../features/spotify_island/spotify_island_controller.dart';
import '../features/spotify_island/ui/dynamic_island_overlay.dart';
import '../features/voice_buddy/ui/buddy_floating_sheet.dart';
import '../features/voice_buddy/voice_buddy_controller.dart';
import '../models/account_config.dart';
import '../routes/app_routes.dart';
import '../services/firebase_service.dart';
import '../services/language_service.dart';
import '../services/theme_service.dart';
import '../widgets/ui/db_ui.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'monitor_screen.dart';

// ============================================================================
// MAIN SHELL — Navigasi bawah + Asisten Suara Siaga Global
// ============================================================================

class MainShell extends StatefulWidget {
  final int initialIndex;

  const MainShell({super.key, this.initialIndex = 0});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  late int _currentIndex;
  final GlobalKey<MonitorScreenState> _monitorKey = GlobalKey();
  final NearbyPlacesController _nearbyController = NearbyPlacesController();
  late final VoiceBuddyController _voiceBuddyController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final curUser = FirebaseAuth.instance.currentUser;
    if (curUser == null || !curUser.emailVerified) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil(
            AppRoutes.welcome,
            (route) => false,
          );
        }
      });
      _currentIndex = widget.initialIndex;
      _voiceBuddyController = VoiceBuddyController(nearby: _nearbyController);
      return;
    }

    _currentIndex = widget.initialIndex;
    // Saat di Beranda sebelum sesi berkendara dimulai, ambil posisi sekali saja (track: false) agar GPS tidak menguras baterai!
    _nearbyController.start(askPermission: false, track: false);
    _voiceBuddyController = VoiceBuddyController(
      nearby: _nearbyController,
      sessionIdProvider: () =>
          AuthService.currentUser?.uid ?? 'local-driver',
    );
    unawaited(_voiceBuddyController.init(insideMainApp: true));

    final curEmail = AuthService.currentUser?.email;
    AccountConfig.getPhotoUrl(userEmail: curEmail);
    SessionService.syncPendingOfflineSessions();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final driving = _monitorKey.currentState?.isMonitoring ?? false;
    _voiceBuddyController.handleAppLifecycle(state, isDriving: driving);
    unawaited(SpotifyIslandController.instance.handleAppLifecycle(state));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voiceBuddyController.dispose();
    _nearbyController.dispose();
    super.dispose();
  }

  void _switchToTab(int index) {
    if (_currentIndex == 1 &&
        index != 1 &&
        _monitorKey.currentState?.isMonitoring == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selesaikan perjalanan terlebih dahulu sebelum berpindah halaman.',
          ),
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
      listenable: Listenable.merge([
        ThemeService.instance,
        LanguageService.instance,
      ]),
      builder: (context, _) {
        final isDark = ThemeService.instance.isDarkMode;
        final s = LanguageService.instance.s;
        final driveActive = _currentIndex == 1;

        return Stack(
          children: [
            Scaffold(
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
                    voiceBuddyController: _voiceBuddyController,
                  ),
                  MonitorScreen(
                    key: _monitorKey,
                    isActive: _currentIndex == 1,
                    nearbyController: _nearbyController,
                    voiceBuddyController: _voiceBuddyController,
                  ),
                  const HistoryScreen(),
                ],
              ),
              bottomNavigationBar: Container(
                decoration: BoxDecoration(
                  color: AppColors.dynamicSurface,
                  border: Border(
                    top: BorderSide(color: AppColors.dynamicBorderLight),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    height: 68,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final totalWidth = constraints.maxWidth;
                        final sideWidth = (totalWidth - 64) / 2;
                        final double targetX;
                        final bool showDot;

                        if (_currentIndex == 0) {
                          targetX = (sideWidth / 2) - 2.5;
                          showDot = true;
                        } else if (_currentIndex == 2) {
                          targetX = sideWidth + 64 + (sideWidth / 2) - 2.5;
                          showDot = true;
                        } else {
                          targetX = (totalWidth / 2) - 2.5;
                          showDot = false;
                        }

                        return Stack(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _NavItem(
                                    icon: Icons.home_outlined,
                                    activeIcon: Icons.home_rounded,
                                    label: s.navHome,
                                    isSelected: _currentIndex == 0,
                                    onTap: () => _switchToTab(0),
                                  ),
                                ),
                                Semantics(
                                  button: true,
                                  label: s.navDriveMode,
                                  child: DbPressable(
                                    onTap: () => _switchToTab(1),
                                    pressedScale: 0.92,
                                    child: AnimatedContainer(
                                      duration: DbMotion.of(
                                        context,
                                        DbMotion.base,
                                      ),
                                      curve: DbMotion.out,
                                      width: 64,
                                      height: 46,
                                      decoration: BoxDecoration(
                                        color: driveActive
                                            ? (isDark
                                                  ? Colors.white
                                                  : DbColors.ink)
                                            : DbColors.orange,
                                        borderRadius: BorderRadius.circular(
                                          DbRadius.pill,
                                        ),
                                      ),
                                      child: Icon(
                                        driveActive
                                            ? Icons.videocam_rounded
                                            : Icons.play_arrow_rounded,
                                        color: driveActive && isDark
                                            ? DbColors.ink
                                            : Colors.white,
                                        size: 26,
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: _NavItem(
                                    icon: Icons.insights_outlined,
                                    activeIcon: Icons.insights_rounded,
                                    label: s.navHistory,
                                    isSelected: _currentIndex == 2,
                                    onTap: () => _switchToTab(2),
                                  ),
                                ),
                              ],
                            ),
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeInOutCubicEmphasized,
                              left: targetX,
                              bottom: 7,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: showDot ? 1.0 : 0.0,
                                child: Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: DbColors.orange,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: DbColors.orange.withValues(
                                          alpha: 0.75,
                                        ),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

            // Dynamic Island Pemutar Musik Spotify (hanya muncul bila diminta via suara)
            const DynamicIslandOverlay(),

            // Overlay Layar Penuh Siri Orb (aktif lintas halaman Beranda & Berkendara)
            BuddyFloatingSheet(controller: _voiceBuddyController),
          ],
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
    final color = isSelected
        ? AppColors.dynamicTextPrimary
        : AppColors.dynamicTextMuted;
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
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
