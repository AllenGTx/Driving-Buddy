import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_colors.dart';
import '../../../services/language_service.dart';
import '../../../services/theme_service.dart';
import '../voice_buddy_controller.dart';
import 'buddy_tutorial_sheet.dart';

/// Tombol Push-to-Talk khusus sesi Berkendara (`MonitorScreen`).
/// Mendukung dua cara bicara:
/// 1. Ketuk sekali (Tap): langsung membuka layar penuh Orb & mendengar otomatis.
/// 2. Tekan & tahan (Hold-to-Talk): bicara selama ditahan, lepas jari langsung terkirim seketika.
class BuddyPushToTalkBar extends StatefulWidget {
  const BuddyPushToTalkBar({
    super.key,
    required this.controller,
  });

  final VoiceBuddyController controller;

  @override
  State<BuddyPushToTalkBar> createState() => _BuddyPushToTalkBarState();
}

class _BuddyPushToTalkBarState extends State<BuddyPushToTalkBar> {
  static const Cubic _appleOut = Cubic(0.23, 1.0, 0.32, 1.0);
  bool _pressing = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.controller,
        ThemeService.instance,
        LanguageService.instance,
      ]),
      builder: (context, _) {
        final isDark = ThemeService.instance.isDarkMode;
        final isEn = LanguageService.instance.isEnglish;
        final ctrl = widget.controller;
        final nick = ctrl.activeNickname;
        final active =
            _pressing ||
            ctrl.isHoldingPtt ||
            ctrl.phase == SiriOrbPhase.listening;

        return Row(
          children: [
            Expanded(
              child: Listener(
                onPointerDown: (_) {
                  HapticFeedback.lightImpact();
                  setState(() => _pressing = true);
                  ctrl.onPushToTalkDown();
                },
                onPointerUp: (_) {
                  if (_pressing) setState(() => _pressing = false);
                  ctrl.onPushToTalkUp();
                },
                onPointerCancel: (_) {
                  if (_pressing) setState(() => _pressing = false);
                  ctrl.onPushToTalkUp();
                },
                child: AnimatedScale(
                  scale: _pressing ? 0.97 : 1.0,
                  duration: const Duration(milliseconds: 110),
                  curve: _appleOut,
                  child: Semantics(
                    button: true,
                    label: isEn
                        ? 'Push to talk with $nick'
                        : 'Tekan untuk bicara dengan $nick',
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 52),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: active
                              ? const [Color(0xFFFF7A2E), Color(0xFFD84315)]
                              : const [Color(0xFFF26B1D), Color(0xFFD9530F)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF26B1D).withValues(
                              alpha: active ? 0.42 : 0.25,
                            ),
                            blurRadius: active ? 16 : 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            active
                                ? Icons.graphic_eq_rounded
                                : Icons.mic_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  active
                                      ? (isEn
                                            ? 'Listening... Release to send'
                                            : 'Mendengarkan... Lepas untuk kirim')
                                      : (isEn
                                            ? 'Talk to $nick (Push to Talk)'
                                            : 'Bicara ke $nick (Tekan / Tahan)'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  ctrl.isEnabled
                                      ? (isEn
                                            ? 'Voice standby active · Or say "Hey $nick"'
                                            : 'Suara siaga aktif · Bisa juga panggil "Hei $nick"')
                                      : (isEn
                                            ? 'Tap or hold to speak anytime'
                                            : 'Ketuk sekali atau tahan untuk ngobrol'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFFFEDD5),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: isEn ? 'Buddy Guide & Voice' : 'Panduan & Pilihan Buddy',
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => showBuddyTutorialSheet(context),
                child: Container(
                  width: 50,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCardBg : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFF26B1D).withValues(alpha: 0.45),
                    ),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: Color(0xFFF26B1D),
                    size: 21,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
