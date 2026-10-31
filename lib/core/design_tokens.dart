import 'package:flutter/material.dart';

/// Design tokens "GT Copper": putih 60%, hitam/navy 30%, oranye 10%.
class DbColors {
  const DbColors._();

  static const Color orange = Color(0xFFF26B1D);
  static const Color orangePressed = Color(0xFFD9560F);
  static const Color orangeTint = Color(0xFFFFF1E8);

  static const Color ink = Color(0xFF0A0A0A);
  static const Color inkMuted = Color(0xFF5B6472);
  static const Color inkSubtle = Color(0xFF9AA3B2);

  static const Color navy = Color(0xFF0F1E3D);
  static const Color navySoft = Color(0xFF1A2B52);

  static const Color bg = Color(0xFFFFFFFF);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF5F6F8);
  static const Color surfaceAlt = Color(0xFFF8FAFC);
  static const Color border = Color(0xFFECEEF2);
  static const Color hairline = Color(0xFFECEEF2);

  static const Color darkBg = Color(0xFF0B0F17);
  static const Color darkSurface = Color(0xFF141A24);
  static const Color darkSurfaceMuted = Color(0xFF1B2230);
  static const Color darkBorder = Color(0xFF253042);

  static const Color danger = Color(0xFFE5383B);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
}

class DbSpace {
  const DbSpace._();
  static const double xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32;
}

class DbRadius {
  const DbRadius._();
  static const double r8 = 8, r10 = 10, r12 = 12, r14 = 14, r16 = 16, r18 = 18, r20 = 20;
  static const double input = 12, card = 20, pill = 999;
}

class DbMotion {
  const DbMotion._();
  static const Duration press = Duration(milliseconds: 120);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration base = Duration(milliseconds: 250);
  static const Duration ring = Duration(milliseconds: 900);
  static const Curve out = Curves.easeOutCubic;

  /// Hormati pengaturan "kurangi animasi" di Android.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;
}

class DbShadow {
  const DbShadow._();
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0F000000), blurRadius: 24, offset: Offset(0, 8)),
  ];
  static const List<BoxShadow> cardDark = [
    BoxShadow(color: Color(0x40000000), blurRadius: 16, offset: Offset(0, 4)),
  ];
}
