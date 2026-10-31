import 'package:flutter/material.dart';
import '../services/theme_service.dart';

class AppColors {
  // ============================================================================
  // BRAND ACCENTS (Luxury Copper — Cocok & Elegan di Mode Terang maupun Abu Gelap)
  // ============================================================================
  static const Color primary = Color(0xFFF26B1D); // Burnished Copper
  static const Color primaryDark = Color(0xFFD9560F);
  static const Color primaryLight = Color(0xFFFFF1E8); // Soft Orange Tint
  static const Color primaryContainer = Color(0xFFFFF1E8);
  static const Color accent = Color(0xFFFF7A2E); // Warm Copper Accent

  // ============================================================================
  // LIGHT PALETTE (Gading Bersih & Kartu Putih)
  // ============================================================================
  static const Color background = Color(0xFFFFFFFF); // Light Ivory
  static const Color surface = Colors.white;
  static const Color cardBg = Colors.white;
  static const Color cardBgSoft = Color(0xFFFFFFFF);
  static const Color cardBorder = Color(0xFFECEEF2); // orange-200 subtle border
  static const Color borderLight = Color(0xFFE2E8F0);

  static const Color textPrimary = Color(0xFF0F172A); // Deep Obsidian Slate
  static const Color textSecondary = Color(0xFF64748B); // Slate Muted
  static const Color textMuted = Color(0xFF94A3B8);

  // ============================================================================
  // DARK GRAY PALETTE (Abu-abu Gelap Nyaman, Bukan Hitam Pekat #000000)
  // ============================================================================
  static const Color darkBackground = Color(0xFF0B0F17); // Slate Charcoal Gelap
  static const Color darkSurface = Color(0xFF141A24); // Elevated Dark Gray
  static const Color darkCardBg = Color(0xFF141A24); // Dark Gray Card
  static const Color darkCardBgSoft = Color(0xFF1B2230); // Inner Sub-card Soft Gray
  static const Color darkCardBorder = Color(0xFF253042); // Muted Dark Gray Border
  static const Color darkBorderLight = Color(0xFF253042); // Subtle Divider Border

  static const Color darkTextPrimary = Color(0xFFF1F5F9); // Crisp Slate 100
  static const Color darkTextSecondary = Color(0xFF94A3B8); // Slate 400
  static const Color darkTextMuted = Color(0xFF64748B); // Slate 500

  static const Color darkPrimaryContainer = Color(0xFF2A1A10); // Warm Copper Slate
  static const Color darkChipBg = Color(0xFF1B2230); // Dark Gray Chip

  // ============================================================================
  // COCKPIT & CAMERA ELEMENTS
  // ============================================================================
  static const Color cameraBg = Color(0xFF0F172A);
  static const Color cockpitDark = Color(0xFF14100E);
  static const Color cockpitCard = Color(0xFF1F1B18);

  // ============================================================================
  // SEMANTICS & STATUS
  // ============================================================================
  static const Color success = Color(0xFF059669); // Emerald
  static const Color successLight = Color(0xFF10B981);
  static const Color successBg = Color(0xFFECFDF5);
  static const Color successBorder = Color(0xFFA7F3D0);
  static const Color darkSuccessBg = Color(0xFF132B22);

  static const Color warning = Color(0xFFE5A938); // Warm Topaz
  static const Color warningBg = Color(0xFFFFFBEB);
  static const Color darkWarningBg = Color(0xFF2E2412);

  static const Color danger = Color(0xFFD94126); // Automotive Vermilion
  static const Color dangerLight = Color(0xFFEF4444);
  static const Color dangerBg = Color(0xFFFEF2F2);
  static const Color dangerBorder = Color(0xFFFECACA);
  static const Color darkDangerBg = Color(0xFF2F1714);

  static const Color chipBg = Color(0xFFFFF1E8);

  // ============================================================================
  // DYNAMIC HELPERS (Mengikuti status ThemeService secara instan)
  // ============================================================================
  static bool get isDark => ThemeService.instance.isDarkMode;

  static Color get dynamicBackground => isDark ? darkBackground : background;
  static Color get dynamicSurface => isDark ? darkSurface : surface;
  static Color get dynamicCardBg => isDark ? darkCardBg : cardBg;
  static Color get dynamicCardBgSoft => isDark ? darkCardBgSoft : cardBgSoft;
  static Color get dynamicCardBorder => isDark ? darkCardBorder : cardBorder;
  static Color get dynamicBorderLight => isDark ? darkBorderLight : borderLight;
  static Color get dynamicTextPrimary => isDark ? darkTextPrimary : textPrimary;
  static Color get dynamicTextSecondary => isDark ? darkTextSecondary : textSecondary;
  static Color get dynamicTextMuted => isDark ? darkTextMuted : textMuted;
  static Color get dynamicPrimaryContainer => isDark ? darkPrimaryContainer : primaryContainer;
  static Color get dynamicChipBg => isDark ? darkChipBg : chipBg;
}
