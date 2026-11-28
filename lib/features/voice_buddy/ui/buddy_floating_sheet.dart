import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../../services/language_service.dart';
import '../voice_buddy_controller.dart';
import 'siri_orange_orb.dart';

/// Overlay Studio Glass Orb Layar Penuh:
/// - Latar belakang ruang gelap `#040406` + `BackdropFilter` statis mulus 60/120fps.
/// - Tidak menutup secara tidak sengaja saat layar/bola diketuk! Menekan bola memicu
///   kilatan energi (*glass flare*) dan hanya menyela bila asisten sedang berbicara.
/// - Saat berpikir (`thinking`), pita cahaya halus melintasi baris status setiap 2.2 detik (tanpa spinner).
/// - Saat mode peringatan kantuk (`isDrowsyReminderActive`), teks `"Silakan bicara sekarang..."` dihapus bersih.
class BuddyFloatingSheet extends StatefulWidget {
  const BuddyFloatingSheet({
    super.key,
    required this.controller,
  });

  final VoiceBuddyController controller;

  @override
  State<BuddyFloatingSheet> createState() => _BuddyFloatingSheetState();
}

class _BuddyFloatingSheetState extends State<BuddyFloatingSheet>
    with TickerProviderStateMixin {
  static const Cubic _easeOutStrong = Cubic(0.23, 1.0, 0.32, 1.0);
  static const Cubic _siriDismissCurve = Cubic(0.32, 0.0, 0.67, 0.0);

  late final AnimationController _presentCtrl;
  late final AnimationController _shimmerCtrl;
  bool _wasActive = false;
  bool _orbPressed = false;
  double _pressKickCounter = 0.0;
  Offset _pointerOffset = Offset.zero;

  static final SpringDescription _siriSummonSpring =
      SpringDescription.withDampingRatio(
        mass: 1.0,
        stiffness: 290.0,
        ratio: 0.78,
      );

  @override
  void initState() {
    super.initState();
    _presentCtrl = AnimationController.unbounded(vsync: this, value: 0.0);
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    widget.controller.addListener(_syncPresentationMotion);
    _syncPresentationMotion();
  }

  @override
  void didUpdateWidget(covariant BuddyFloatingSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncPresentationMotion);
      widget.controller.addListener(_syncPresentationMotion);
      _syncPresentationMotion();
    }
  }

  void _syncPresentationMotion() {
    if (!mounted) return;
    final phase = widget.controller.phase;
    final shouldShow =
        phase != SiriOrbPhase.hidden && phase != SiriOrbPhase.dismissing;
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    if (shouldShow && !_wasActive) {
      _wasActive = true;
      HapticFeedback.lightImpact();
      if (reducedMotion) {
        _presentCtrl.animateTo(
          1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      } else {
        final startVal = _presentCtrl.value.clamp(0.0, 1.0);
        final sim = SpringSimulation(
          _siriSummonSpring,
          startVal,
          1.0,
          _presentCtrl.velocity,
        );
        _presentCtrl.animateWith(sim);
      }
    } else if (!shouldShow && _wasActive) {
      _wasActive = false;
      if (phase == SiriOrbPhase.hidden) {
        _presentCtrl.value = 0.0;
      } else {
        _presentCtrl.animateTo(
          0.0,
          duration: Duration(milliseconds: reducedMotion ? 140 : 280),
          curve: _siriDismissCurve,
        );
      }
    } else if (phase == SiriOrbPhase.hidden && _presentCtrl.value != 0.0) {
      _presentCtrl.value = 0.0;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncPresentationMotion);
    _presentCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final screenSize = MediaQuery.sizeOf(context);
    // Ukuran proporsional studio spec: tetap besar & megah di layar HP
    final orbCanvasSize = (screenSize.width * 0.72).clamp(240.0, 310.0);

    return ListenableBuilder(
      listenable: Listenable.merge([
        controller,
        _presentCtrl,
        LanguageService.instance,
      ]),
      builder: (context, _) {
        final rawT = _presentCtrl.value;
        if (controller.phase == SiriOrbPhase.hidden && rawT <= 0.005) {
          return const SizedBox.shrink();
        }

        final opacityT = rawT.clamp(0.0, 1.0);
        final springT = rawT.clamp(0.0, 1.08);
        // Tumbuh mulus dari 80% ke ukuran penuh sesuai spesifikasi studio
        final orbScale = reducedMotion ? 1.0 : (0.80 + 0.20 * springT);
        final orbTranslateY =
            reducedMotion ? 0.0 : ((1.0 - opacityT) * 22.0);
        final textOpacity = ((opacityT - 0.16) / 0.84).clamp(0.0, 1.0);
        final textTranslateY =
            reducedMotion ? 0.0 : ((1.0 - textOpacity) * 12.0);

        final isEn = LanguageService.instance.isEnglish;
        final nick = controller.activeNickname;
        final isDrowsy = controller.isDrowsyReminderActive;

        final statusLabel = isDrowsy
            ? (isEn ? 'Safety Alertness Reminder' : 'Pengingat Kewaspadaan')
            : switch (controller.phase) {
                SiriOrbPhase.summon => isEn ? '$nick is here' : '$nick hadir',
                SiriOrbPhase.listening => controller.isHoldingPtt
                    ? (isEn
                          ? 'Release button to send...'
                          : 'Lepas tombol untuk kirim...')
                    : (controller.isFollowUpListening
                          ? (isEn
                                ? 'Keep talking · Pause to finish'
                                : 'Lanjut bicara · Diam sejenak jika selesai')
                          : (isEn
                                ? 'Listening to you...'
                                : 'Mendengarkan suaramu...')),
                SiriOrbPhase.thinking =>
                  isEn ? 'Thinking of an answer...' : 'Memikirkan jawaban...',
                SiriOrbPhase.speaking =>
                  isEn
                      ? '$nick is speaking · Tap orb to interrupt'
                      : '$nick berbicara · Ketuk bola untuk sela',
                _ => nick,
              };

        final String primaryLine;
        if (controller.replyText.isNotEmpty) {
          primaryLine = controller.replyText;
        } else if (controller.transcriptText.isNotEmpty) {
          primaryLine = controller.transcriptText;
        } else if (isDrowsy) {
          primaryLine = '';
        } else {
          primaryLine = isEn
              ? 'Go ahead, speak now...'
              : 'Silakan bicara sekarang...';
        }

        return Positioned.fill(
          child: IgnorePointer(
            ignoring:
                controller.phase == SiriOrbPhase.dismissing || opacityT < 0.08,
            child: Material(
              type: MaterialType.transparency,
              child: Stack(
                children: [
                  // 1. Studio Dark Room #040406 + Backdrop Blur ringan 10px terisolasi di RepaintBoundary (60/120fps)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          // Sengaja ditahan agar salah sentuh di layar tidak menghilangkan asisten!
                        },
                        child: Opacity(
                          opacity: opacityT,
                          child: BackdropFilter(
                            filter: ImageFilter.blur(
                              sigmaX: 10.0,
                              sigmaY: 10.0,
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  center: const Alignment(0.0, -0.18),
                                  radius: 0.95,
                                  colors: [
                                    (controller.phase == SiriOrbPhase.thinking
                                            ? const Color(0xFF280707)
                                            : const Color(0xFF1E0D06))
                                        .withValues(alpha: 0.86),
                                    const Color(0xFF040406)
                                        .withValues(alpha: 0.94),
                                  ],
                                ),
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 2. Bola Kaca Studio (32% dari atas) + Headline #F2F2F5 + Status Baris Bercahaya
                  SafeArea(
                    child: Stack(
                      children: [
                        Align(
                          alignment: const Alignment(0.0, -0.16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 26),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Bola Kaca Studio dengan Efek Tekan Flare
                                Opacity(
                                  opacity: opacityT,
                                  child: Transform.translate(
                                    offset: Offset(0, orbTranslateY),
                                    child: Transform.scale(
                                      scale: orbScale,
                                      child: Listener(
                                        onPointerDown: (ev) {
                                          final half = orbCanvasSize * 0.5;
                                          final nx = ((ev.localPosition.dx - half) / half).clamp(-1.0, 1.0);
                                          final ny = ((half - ev.localPosition.dy) / half).clamp(-1.0, 1.0);
                                          setState(() {
                                            _orbPressed = true;
                                            _pressKickCounter += 1.0;
                                            _pointerOffset = Offset(nx, ny);
                                          });
                                          HapticFeedback.selectionClick();
                                        },
                                        onPointerMove: (ev) {
                                          final half = orbCanvasSize * 0.5;
                                          final nx = ((ev.localPosition.dx - half) / half).clamp(-1.0, 1.0);
                                          final ny = ((half - ev.localPosition.dy) / half).clamp(-1.0, 1.0);
                                          setState(() {
                                            _pointerOffset = Offset(nx, ny);
                                          });
                                        },
                                        onPointerUp: (_) {
                                          if (_orbPressed || _pointerOffset != Offset.zero) {
                                            setState(() {
                                              _orbPressed = false;
                                              _pointerOffset = Offset.zero;
                                            });
                                          }
                                          if (controller.isHoldingPtt) {
                                            controller.onPushToTalkUp();
                                          }
                                        },
                                        onPointerCancel: (_) {
                                          if (_orbPressed || _pointerOffset != Offset.zero) {
                                            setState(() {
                                              _orbPressed = false;
                                              _pointerOffset = Offset.zero;
                                            });
                                          }
                                          if (controller.isHoldingPtt) {
                                            controller.onPushToTalkUp();
                                          }
                                        },
                                        child: AnimatedScale(
                                          scale: (_orbPressed && !reducedMotion)
                                              ? 0.96
                                              : 1.0,
                                          duration: const Duration(
                                            milliseconds: 100,
                                          ),
                                          curve: _easeOutStrong,
                                          child: GestureDetector(
                                            onTap: controller.onOrbTapped,
                                            child: SiriOrangeOrb(
                                              phase: controller.phase,
                                              energyListenable:
                                                  controller.orbEnergyListenable,
                                              frequencyListenable:
                                                  controller.orbFrequencyListenable,
                                              size: orbCanvasSize,
                                              pressKick: _pressKickCounter,
                                              pointerOffset: _pointerOffset,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // Baris Status Sekunder (62% dari #F2F2F5 + Pita Cahaya Melintas Tiap 2.2s Saat Thinking)
                                Opacity(
                                  opacity: textOpacity,
                                  child: Transform.translate(
                                    offset: Offset(0, textTranslateY),
                                    child: Semantics(
                                      liveRegion: true,
                                      child: _StatusShimmerLine(
                                        text: statusLabel,
                                        shimmerAnimation: _shimmerCtrl,
                                        isThinking:
                                            controller.phase ==
                                                SiriOrbPhase.thinking &&
                                            !reducedMotion,
                                      ),
                                    ),
                                  ),
                                ),

                                if (primaryLine.isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  // Headline Utama (#F2F2F5, weight 650, letterSpacing -0.035em, terpusat)
                                  Opacity(
                                    opacity: textOpacity,
                                    child: Transform.translate(
                                      offset: Offset(0, textTranslateY),
                                      child: AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        switchInCurve: _easeOutStrong,
                                        child: Text(
                                          primaryLine,
                                          key: ValueKey<String>(primaryLine),
                                          textAlign: TextAlign.center,
                                          maxLines: 5,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 22.0,
                                            height: 1.34,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.7,
                                            color: Color(0xFFF2F2F5),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        // Satu-satunya tombol penutup eksplisit (mencegah tertutup tak sengaja!)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 24,
                          child: Opacity(
                            opacity: textOpacity,
                            child: Transform.translate(
                              offset: Offset(0, textTranslateY),
                              child: Center(
                                child: Semantics(
                                  button: true,
                                  label: isEn
                                      ? 'Close voice assistant'
                                      : 'Tutup asisten suara',
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(999),
                                    onTap: controller.dismissSheet,
                                    child: Container(
                                      constraints: const BoxConstraints(
                                        minWidth: 116,
                                        minHeight: 46,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 22,
                                        vertical: 11,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF7A2E)
                                            .withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(
                                          color: const Color(0xFFFF9E44)
                                              .withValues(alpha: 0.38),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                            color: Color(0xFFF2F2F5),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            isEn ? 'Close' : 'Tutup',
                                            style: const TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFFF2F2F5),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
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

class _StatusShimmerLine extends StatelessWidget {
  const _StatusShimmerLine({
    required this.text,
    required this.shimmerAnimation,
    required this.isThinking,
  });

  final String text;
  final Animation<double> shimmerAnimation;
  final bool isThinking;

  @override
  Widget build(BuildContext context) {
    final pillBg = isThinking
        ? const Color(0xFFE53935).withValues(alpha: 0.16)
        : const Color(0xFFFF7A2E).withValues(alpha: 0.13);
    final pillBorder = isThinking
        ? const Color(0xFFFF5252).withValues(alpha: 0.45)
        : const Color(0xFFFF9E44).withValues(alpha: 0.34);

    final basePill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: pillBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: pillBorder,
        ),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.15,
          color: const Color(0xFFF2F2F5).withValues(alpha: 0.72),
        ),
      ),
    );

    if (!isThinking) return basePill;

    return AnimatedBuilder(
      animation: shimmerAnimation,
      builder: (context, child) {
        final sweepPos = shimmerAnimation.value * 2.4 - 0.7;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(sweepPos - 0.45, 0.0),
              end: Alignment(sweepPos + 0.45, 0.0),
              colors: [
                const Color(0xFFF2F2F5).withValues(alpha: 0.64),
                const Color(0xFFFF8A80),
                const Color(0xFFF2F2F5).withValues(alpha: 0.64),
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: basePill,
    );
  }
}
