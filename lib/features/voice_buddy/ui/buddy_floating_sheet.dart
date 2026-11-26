import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../../services/language_service.dart';
import '../voice_buddy_controller.dart';
import 'siri_orange_orb.dart';

/// Overlay Siri Layar Penuh dengan koreografi Apple Fluid Spring:
/// - Summon (Muncul): Pegas fisik Apple (`dampingRatio: 0.78`, `stiffness: 290`) dari `scale(0.76)` + `translateY(+26px)`,
///   crossfade pada `BackdropFilter` statis (tidak merender ulang radius blur per frame di Android!).
/// - Auto-Dismiss (Menutup sesudah bicara): Jalur simetris kembali ke titik cahaya (`scale(0.78)`, `translateY(+22px)`, `opacity -> 0`)
///   dalam 280ms (`Cubic(0.32, 0.0, 0.67, 0.0)`), dan siap mekar kembali secara instan saat dipanggil lagi!
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
    with SingleTickerProviderStateMixin {
  static const Cubic _easeOutStrong = Cubic(0.23, 1.0, 0.32, 1.0);
  static const Cubic _siriDismissCurve = Cubic(0.32, 0.0, 0.67, 0.0);

  late final AnimationController _presentCtrl;
  bool _wasActive = false;
  bool _orbPressed = false;

  // Parameter pegas Apple WWDC (dampingRatio ~0.78, terasa hidup namun tidak membal berlebihan)
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
      // Haptic ringan di frame yang sama saat Siri Orb mekar ke layar!
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
        // Animasi menutup halus ala Siri begitu selesai berbicara (jalur simetris)
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

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
        // Pegas Apple boleh sedikit melampaui 1.0 (~1.03) pada scale untuk efek mekar organik Siri
        final springT = rawT.clamp(0.0, 1.08);
        final orbScale = reducedMotion ? 1.0 : (0.76 + 0.24 * springT);
        final orbTranslateY =
            reducedMotion ? 0.0 : ((1.0 - opacityT) * 24.0);
        final textOpacity = ((opacityT - 0.18) / 0.82).clamp(0.0, 1.0);
        final textTranslateY =
            reducedMotion ? 0.0 : ((1.0 - textOpacity) * 12.0);

        final isEn = LanguageService.instance.isEnglish;
        final nick = controller.activeNickname;

        final statusLabel = switch (controller.phase) {
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

        final primaryLine = controller.replyText.isNotEmpty
            ? controller.replyText
            : (controller.transcriptText.isNotEmpty
                ? controller.transcriptText
                : (isEn
                      ? 'Go ahead, speak now...'
                      : 'Silakan bicara sekarang...'));

        return Positioned.fill(
          child: IgnorePointer(
            ignoring: controller.phase == SiriOrbPhase.dismissing || opacityT < 0.08,
            child: Material(
              type: MaterialType.transparency,
              child: Stack(
                children: [
                  // 1. Static BackdropFilter + Scrim Crossfade (60/120fps mulus di Android tanpa re-blur tiap frame!)
                  Positioned.fill(
                    child: Opacity(
                      opacity: opacityT,
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: controller.dismissSheet,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: const Alignment(0.0, -0.06),
                                radius: 0.92,
                                colors: [
                                  const Color(0xFF281208).withValues(alpha: 0.80),
                                  const Color(0xFF090607).withValues(alpha: 0.88),
                                ],
                              ),
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 2. Siri Orb & Teks di Tengah Layar (Transform + Opacity GPU-Only)
                  SafeArea(
                    child: Stack(
                      children: [
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Status Pill (Staggered halus)
                                Opacity(
                                  opacity: textOpacity,
                                  child: Transform.translate(
                                    offset: Offset(0, textTranslateY),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF26B1D)
                                            .withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(
                                          color: const Color(0xFFFF8A2B)
                                              .withValues(alpha: 0.40),
                                        ),
                                      ),
                                      child: Text(
                                        statusLabel,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.1,
                                          color: Color(0xFFFFCBA4),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 22),

                                // Bola Siri Utama (Apple Spring Scale + TranslateY)
                                Opacity(
                                  opacity: opacityT,
                                  child: Transform.translate(
                                    offset: Offset(0, orbTranslateY),
                                    child: Transform.scale(
                                      scale: orbScale,
                                      child: Listener(
                                        onPointerDown: (_) {
                                          if (!_orbPressed) {
                                            setState(() => _orbPressed = true);
                                          }
                                        },
                                        onPointerUp: (_) {
                                          if (_orbPressed) {
                                            setState(() => _orbPressed = false);
                                          }
                                          if (controller.isHoldingPtt) {
                                            controller.onPushToTalkUp();
                                          }
                                        },
                                        onPointerCancel: (_) {
                                          if (_orbPressed) {
                                            setState(() => _orbPressed = false);
                                          }
                                          if (controller.isHoldingPtt) {
                                            controller.onPushToTalkUp();
                                          }
                                        },
                                        child: AnimatedScale(
                                          scale: (_orbPressed && !reducedMotion)
                                              ? 0.95
                                              : 1.0,
                                          duration: const Duration(
                                            milliseconds: 110,
                                          ),
                                          curve: _easeOutStrong,
                                          child: GestureDetector(
                                            onTap: controller.onOrbTapped,
                                            child: SiriOrangeOrb(
                                              phase: controller.phase,
                                              energy: controller.orbEnergy,
                                              frequency:
                                                  controller.orbFrequency,
                                              size: 228,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Transkrip / Jawaban Asisten (Staggered halus)
                                Opacity(
                                  opacity: textOpacity,
                                  child: Transform.translate(
                                    offset: Offset(0, textTranslateY),
                                    child: AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 170,
                                      ),
                                      switchInCurve: _easeOutStrong,
                                      child: Text(
                                        primaryLine,
                                        key: ValueKey<String>(primaryLine),
                                        textAlign: TextAlign.center,
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 18.0,
                                          height: 1.42,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.2,
                                          color: Color(0xFFFFF7ED),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Tombol Tutup Bawah
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
                                        minWidth: 112,
                                        minHeight: 46,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 11,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.10),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        border: Border.all(
                                          color: Colors.white
                                              .withValues(alpha: 0.22),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                            color: Color(0xFFFFF7ED),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            isEn ? 'Close' : 'Tutup',
                                            style: const TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFFFFF7ED),
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
