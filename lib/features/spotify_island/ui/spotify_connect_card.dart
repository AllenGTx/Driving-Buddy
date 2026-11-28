import 'package:flutter/material.dart';

import '../../../core/app_colors.dart';
import '../../../core/design_tokens.dart';
import '../../../services/device_control_service.dart';
import '../../../services/language_service.dart';
import '../../../services/theme_service.dart';
import '../spotify_island_controller.dart';
import 'spotify_logo_mark.dart';

/// Kartu Koneksi Spotify Resmi di Beranda (di bawah tombol Mulai Perjalanan,
/// di atas Skor Kewaspadaan Rata-rata / Analisis Telemetri Realtime).
class SpotifyConnectCard extends StatefulWidget {
  const SpotifyConnectCard({super.key});

  @override
  State<SpotifyConnectCard> createState() => _SpotifyConnectCardState();
}

class _SpotifyConnectCardState extends State<SpotifyConnectCard> {
  final SpotifyIslandController _spotify = SpotifyIslandController.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _spotify.init();
  }

  Future<void> _handleToggleConnect() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_spotify.isConnected) {
        await _spotify.disconnectSpotify();
      } else {
        final ok = await _spotify.connectSpotify(openAppToAuthorize: true);
        if (!mounted) return;
        final isEn = LanguageService.instance.isEnglish;
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isEn
                    ? 'Spotify app is not installed on this phone yet. Please install & log in to Spotify first.'
                    : 'Aplikasi Spotify belum terpasang di HP ini. Install & login akun Spotify kamu terlebih dahulu.',
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
          return;
        }
        if (!_spotify.isNotificationAccessGranted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(
                isEn ? 'Enable Spotify Live Sync' : 'Aktifkan Sinkronisasi Spotify',
              ),
              content: Text(
                isEn
                    ? 'Allow Notification Access for Driving Buddy so Dynamic Island automatically syncs track titles, Spotify recommendations, ads, and playback time.'
                    : 'Izinkan Akses Notifikasi untuk Driving Buddy agar lagu berikutnya, iklan Spotify, dan timer Dynamic Island tersinkron otomatis. Pastikan kamu juga sudah login di aplikasi Spotify.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(isEn ? 'Later' : 'Nanti'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    DeviceControlService.instance.openNotificationAccessSettings();
                  },
                  child: Text(isEn ? 'Open Settings' : 'Buka Pengaturan'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isEn
                    ? 'Spotify connected! Ask Buddy to play any song.'
                    : 'Spotify terhubung! Sekarang minta Buddy setel lagu lewat suara.',
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _spotify,
        ThemeService.instance,
        LanguageService.instance,
      ]),
      builder: (context, _) {
        final isDark = ThemeService.instance.isDarkMode;
        final isEn = LanguageService.instance.isEnglish;
        final connected = _spotify.isConnected;
        final installed = _spotify.isSpotifyInstalled;
        final notifGranted = _spotify.isNotificationAccessGranted;
        final fullyReady = connected && notifGranted;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCardBg : Colors.white,
            borderRadius: BorderRadius.circular(DbRadius.r20),
            border: Border.all(
              color: fullyReady
                  ? const Color(0xFF1ED760).withValues(alpha: isDark ? 0.50 : 0.42)
                  : (connected
                        ? const Color(0xFFF59E0B).withValues(alpha: 0.48)
                        : (isDark ? AppColors.darkCardBorder : const Color(0xFFECEEF2))),
              width: connected ? 1.4 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.24)
                    : const Color(0xFF1ED760).withValues(alpha: fullyReady ? 0.08 : 0.03),
                blurRadius: 14,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Baris atas: Logo + Judul + Badge + Tombol
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0A0C),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: (fullyReady
                                ? const Color(0xFF1ED760)
                                : const Color(0xFFF59E0B))
                            .withValues(alpha: 0.32),
                      ),
                    ),
                    child: const SpotifyLogoMark(size: 32),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Spotify Dynamic Island',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? AppColors.darkTextPrimary
                                      : const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: fullyReady
                                    ? const Color(0xFF1ED760).withValues(alpha: 0.14)
                                    : (connected
                                          ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                                          : (isDark
                                                ? AppColors.darkCardBgSoft
                                                : const Color(0xFFF1F5F9))),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                fullyReady
                                    ? (isEn ? 'CONNECTED' : 'TERHUBUNG')
                                    : (connected
                                          ? (isEn ? 'ALLOW ACCESS' : 'PERLU IZIN')
                                          : (isEn ? 'OFF' : 'BELUM AKTIF')),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  color: fullyReady
                                      ? const Color(0xFF16A34A)
                                      : (connected
                                            ? const Color(0xFFD97706)
                                            : (isDark
                                                  ? AppColors.darkTextSecondary
                                                  : const Color(0xFF64748B))),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isEn
                              ? 'Spotify Native Mode · Requires Spotify app'
                              : 'Mode Spotify Native · Butuh aplikasi Spotify',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.3,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (connected && !notifGranted)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => DeviceControlService.instance.openNotificationAccessSettings(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isEn ? 'Allow' : 'Izinkan',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF09090B),
                          ),
                        ),
                      ),
                    )
                  else
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _busy ? null : _handleToggleConnect,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: connected
                              ? (isDark
                                    ? const Color(0xFF1E293B)
                                    : const Color(0xFFF1F5F9))
                              : const Color(0xFF1ED760),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          connected
                              ? (isEn ? 'Disconnect' : 'Putuskan')
                              : (isEn ? 'Connect' : 'Hubungkan'),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: connected
                                ? (isDark
                                      ? AppColors.darkTextPrimary
                                      : const Color(0xFF0F172A))
                                : const Color(0xFF09090B),
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),
              Divider(
                height: 1,
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.07),
              ),
              const SizedBox(height: 12),

              // ── Baris info: Premium badge + cara pakai + Free tier notice
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB).withValues(alpha: isDark ? 0.06 : 0.80),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.30 : 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.workspace_premium_rounded,
                          size: 14,
                          color: Color(0xFFD97706),
                        ),
                        const SizedBox(width: 5),
                        // Flexible agar teks tidak nembus batas card
                        Flexible(
                          child: Text(
                            isEn
                                ? 'Recommended: Spotify Premium for best experience'
                                : 'Disarankan: Spotify Premium untuk pengalaman terbaik',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFD97706),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _InfoRow(
                      icon: Icons.mic_rounded,
                      text: isEn
                          ? 'Say: "Play [Song] via Spotify" to use Spotify native mode'
                          : 'Ucapkan: "Setelkan [Lagu] via Spotify" untuk mode Spotify native',
                      isDark: isDark,
                    ),
                    const SizedBox(height: 4),
                    _InfoRow(
                      icon: Icons.music_note_rounded,
                      text: isEn
                          ? 'Without "via Spotify" → plays via in-app engine (no Premium needed)'
                          : 'Tanpa "via Spotify" → diputar lewat mesin internal app (tanpa Premium)',
                      isDark: isDark,
                    ),
                    const SizedBox(height: 4),
                    _InfoRow(
                      icon: Icons.warning_amber_rounded,
                      iconColor: const Color(0xFFEF4444),
                      text: isEn
                          ? 'Spotify Free: "via Spotify" mode will only resume your last active queue or radio — specific song requests require Premium'
                          : 'Spotify Free: mode "via Spotify" hanya melanjutkan antrean/radio terakhir yang aktif — request lagu spesifik membutuhkan Premium',
                      isDark: isDark,
                    ),
                  ],
                ),
              ),

              if (!installed || !connected) ...[
                const SizedBox(height: 10),
                Text(
                  installed
                      ? (isEn
                            ? 'Spotify app detected on your phone. Tap Connect to enable native mode.'
                            : 'Aplikasi Spotify terdeteksi di HP kamu. Ketuk Hubungkan untuk mode native.')
                      : (isEn
                            ? 'Spotify app not installed. Install & log in to Spotify first to use this card.'
                            : 'Aplikasi Spotify belum terpasang. Install & login Spotify dulu untuk menggunakan kartu ini.'),
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Widget baris informasi kecil (ikon + teks) untuk panel info kartu Spotify.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.text,
    required this.isDark,
    this.iconColor,
  });

  final IconData icon;
  final String text;
  final bool isDark;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 13,
          color: iconColor ?? (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.4,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
            ),
          ),
        ),
      ],
    );
  }
}
