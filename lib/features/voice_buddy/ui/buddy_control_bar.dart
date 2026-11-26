import 'package:flutter/material.dart';

import '../../../core/app_colors.dart';
import '../../../services/language_service.dart';
import '../../../services/theme_service.dart';
import '../voice_buddy_controller.dart';
import 'buddy_tutorial_sheet.dart';

class BuddyControlBar extends StatefulWidget {
  const BuddyControlBar({
    super.key,
    required this.controller,
  });

  final VoiceBuddyController controller;

  @override
  State<BuddyControlBar> createState() => _BuddyControlBarState();
}

class _BuddyControlBarState extends State<BuddyControlBar> {
  bool _tutorialPressed = false;

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
        final enabled = widget.controller.isEnabled;
        final nick = widget.controller.activeNickname;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: enabled
                ? const Color(0xFF1F140E)
                : (isDark ? AppColors.darkCardBgSoft : const Color(0xFFF8FAFC)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: enabled
                  ? const Color(0xFFF26B1D)
                  : (isDark ? AppColors.darkCardBorder : const Color(0xFFECEEF2)),
              width: enabled ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: enabled
                    ? const Color(0xFFF26B1D).withValues(alpha: 0.20)
                    : Colors.black.withValues(alpha: isDark ? 0.16 : 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: enabled ? widget.controller.onOrbTapped : null,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: enabled
                        ? const Color(0xFFF26B1D)
                        : (isDark
                              ? AppColors.darkCardBg
                              : const Color(0xFFFFF1E8)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    enabled ? Icons.graphic_eq_rounded : Icons.mic_off_rounded,
                    size: 20,
                    color: enabled ? Colors.white : const Color(0xFFF26B1D),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isEn ? 'Voice Buddy ($nick)' : 'Asisten Suara ($nick)',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: enabled
                            ? Colors.white
                            : (isDark
                                  ? AppColors.darkTextPrimary
                                  : const Color(0xFF0F172A)),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      enabled
                          ? (isEn
                                ? 'Standby · Say "$nick" or "Hey $nick"'
                                : 'Siaga · Panggil "$nick" atau "Hei $nick"')
                          : (isEn
                                ? 'Off · Turn on for hands-free buddy'
                                : 'Mati · Nyalakan untuk teman bicara'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: enabled
                            ? const Color(0xFFFFCBA4)
                            : (isDark
                                  ? AppColors.darkTextSecondary
                                  : const Color(0xFF64748B)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Listener(
                onPointerDown: (_) => setState(() => _tutorialPressed = true),
                onPointerUp: (_) => setState(() => _tutorialPressed = false),
                onPointerCancel: (_) => setState(() => _tutorialPressed = false),
                child: AnimatedScale(
                  scale: _tutorialPressed ? 0.96 : 1.0,
                  duration: const Duration(milliseconds: 120),
                  curve: const Cubic(0.23, 1.0, 0.32, 1.0),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => showBuddyTutorialSheet(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: enabled
                            ? const Color(0xFF331D12)
                            : (isDark
                                  ? AppColors.darkCardBg
                                  : const Color(0xFFFFF1E8)),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFF26B1D).withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.help_outline_rounded,
                            size: 14,
                            color: Color(0xFFF26B1D),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isEn ? 'Guide' : 'Panduan',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: enabled
                                  ? const Color(0xFFFFEDD5)
                                  : const Color(0xFFF26B1D),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Switch.adaptive(
                value: enabled,
                activeTrackColor: const Color(0xFFF26B1D),
                activeThumbColor: Colors.white,
                onChanged: (val) async {
                  final ok = await widget.controller.setEnabled(val);
                  if (val && !ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isEn
                              ? 'Microphone permission is needed to enable Voice Buddy.'
                              : 'Izin mikrofon diperlukan untuk menyalakan Asisten Suara.',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
