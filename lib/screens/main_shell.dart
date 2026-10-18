import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import 'home_screen.dart';
import 'monitor_screen.dart';
import 'history_screen.dart';

// ============================================================================
// MAIN SHELL — 3-Tab BottomNavigationBar (Cockpit / Monitor / Riwayat)
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

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

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
