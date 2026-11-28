import 'package:flutter/material.dart';

import '../../../core/app_colors.dart';
import '../../../services/language_service.dart';
import '../../../services/theme_service.dart';
import '../buddy_tts_service.dart';
import '../buddy_voice_config.dart';

Future<void> showBuddyTutorialSheet(BuildContext context) async {
  await BuddyVoiceConfig.instance.load();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    enableDrag: true,
    isDismissible: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _BuddyTutorialSheetBody(),
  );
}

class _BuddyTutorialSheetBody extends StatefulWidget {
  const _BuddyTutorialSheetBody();

  @override
  State<_BuddyTutorialSheetBody> createState() =>
      _BuddyTutorialSheetBodyState();
}

class _BuddyTutorialSheetBodyState extends State<_BuddyTutorialSheetBody> {
  late final TextEditingController _nameCtrl;
  final BuddyTtsService _previewTts = BuddyTtsService();
  bool _testingVoice = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
      text: BuddyVoiceConfig.instance.rawCustomNickname,
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _previewTts.dispose();
    super.dispose();
  }

  Future<void> _previewVoice(BuddyVoiceProfile profile, bool isEn) async {
    if (_testingVoice) return;
    setState(() => _testingVoice = true);
    try {
      final nick = BuddyVoiceConfig.instance.rawCustomNickname.trim().isNotEmpty
          ? BuddyVoiceConfig.instance.rawCustomNickname.trim()
          : profile.defaultNickname;
      final sampleText = isEn
          ? 'Hi! I am $nick, ready to keep you company and help you stay safe on the road.'
          : 'Halo! Aku $nick, siap menemani perjalananmu supaya tetap aman dan menyenangkan.';
      await _previewTts.speakReply(
        profile: profile,
        text: sampleText,
      );
    } finally {
      if (mounted) setState(() => _testingVoice = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        BuddyVoiceConfig.instance,
        ThemeService.instance,
        LanguageService.instance,
      ]),
      builder: (context, _) {
        final isDark = ThemeService.instance.isDarkMode;
        final isEn = LanguageService.instance.isEnglish;
        final bg = isDark ? AppColors.darkSurface : Colors.white;
        final textPrimary =
            isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
        final textSec =
            isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

        final curProfile = BuddyVoiceConfig.instance.profile;
        final activeNick = BuddyVoiceConfig.instance.activeNickname;

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.80,
            minChildSize: 0.42,
            maxChildSize: 0.90,
            shouldCloseOnMinExtent: true,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: textSec.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1E8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.record_voice_over_rounded,
                          color: Color(0xFFF26B1D),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isEn
                              ? 'Your Driving Buddy Guide'
                              : 'Panduan Teman Perjalananmu',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildGuideStep(
                    numLabel: '1',
                    title: isEn
                        ? 'Just Call Out Their Name'
                        : 'Sapa Langsung Tanpa Sentuh Layar',
                    desc: isEn
                        ? 'Turn on Voice Buddy on the Home screen, then simply say "$activeNick", "Hey $activeNick", or use the Push-to-Talk button while driving.'
                        : 'Nyalakan Asisten Suara di Beranda, lalu cukup sapa "$activeNick", "Hei $activeNick", atau tekan tombol bicara di layar Berkendara.',
                    textPrimary: textPrimary,
                    textSec: textSec,
                  ),
                  const SizedBox(height: 12),
                  _buildGuideStep(
                    numLabel: '2',
                    title: isEn
                        ? 'Find Rest Stops & Chat Along the Way'
                        : 'Cari Tempat Istirahat & Teman Ngobrol',
                    desc: isEn
                        ? 'Ask "Help me find a rest stop nearby", "Where is the nearest gas station?", or just chat casually to keep your drive fun and relaxed.'
                        : 'Tanyakan "Tolong cari tempat istirahat terdekat", "SPBU paling dekat di mana?", atau ajak ngobrol santai supaya perjalanan tidak jenuh.',
                    textPrimary: textPrimary,
                    textSec: textSec,
                  ),
                  const SizedBox(height: 12),
                  _buildGuideStep(
                    numLabel: '3',
                    title: isEn
                        ? 'Gentle Reminders When You Feel Tired'
                        : 'Pengingat Lembut Saat Mulai Lelah',
                    desc: isEn
                        ? 'When your eyes look sleepy or you yawn often, $activeNick will gently remind you to take a quick break. Tap the glowing orb anytime to interrupt.'
                        : 'Saat matamu mulai sayu atau sering menguap, $activeNick akan menyapamu dengan lembut untuk beristirahat sejenak. Ketuk bola cahaya kapan saja untuk menyela.',
                    textPrimary: textPrimary,
                    textSec: textSec,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    isEn ? 'Choose Your Buddy' : 'Pilih Suara Buddy Kamu',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...BuddyVoiceProfile.values.map((p) {
                    final selected = p == curProfile;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => BuddyVoiceConfig.instance.setProfile(p),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFFF26B1D)
                                  : (isDark
                                        ? AppColors.darkCardBorder
                                        : AppColors.borderLight),
                              width: selected ? 1.6 : 1.0,
                            ),
                            color: selected
                                ? const Color(0xFFF26B1D).withValues(alpha: 0.08)
                                : Colors.transparent,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                                color: selected
                                    ? const Color(0xFFF26B1D)
                                    : textSec,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  p.localizedLabel(isEnglish: isEn),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _testingVoice
                                    ? null
                                    : () => _previewVoice(p, isEn),
                                icon: const Icon(
                                  Icons.volume_up_rounded,
                                  size: 16,
                                  color: Color(0xFFF26B1D),
                                ),
                                label: Text(
                                  isEn ? 'Preview' : 'Coba',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFF26B1D),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  Text(
                    isEn
                        ? 'Favorite Nickname (Leave blank to use ${curProfile.defaultNickname})'
                        : 'Panggilan Kesayangan (Kosongkan untuk pakai ${curProfile.defaultNickname})',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _nameCtrl,
                    maxLength: 20,
                    onChanged: (v) =>
                        BuddyVoiceConfig.instance.setCustomNickname(v),
                    style: TextStyle(color: textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: isEn
                          ? 'Example: ${curProfile.defaultNickname}'
                          : 'Contoh: ${curProfile.defaultNickname}',
                      hintStyle: TextStyle(color: textSec),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildGuideStep({
    required String numLabel,
    required String title,
    required String desc,
    required Color textPrimary,
    required Color textSec,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF26B1D),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            numLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: textSec,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
