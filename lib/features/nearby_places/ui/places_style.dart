import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';

// ============================================================================
// GAYA — token desain dari rancangan Stitch "Driving Buddy" (layar Berkendara):
// tembaga (copper) #E57A38 di atas gading hangat / abu-abu gelap nyaman,
// kapital kecil berjarak untuk label, sudut membulat 8/12 px.
// ============================================================================

class PlacesStyle {
  const PlacesStyle._();

  // ------------------------------------------------------------------ warna

  /// Warna utama desain (tembaga).
  static const Color copper = Color(0xFFE57A38);
  static const Color copperDark = Color(0xFFC25E21);

  /// Teks utama (dinamis mengikuti tema terang / gelap).
  static Color get ink => AppColors.isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
  static Color get slate700 => AppColors.isDark ? AppColors.darkTextPrimary : const Color(0xFF334155);
  static Color get slate600 => AppColors.isDark ? AppColors.darkTextSecondary : const Color(0xFF475569);
  static Color get slate500 => AppColors.isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B);
  static Color get slate400 => AppColors.isDark ? AppColors.darkTextMuted : const Color(0xFF94A3B8);
  static Color get slate300 => AppColors.isDark ? AppColors.darkCardBorder : const Color(0xFFCBD5E1);
  static Color get slate100 => AppColors.isDark ? AppColors.darkCardBgSoft : const Color(0xFFF1F5F9);

  /// Latar halaman / sheet.
  static Color get pageBg => AppColors.isDark ? AppColors.darkBackground : const Color(0xFFF8F9FA);
  static Color get cardBg => AppColors.isDark ? AppColors.darkCardBg : Colors.white;
  static Color get ivory => AppColors.isDark ? AppColors.darkCardBg : const Color(0xFFFFFBF8);
  static Color get orange50 => AppColors.isDark ? const Color(0xFF2E241E) : const Color(0xFFFFF7ED);
  static Color get orange100 => AppColors.isDark ? const Color(0xFF382A22) : const Color(0xFFFFEDD5);
  static Color get orange200 => AppColors.isDark ? const Color(0xFF4A3427) : const Color(0xFFFED7AA);
  static Color get orange300 => AppColors.isDark ? const Color(0xFF5E3F2E) : const Color(0xFFFDBA74);

  static const Color emerald = Color(0xFF059669);
  static Color get emerald50 => AppColors.isDark ? AppColors.darkSuccessBg : const Color(0xFFECFDF5);
  static const Color emerald200 = Color(0xFFA7F3D0);

  /// Mode darurat (alarm kantuk) dan pesan kesalahan.
  static const Color vermilion = Color(0xFFD94126);
  static const Color vermilionDark = Color(0xFFB3301B);
  static Color get vermilion50 => AppColors.isDark ? AppColors.darkDangerBg : const Color(0xFFFFF1EE);
  static Color get vermilion100 => AppColors.isDark ? const Color(0xFF3B1F1C) : const Color(0xFFFFE0D9);
  static const Color vermilion300 = Color(0xFFF4A593);

  // ---------------------------------------------------------------- ukuran

  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;

  static const double radiusLg = 8;
  static const double radiusXl = 12;

  /// Tombol aksi bulat-persegi (navigasi) & kotak ikon: 48 px.
  static const double actionSize = 48;

  // ------------------------------------------------------------------ teks

  /// 11 px, kapital berjarak, tebal — label kecil di atas judul.
  static const TextStyle labelCaps = TextStyle(
    fontSize: 11,
    height: 14 / 11,
    letterSpacing: 0.88,
    fontWeight: FontWeight.w700,
  );

  /// 20 px — nama tempat di kartu.
  static const TextStyle headlineSm = TextStyle(
    fontSize: 20,
    height: 26 / 20,
    letterSpacing: -0.3,
    fontWeight: FontWeight.w700,
  );

  /// 14 px — teks isi.
  static const TextStyle bodyMd = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    letterSpacing: 0.07,
    fontWeight: FontWeight.w400,
  );

  /// 12 px — keterangan.
  static const TextStyle bodySm = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    letterSpacing: 0.12,
    fontWeight: FontWeight.w500,
  );

  /// Teks tombol kategori.
  static const TextStyle chip = TextStyle(
    fontSize: 12.5,
    height: 1.2,
    fontWeight: FontWeight.w700,
  );

  // -------------------------------------------------------------- dekorasi

  /// Latar kartu Pitstop normal.
  static LinearGradient get pitstopGradient => AppColors.isDark
      ? const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF282F3D), Color(0xFF222731)],
          stops: <double>[0.0, 1.0],
        )
      : const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFFFF7ED), Color(0xFFFFEDD5), Color(0xFFFFFBF8)],
          stops: <double>[0.0, 0.6, 1.0],
        );

  /// Latar kartu Pitstop saat alarm kantuk (darurat).
  static LinearGradient get urgentGradient => AppColors.isDark
      ? const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF381B18), Color(0xFF222731)],
          stops: <double>[0.0, 1.0],
        )
      : const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFFFF1EE), Color(0xFFFFE0D9), Color(0xFFFFFBF8)],
          stops: <double>[0.0, 0.6, 1.0],
        );

  /// Bayangan halus (shadow-sm di desain).
  static List<BoxShadow> get softShadow => <BoxShadow>[
        BoxShadow(
          color: AppColors.isDark ? Colors.black26 : const Color(0x1A0F172A),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];

  /// Bayangan sangat tipis (shadow-xs).
  static List<BoxShadow> get hairShadow => <BoxShadow>[
        BoxShadow(
          color: AppColors.isDark ? Colors.black12 : const Color(0x0D0F172A),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];
}
