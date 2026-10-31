import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../services/theme_service.dart';
import '../widgets/ui/db_ui.dart';
import '../routes/app_routes.dart';

// ============================================================================
// WELCOME SCREEN (Organic Wave Header with WelcomeCar.jpg & World-Class Minimal)
// ============================================================================

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final isDark = ThemeService.instance.isDarkMode;
        final screenHeight = MediaQuery.of(context).size.height;
        final topPadding = MediaQuery.of(context).padding.top;
        final waveHeight = screenHeight * 0.67;

        return Scaffold(
          backgroundColor: isDark ? AppColors.darkBackground : const Color(0xFFFFFFFF),
          body: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── TOP ORGANIC WAVE HEADER WITH WELCOMECAR.JPG ────
                  SizedBox(
                    height: waveHeight,
                    width: double.infinity,
                    child: Stack(
                      children: [
                        // Clipped Wave Container
                        Positioned.fill(
                          child: ClipPath(
                            clipper: const _WelcomeWaveClipper(),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // Background Car Image
                                Image.asset(
                                  'assets/images/WelcomeCar.jpg',
                                  fit: BoxFit.cover,
                                  alignment: Alignment.center,
                                ),

                                // Cinematic Brand Gradient Overlay (Orange & Dark Tones)
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: isDark
                                          ? [
                                              Colors.black.withValues(alpha: 0.45),
                                              Colors.black.withValues(alpha: 0.20),
                                              const Color(0xFF9A3412).withValues(alpha: 0.55),
                                              const Color(0xFF0A0F1D).withValues(alpha: 0.95),
                                            ]
                                          : [
                                              const Color(0xFFF26B1D).withValues(alpha: 0.30),
                                              Colors.black.withValues(alpha: 0.15),
                                              const Color(0xFFF26B1D).withValues(alpha: 0.65),
                                              const Color(0xFFEA580C).withValues(alpha: 0.90),
                                            ],
                                      stops: const [0.0, 0.35, 0.72, 1.0],
                                    ),
                                  ),
                                ),

                                // Topographic Vector Contour Lines
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _WelcomeTopographicPainter(isDark: isDark),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Logo at Top-Left (Clean, NO black box/badge)
                        Positioned(
                          top: topPadding + 16,
                          left: 24,
                          child: Image.asset(
                            'assets/images/DrivingBuddyLogo_white_tight.png',
                            height: 36,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── BOTTOM CONTENT CANVAS ─────────────────────────
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Spacer(flex: 1),

                          // Heading
                          Text(
                            'Welcome',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.6,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Brand Orange Accent Dash
                          Container(
                            width: 38,
                            height: 4,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF26B1D),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // App Narrative / Description
                          Text(
                            'Asisten AI cerdas untuk memantau keselamatan & kewaspadaan berkendara Anda di setiap perjalanan.',
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.48,
                              fontWeight: FontWeight.w500,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                          ),

                          const Spacer(flex: 2),

                          // Bottom Continue Action Button (Aligned Right as in mockup)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                'Continue',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(width: 14),
                              DbPressable(
                                onTap: () {
                                  Navigator.of(context).pushReplacementNamed(AppRoutes.login);
                                },
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFFF26B1D), Color(0xFFEA580C)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFF26B1D).withValues(alpha: 0.38),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.arrow_forward_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 28),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// WELCOME WAVE CLIPPER (Deep swoop curve for ~68% header)
// ============================================================================
class _WelcomeWaveClipper extends CustomClipper<Path> {
  const _WelcomeWaveClipper();

  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 40);

    // Smooth bezier wave dipping and swooping across
    final cp1 = Offset(size.width * 0.32, size.height + 16);
    final ep1 = Offset(size.width * 0.64, size.height - 30);
    path.quadraticBezierTo(cp1.dx, cp1.dy, ep1.dx, ep1.dy);

    final cp2 = Offset(size.width * 0.88, size.height - 65);
    final ep2 = Offset(size.width, size.height - 24);
    path.quadraticBezierTo(cp2.dx, cp2.dy, ep2.dx, ep2.dy);

    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

// ============================================================================
// TOPOGRAPHIC CONTOUR PAINTER FOR WELCOME SCREEN
// ============================================================================
class _WelcomeTopographicPainter extends CustomPainter {
  final bool isDark;

  const _WelcomeTopographicPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paintSoft = Paint()
      ..color = Colors.white.withValues(alpha: isDark ? 0.08 : 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    final paintAccent = Paint()
      ..color = Colors.white.withValues(alpha: isDark ? 0.16 : 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    // Organic loop 1 (top-left contour hill)
    for (int i = 0; i < 4; i++) {
      final radX = 40.0 + i * 32.0;
      final radY = 30.0 + i * 24.0;
      final rect = Rect.fromCenter(
        center: Offset(w * 0.16, h * 0.22),
        width: radX * 2,
        height: radY * 2,
      );
      canvas.drawOval(rect, i.isEven ? paintAccent : paintSoft);
    }

    // Organic loop 2 (center-right contour hill)
    for (int i = 0; i < 5; i++) {
      final radX = 50.0 + i * 36.0;
      final radY = 38.0 + i * 28.0;
      final rect = Rect.fromCenter(
        center: Offset(w * 0.84, h * 0.40),
        width: radX * 2,
        height: radY * 2,
      );
      canvas.drawOval(rect, i % 2 == 1 ? paintAccent : paintSoft);
    }

    // Flowing sweeping ridge paths
    final path1 = Path();
    path1.moveTo(0, h * 0.18);
    path1.cubicTo(w * 0.30, h * 0.08, w * 0.60, h * 0.35, w, h * 0.15);
    canvas.drawPath(path1, paintSoft);

    final path2 = Path();
    path2.moveTo(0, h * 0.50);
    path2.cubicTo(w * 0.35, h * 0.68, w * 0.65, h * 0.25, w, h * 0.58);
    canvas.drawPath(path2, paintAccent);

    final path3 = Path();
    path3.moveTo(0, h * 0.76);
    path3.cubicTo(w * 0.30, h * 0.88, w * 0.70, h * 0.62, w, h * 0.80);
    canvas.drawPath(path3, paintSoft);
  }

  @override
  bool shouldRepaint(covariant _WelcomeTopographicPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
