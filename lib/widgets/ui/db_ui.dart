import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/design_tokens.dart';

/// Membungkus widget apa pun agar mengecil sedikit saat ditekan + haptic ringan.
class DbPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  const DbPressable({super.key, required this.child, this.onTap, this.pressedScale = 0.97});

  @override
  State<DbPressable> createState() => _DbPressableState();
}

class _DbPressableState extends State<DbPressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1,
        duration: DbMotion.of(context, DbMotion.press),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Ring skor yang mengisi dari 0 ke nilai (gaya Apple Activity).
class DbScoreRing extends StatelessWidget {
  final int score;
  final double size;
  final double stroke;
  final Color? trackColor;
  final Color? textColor;
  final String? caption;

  const DbScoreRing({
    super.key,
    required this.score,
    this.size = 120,
    this.stroke = 10,
    this.trackColor,
    this.textColor,
    this.caption,
  });

  static Color colorFor(int s) =>
      s >= 80 ? DbColors.success : (s >= 60 ? DbColors.warning : DbColors.danger);

  @override
  Widget build(BuildContext context) {
    final target = (score.clamp(0, 100)) / 100.0;
    final color = colorFor(score);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: target),
      duration: DbMotion.of(context, DbMotion.ring),
      curve: DbMotion.out,
      builder: (context, v, _) {
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: v,
                  strokeWidth: stroke,
                  strokeCap: StrokeCap.round,
                  color: color,
                  backgroundColor: trackColor ?? color.withValues(alpha: 0.15),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(v * 100).round()}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: size * 0.3,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      color: textColor ?? DbColors.ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (caption != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        caption!,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: (textColor ?? DbColors.ink).withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Kartu standar: putih, radius 20, border tipis, bayangan halus.
class DbCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  const DbCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? (dark ? DbColors.darkSurface : DbColors.bg),
        borderRadius: BorderRadius.circular(DbRadius.card),
        border: Border.all(color: dark ? DbColors.darkBorder : DbColors.border),
        boxShadow: dark ? null : DbShadow.card,
      ),
      child: child,
    );
  }
}
