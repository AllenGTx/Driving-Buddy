import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'design_tokens.dart';

/// Konfigurasi tema aplikasi DrivingBuddy (Mode Terang & Mode Gelap Navy).
class AppTheme {
  const AppTheme._();

  static ThemeData _base({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color surfaceMuted,
    required Color border,
    required Color ink,
    required Color inkMuted,
  }) {
    final text = GoogleFonts.plusJakartaSansTextTheme(
      ThemeData(brightness: brightness).textTheme,
    ).apply(bodyColor: ink, displayColor: ink);

    final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(DbRadius.pill));
    const btnText = TextStyle(fontWeight: FontWeight.w700, fontSize: 15);
    final dark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      textTheme: text,
      colorScheme: ColorScheme.fromSeed(
        seedColor: DbColors.orange,
        brightness: brightness,
        primary: DbColors.orange,
        onPrimary: Colors.white,
        secondary: dark ? Colors.white : DbColors.ink,
        surface: surface,
        onSurface: ink,
        error: DbColors.danger,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800, color: ink),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DbRadius.card),
          side: BorderSide(color: border),
        ),
      ),
      dividerColor: border,
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DbColors.orange,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(64, 52),
          shape: pill,
          textStyle: btnText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: dark ? Colors.white : DbColors.ink,
          foregroundColor: dark ? DbColors.ink : Colors.white,
          minimumSize: const Size(64, 52),
          shape: pill,
          textStyle: btnText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(64, 52),
          side: BorderSide(color: border, width: 1.2),
          shape: pill,
          textStyle: btnText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: DbColors.orange, textStyle: btnText),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceMuted,
        hintStyle: TextStyle(color: inkMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DbRadius.input),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DbRadius.input),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DbRadius.input),
          borderSide: const BorderSide(color: DbColors.orange, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? DbColors.darkSurfaceMuted : DbColors.ink,
        contentTextStyle: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DbRadius.input)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? DbColors.orange
              : (dark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => Colors.transparent,
        ),
      ),
    );
  }

  /// Tema Terang: latar putih bersih.
  static ThemeData get lightTheme => _base(
        brightness: Brightness.light,
        bg: AppColors.background,
        surface: AppColors.surface,
        surfaceMuted: DbColors.surfaceMuted,
        border: AppColors.borderLight,
        ink: AppColors.textPrimary,
        inkMuted: AppColors.textSecondary,
      );

  /// Tema Gelap: navy-hitam ala kokpit GT.
  static ThemeData get darkTheme => _base(
        brightness: Brightness.dark,
        bg: AppColors.darkBackground,
        surface: AppColors.darkSurface,
        surfaceMuted: DbColors.darkSurfaceMuted,
        border: AppColors.darkBorderLight,
        ink: AppColors.darkTextPrimary,
        inkMuted: AppColors.darkTextSecondary,
      );
}
