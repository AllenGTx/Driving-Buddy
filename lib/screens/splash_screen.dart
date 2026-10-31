import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../routes/app_routes.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutBack),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.45, curve: Curves.easeIn),
      ),
    );


    _controller.forward();

    Future.delayed(const Duration(milliseconds: 2600), () async {
      if (!mounted) return;
      final user = FirebaseAuth.instance.currentUser;
      bool isVerifiedUser = false;
      if (user != null) {
        try {
          await user.reload();
          final freshUser = FirebaseAuth.instance.currentUser;
          isVerifiedUser = freshUser?.emailVerified ?? false;
        } catch (_) {
          isVerifiedUser = user.emailVerified;
        }
        if (!isVerifiedUser) {
          await FirebaseAuth.instance.signOut();
        }
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        isVerifiedUser ? AppRoutes.main : AppRoutes.welcome,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _pulseController.dispose();
    super.dispose();
  }

    @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // Background ambient gradient with warm amber cockpit glow
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.2),
                  radius: 1.0,
                  colors: [
                    Color(0xFF1E293B), // Deep slate glow
                    Color(0xFF0B1120), // Dark cockpit graphite
                  ],
                ),
              ),
            ),
          ),

          // Subtle decorative ambient aura
          Center(
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFF26B1D).withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Center Logo + Title + Dynamic Automotive Animation
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_controller, _pulseController]),
              builder: (context, _) {
                // Micro-breathing oscillation simulating engine idling
                final idleScale = 1.0 + (0.025 * _pulseController.value);
                final glowRadius = 140.0 + (30.0 * _pulseController.value);

                return FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo container dengan dynamic amber engine glow
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // Ambient breathing radial aura
                            Container(
                              width: glowRadius,
                              height: glowRadius * 0.7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    const Color(0xFFF26B1D).withValues(alpha: 0.28 + 0.15 * _pulseController.value),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),

                            // Driving Buddy Logo with idle pulse
                            Transform.scale(
                              scale: idleScale,
                              child: SizedBox(
                                width: 230,
                                height: 125,
                                child: Image.asset(
                                  'assets/images/DrivingBuddyLogo_white_tight.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        const Text(
                          'SISTEM MONITORING KESELAMATAN BERKENDARA',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.8,
                            color: Color(0xFF94A3B8),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),

                        // Pulsing loading dots
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(3, (i) {
                              final offset = (i / 3);
                              final anim = (_pulseController.value - offset).clamp(0.0, 1.0);
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF26B1D).withValues(alpha: 0.3 + 0.7 * anim),
                                  shape: BoxShape.circle,
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
