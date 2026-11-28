import 'package:flutter/material.dart';

/// Logo resmi Spotify (#1ED760 lingkaran hijau + 3 garis gelombang akustik melengkung presisi).
class SpotifyLogoMark extends StatelessWidget {
  const SpotifyLogoMark({
    super.key,
    this.size = 36,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SpotifyLogoPainter(),
      ),
    );
  }
}

class _SpotifyLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s * 0.5, s * 0.5);

    // Lingkaran resmi Spotify Green (#1ED760)
    canvas.drawCircle(
      c,
      s * 0.5,
      Paint()
        ..isAntiAlias = true
        ..color = const Color(0xFF1ED760),
    );

    final wavePaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF09090B);

    // Gelombang Atas (paling tebal & lebar)
    wavePaint.strokeWidth = s * 0.092;
    final topPath = Path()
      ..moveTo(s * 0.22, s * 0.36)
      ..quadraticBezierTo(s * 0.50, s * 0.26, s * 0.79, s * 0.39);
    canvas.drawPath(topPath, wavePaint);

    // Gelombang Tengah
    wavePaint.strokeWidth = s * 0.078;
    final midPath = Path()
      ..moveTo(s * 0.26, s * 0.52)
      ..quadraticBezierTo(s * 0.50, s * 0.44, s * 0.74, s * 0.55);
    canvas.drawPath(midPath, wavePaint);

    // Gelombang Bawah
    wavePaint.strokeWidth = s * 0.066;
    final botPath = Path()
      ..moveTo(s * 0.30, s * 0.67)
      ..quadraticBezierTo(s * 0.50, s * 0.61, s * 0.69, s * 0.69);
    canvas.drawPath(botPath, wavePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
