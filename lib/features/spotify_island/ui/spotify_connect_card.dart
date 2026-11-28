import 'package:flutter/material.dart';

import '../../../core/app_colors.dart';
import '../../../core/design_tokens.dart';
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
        await _spotify.connectSpotify(openAppToAuthorize: false);
        if (mounted) {
          final isEn = LanguageService.instance.isEnglish;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isEn
                    ? 'Spotify Dynamic Island activated! Ask Buddy to play any song.'
                    : 'Spotify Dynamic Island aktif! Sekarang minta Buddy setel lagu lewat suara tanpa keluar aplikasi.',
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

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCardBg : Colors.white,
            borderRadius: BorderRadius.circular(DbRadius.r20),
            border: Border.all(
              color: connected
                  ? const Color(0xFF1ED760).withValues(alpha: isDark ? 0.50 : 0.42)
                  : (isDark ? AppColors.darkCardBorder : const Color(0xFFECEEF2)),
              width: connected ? 1.4 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.24)
                    : const Color(0xFF1ED760).withValues(alpha: connected ? 0.08 : 0.03),
                blurRadius: 14,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              // Logo Resmi Spotify
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0C),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF1ED760).withValues(alpha: 0.32),
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
                            color: connected
                                ? const Color(0xFF1ED760).withValues(alpha: 0.14)
                                : (isDark
                                      ? AppColors.darkCardBgSoft
                                      : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            connected
                                ? (isEn ? 'CONNECTED' : 'TERHUBUNG')
                                : (isEn ? 'OFF' : 'BELUM AKTIF'),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: connected
                                  ? const Color(0xFF16A34A)
                                  : (isDark
                                        ? AppColors.darkTextSecondary
                                        : const Color(0xFF64748B)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      connected
                          ? (isEn
                                ? 'Say "Play [Song Name] on Spotify" to launch Dynamic Island.'
                                : 'Ucapkan "Setelkan lagu [Judul] di Spotify" ke Buddy kapan saja.')
                          : (installed
                                ? (isEn
                                      ? 'Spotify app detected on phone · Connect for hands-free music'
                                      : 'Aplikasi Spotify terdeteksi di HP · Hubungkan untuk putar lewat suara')
                                : (isEn
                                      ? 'Connect Spotify to play music via voice on Dynamic Island'
                                      : 'Hubungkan Spotify agar Buddy bisa menyetel lagu di Dynamic Island')),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.2,
                        height: 1.32,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
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
        );
      },
    );
  }
}
