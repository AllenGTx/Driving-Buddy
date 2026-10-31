import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'services/firebase_service.dart';
import 'services/language_service.dart';
import 'features/nearby_places/nearby_places.dart';

// ─────────────────────────────────────────────
//  PALETTE
// ─────────────────────────────────────────────
const _orange = Color(0xFFF26B1D);
const _green = Color(0xFF10B981);
const _yellow = Color(0xFFF59E0B);
const _red = Color(0xFFEF4444);
const _blue = Color(0xFF3B82F6);
const _purple = Color(0xFF8B5CF6);
const _grey = Color(0xFF94A3B8);

// ─────────────────────────────────────────────
//  ACHIEVEMENT MODEL
// ─────────────────────────────────────────────
class Achievement {
  final String tag;
  final String emoji;
  final Color color;
  const Achievement(this.tag, this.emoji, this.color);
}

List<Achievement> computeAchievements({
  required int durationSeconds,
  required int drivingScore,
  required int totalMicrosleeps,
  required int totalDrowsy,
  required int totalYawns,
  required bool isFirstSession,
  DateTime? startedAt,
}) {
  final results = <Achievement>[];
  final h = startedAt?.hour ?? DateTime.now().hour;

  if (drivingScore >= 85 && totalMicrosleeps == 0) {
    results.add(Achievement(LanguageService.instance.s.alertDriverTag, '', _blue));
  }
  if (totalMicrosleeps == 0 && totalDrowsy == 0) {
    results.add(Achievement(LanguageService.instance.s.zeroFatigueTag, '', _green));
  }
  final isEn = LanguageService.instance.isEnglish;
  if (h >= 21 || h < 5) {
    results.add(Achievement(isEn ? '#NightDriver' : '#PengemudiMalam', '', _purple));
  } else if (h >= 5 && h < 8) {
    results.add(Achievement(isEn ? '#EarlyBird' : '#BangunPagi', '', _yellow));
  }
  if (isFirstSession) {
    results.add(Achievement(isEn ? '#FirstDrive' : '#PertamaBergerak', '', _orange));
  }

  if (results.isEmpty) {
    results.add(Achievement(LanguageService.instance.s.stayAlertTag, '', _orange));
  }

  return results.take(3).toList();
}

// ─────────────────────────────────────────────
//  SCORE RING PAINTER
// ─────────────────────────────────────────────
class _ScoreRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  _ScoreRingPainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = color
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ScoreRingPainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────
//  POLAROID MAP CARD (Centrally Framed Photo Aesthetic)
// ─────────────────────────────────────────────
class _PolaroidMapCard extends StatelessWidget {
  final double? centerLat;
  final double? centerLng;
  final double? startLat;
  final double? startLng;
  final List<Map<String, double>>? routePoints;

  const _PolaroidMapCard({
    this.centerLat,
    this.centerLng,
    this.startLat,
    this.startLng,
    this.routePoints,
  });



  /// Hitung zoom adaptif agar Start, Finish, dan seluruh rute muat sempurna di dalam frame Polaroid
  int _calculateAdaptiveZoom({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
  }) {
    final latDiff = (maxLat - minLat).abs();
    final lngDiff = (maxLng - minLng).abs();
    if (latDiff < 0.0001 && lngDiff < 0.0001) {
      return 16;
    }

    // Viewport card ~330px lebar, ~295px tinggi.
    // Beri batas 210px x 180px (margin 35%) agar badge Start & Finish tidak terpotong tepi layar.
    const double maxSpanX = 210.0;
    const double maxSpanY = 180.0;

    for (int z = 16; z >= 8; z--) {
      final n = (1 << z).toDouble();
      final spanX = (lngDiff / 360.0) * n * 256.0;

      double mercatorY(double deg) {
        final rad = deg.clamp(-85.0511, 85.0511) * math.pi / 180.0;
        return (1.0 - math.log(math.tan(rad) + 1.0 / math.cos(rad)) / math.pi) / 2.0 * n * 256.0;
      }

      final spanY = (mercatorY(minLat) - mercatorY(maxLat)).abs();

      if (spanX <= maxSpanX && spanY <= maxSpanY) {
        return z;
      }
    }
    return 8;
  }

  @override
  Widget build(BuildContext context) {
    // 1. Titik Finish (Destinasi Akhir Perjalanan)
    final fLat = centerLat ?? -6.2088;
    final fLng = centerLng ?? 106.8456;

    // 2. Titik Start (Awal Keberangkatan)
    double sLat = startLat ?? (routePoints != null && routePoints!.isNotEmpty ? routePoints!.first['lat']! : (fLat - 0.003));
    double sLng = startLng ?? (routePoints != null && routePoints!.isNotEmpty ? routePoints!.first['lng']! : (fLng - 0.003));

    // Jika start dan finish terlalu dekat / sama, beri offset visual agar kedua pin terlihat
    if ((sLat - fLat).abs() < 0.00005 && (sLng - fLng).abs() < 0.00005) {
      sLat = fLat - 0.0020;
      sLng = fLng - 0.0020;
    }

    // 3. Kumpulkan semua titik untuk kalkulasi Bounding Box
    final allPoints = <Map<String, double>>[
      {'lat': sLat, 'lng': sLng},
      {'lat': fLat, 'lng': fLng},
    ];
    if (routePoints != null && routePoints!.isNotEmpty) {
      for (final p in routePoints!) {
        final pLat = p['lat'];
        final pLng = p['lng'];
        if (pLat != null && pLng != null && (pLat != 0.0 || pLng != 0.0)) {
          allPoints.add({'lat': pLat, 'lng': pLng});
        }
      }
    }

    double minLat = allPoints.first['lat']!;
    double maxLat = allPoints.first['lat']!;
    double minLng = allPoints.first['lng']!;
    double maxLng = allPoints.first['lng']!;

    for (final p in allPoints) {
      final pLat = p['lat']!;
      final pLng = p['lng']!;
      if (pLat < minLat) minLat = pLat;
      if (pLat > maxLat) maxLat = pLat;
      if (pLng < minLng) minLng = pLng;
      if (pLng > maxLng) maxLng = pLng;
    }

    // 4. Titik tengah geografis sesungguhnya (Midpoint) agar rute tepat berada di tengah foto
    final mapCenterLat = (minLat + maxLat) / 2.0;
    final mapCenterLng = (minLng + maxLng) / 2.0;

    // 5. Kalkulasi zoom adaptif: dekat (zoom in 16), jauh/antar kota (zoom out 10-12)
    final zoom = _calculateAdaptiveZoom(
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFDFBF7), // Warm vintage polaroid paper
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Inner Photographic Map Window
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: AspectRatio(
              aspectRatio: 1.38,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Single High-Resolution Unified Tile Image (Pusat di Midpoint rute)
                    _buildTileMap(mapCenterLat, mapCenterLng, zoom),

                    // Atmospheric Vignette Overlay
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment.center,
                            radius: 0.95,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.12),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Strava-style Route Overlay (Start Pin, Finish Pin, & Glowing Polyline)
                    _buildStravaRouteOverlay(
                      mapCenterLat: mapCenterLat,
                      mapCenterLng: mapCenterLng,
                      sLat: sLat,
                      sLng: sLng,
                      fLat: fLat,
                      fLng: fLng,
                      z: zoom,
                    ),


                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Polaroid Bottom Caption Strip (Bebas Overflow)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_rounded, size: 12, color: _orange),
                      const SizedBox(width: 3.5),
                      Flexible(
                        child: Text(
                          '${fLat.toStringAsFixed(4)}, ${fLng.toStringAsFixed(4)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF64748B),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.gps_fixed_rounded, size: 11, color: _orange),
                    const SizedBox(width: 3.5),
                    Text(
                      LanguageService.instance.s.travelRoute,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
  }

  /// Peta OSM: susun tile 256px di sekitar koordinat sehingga titik posisi tepat di tengah.
  Widget _buildTileMap(double lat, double lng, int z) {
    final n = (1 << z).toDouble();
    final xf = (lng + 180.0) / 360.0 * n;
    final latRad = lat * math.pi / 180.0;
    final yf = (1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) / 2.0 * n;
    final x0 = xf.floor();
    final y0 = yf.floor();
    const ts = 256.0;
    const headers = {'User-Agent': 'DrivingBuddy/1.0 (com.drivingbuddy)'};

    return LayoutBuilder(builder: (context, c) {
      final cx = c.maxWidth / 2;
      final cy = c.maxHeight / 2;
      final tiles = <Widget>[];
      for (var dx = -2; dx <= 2; dx++) {
        for (var dy = -2; dy <= 2; dy++) {
          final tx = x0 + dx;
          final ty = y0 + dy;
          if (ty < 0 || ty >= n) continue;
          final wx = (((tx % n) + n) % n).toInt();
          tiles.add(Positioned(
            left: cx + (tx - xf) * ts,
            top: cy + (ty - yf) * ts,
            width: ts,
            height: ts,
            child: Image.network(
              'https://tile.openstreetmap.org/$z/$wx/$ty.png',
              headers: headers,
              fit: BoxFit.fill,
              errorBuilder: (c, e, s) => Image.network(
                'https://a.basemaps.cartocdn.com/rastertiles/voyager/$z/$wx/$ty.png',
                headers: headers,
                fit: BoxFit.fill,
                errorBuilder: (c, e, s) => const ColoredBox(color: Color(0xFFE2E8F0)),
              ),
            ),
          ));
        }
      }
      return ClipRect(
        child: Stack(children: [
          const Positioned.fill(child: ColoredBox(color: Color(0xFFE2E8F0))),
          ...tiles,
        ]),
      );
    });
  }

  /// Gambar rute ala Strava dengan Titik Start Hijau, Titik Finish Oranye, dan Garis Polyline GPS Asli
  Widget _buildStravaRouteOverlay({
    required double mapCenterLat,
    required double mapCenterLng,
    required double sLat,
    required double sLng,
    required double fLat,
    required double fLng,
    required int z,
  }) {
    final n = (1 << z).toDouble();
    final xf = (mapCenterLng + 180.0) / 360.0 * n;
    final latRad = mapCenterLat.clamp(-85.0511, 85.0511) * math.pi / 180.0;
    final yf = (1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) / 2.0 * n;
    const ts = 256.0;

    return LayoutBuilder(
      builder: (context, c) {
        final cx = c.maxWidth / 2;
        final cy = c.maxHeight / 2;

        Offset toPixel(double pLat, double pLng) {
          final px = (pLng + 180.0) / 360.0 * n;
          final pRad = pLat * math.pi / 180.0;
          final py = (1.0 - math.log(math.tan(pRad) + 1.0 / math.cos(pRad)) / math.pi) / 2.0 * n;
          return Offset(cx + (px - xf) * ts, cy + (py - yf) * ts);
        }

        final startP = toPixel(sLat, sLng);
        final finishP = toPixel(fLat, fLng);

        List<Offset> polylinePixels = [];
        if (routePoints != null && routePoints!.length >= 2) {
          polylinePixels = routePoints!
              .map((pt) => toPixel(pt['lat']!, pt['lng']!))
              .toList();
        }

        return Stack(
          children: [
            // Polyline Rute GPS (Mengikuti lekukan jalan jika ada data breadcrumbs)
            CustomPaint(
              size: Size(c.maxWidth, c.maxHeight),
              painter: _StravaRoutePainter(
                start: startP,
                finish: finishP,
                points: polylinePixels.isNotEmpty ? polylinePixels : null,
              ),
            ),

            // Titik Start (Hijau)
            Positioned(
              left: startP.dx - 14,
              top: startP.dy - 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flag_rounded, size: 9, color: Colors.white),
                    SizedBox(width: 2),
                    Text(
                      'START',
                      style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),

            // Titik Finish (Oranye / Navigasi Pin)
            Positioned(
              left: finishP.dx - 16,
              top: finishP.dy - 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF26B1D),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: const [
                        BoxShadow(color: Colors.black45, blurRadius: 5, offset: Offset(0, 2)),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sports_score_rounded, size: 10, color: Colors.white),
                        SizedBox(width: 2),
                        Text(
                          'FINISH',
                          style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StravaRoutePainter extends CustomPainter {
  final Offset start;
  final Offset finish;
  final List<Offset>? points;

  _StravaRoutePainter({required this.start, required this.finish, this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();

    if (points != null && points!.length >= 2) {
      // Gambar Polyline GPS Asli persis mengikuti kelokan jalan
      path.moveTo(points!.first.dx, points!.first.dy);
      for (int i = 1; i < points!.length; i++) {
        path.lineTo(points![i].dx, points![i].dy);
      }
    } else {
      // Fallback kurva natural jika data breadcrumbs belum terisi penuh
      path.moveTo(start.dx, start.dy);
      final midX = (start.dx + finish.dx) / 2 + 18;
      final midY = (start.dy + finish.dy) / 2 - 14;
      path.quadraticBezierTo(midX, midY, finish.dx, finish.dy);
    }

    // Glow luar
    final glowPaint = Paint()
      ..color = const Color(0xFFF97316).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, glowPaint);

    // Garis Utama Rute Oranye Strava
    final linePaint = Paint()
      ..color = const Color(0xFFF26B1D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    // Garis Tengah Putih Halus
    final innerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, innerPaint);
  }

  @override
  bool shouldRepaint(_StravaRoutePainter old) =>
      old.start != start || old.finish != finish || old.points != points;
}
// ─────────────────────────────────────────────
//  MAIN SCREEN
// ─────────────────────────────────────────────
class DrivingCardScreen extends StatefulWidget {
  final int durationSeconds;
  final int drivingScore;
  final int totalMicrosleeps;
  final int totalDrowsy;
  final int totalYawns;
  final double distanceKm;
  final double avgSpeedKmh;
  final double? maxSpeedKmh;
  final bool isFirstSession;
  final DateTime? startedAt;
  final String? sessionId;
  final double? lastLat;
  final double? lastLng;
  final double? startLat;
  final double? startLng;
  final List<Map<String, double>>? routePoints;

  const DrivingCardScreen({
    super.key,
    required this.durationSeconds,
    required this.drivingScore,
    required this.totalMicrosleeps,
    required this.totalDrowsy,
    required this.totalYawns,
    this.distanceKm = 0,
    this.avgSpeedKmh = 0,
    this.maxSpeedKmh,
    this.isFirstSession = false,
    this.startedAt,
    this.sessionId,
    this.lastLat,
    this.lastLng,
    this.startLat,
    this.startLng,
    this.routePoints,
  });

  @override
  State<DrivingCardScreen> createState() => _DrivingCardScreenState();
}

class _DrivingCardScreenState extends State<DrivingCardScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey _cardRepaintKey = GlobalKey();
  bool _isSharing = false;
  late final String _randomBg;
  late AnimationController _ctrl;
  late Animation<double> _scoreAnim;

  double? _resolvedStartLat;
  double? _resolvedStartLng;
  double? _resolvedLastLat;
  double? _resolvedLastLng;
  List<Map<String, double>>? _resolvedRoutePoints;

  static const List<String> _cardBackgrounds = [
    'assets/images/card_bg.png',
    'assets/images/CardBG0.jpg',
    'assets/images/CardBG1.jpg',
    'assets/images/CardBG2.jpg',
    'assets/images/CardBG3.jpg',
    'assets/images/CardBG4.jpg',
    'assets/images/CardBG5.jpg',
  ];

  @override
  void initState() {
    super.initState();
    _randomBg = _cardBackgrounds[math.Random().nextInt(_cardBackgrounds.length)];
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _scoreAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();

    _resolvedStartLat = widget.startLat;
    _resolvedStartLng = widget.startLng;
    _resolvedLastLat = widget.lastLat;
    _resolvedLastLng = widget.lastLng;
    _resolvedRoutePoints = widget.routePoints;

    _resolveGpsCoordinates();
  }

  Future<void> _resolveGpsCoordinates() async {
    // Ambil koordinat awal dari breadcrumbs jika startLat masih null
    if (_resolvedStartLat == null && _resolvedRoutePoints != null && _resolvedRoutePoints!.isNotEmpty) {
      _resolvedStartLat = _resolvedRoutePoints!.first['lat'];
      _resolvedStartLng = _resolvedRoutePoints!.first['lng'];
    }
    if (_resolvedLastLat == null && _resolvedRoutePoints != null && _resolvedRoutePoints!.isNotEmpty) {
      _resolvedLastLat = _resolvedRoutePoints!.last['lat'];
      _resolvedLastLng = _resolvedRoutePoints!.last['lng'];
    }

    // 1. Cek apakah koordinat sudah ada dan valid
    final hasValidLast = _resolvedLastLat != null && _resolvedLastLng != null &&
        (_resolvedLastLat! != -6.2088 || _resolvedLastLng! != 106.8456);
    final hasValidStart = _resolvedStartLat != null && _resolvedStartLng != null;

    if (hasValidLast && hasValidStart) {
      return;
    }

    // 2. Coba fetch koordinat dari Firestore session jika sessionId ada
    if (widget.sessionId != null && AuthService.isLoggedIn) {
      try {
        final uid = AuthService.currentUser?.uid;
        if (uid != null) {
          final doc = await firestore
              .collection('users')
              .doc(uid)
              .collection('sessions')
              .doc(widget.sessionId)
              .get();
          if (doc.exists && doc.data() != null) {
            final data = doc.data()!;
            final sLat = (data['startLat'] ?? data['start_lat']) as num?;
            final sLng = (data['startLng'] ?? data['start_lng']) as num?;
            final eLat = (data['endLat'] ?? data['end_lat'] ?? data['lastLat'] ?? data['last_lat']) as num?;
            final eLng = (data['endLng'] ?? data['end_lng'] ?? data['lastLng'] ?? data['last_lng']) as num?;
            List<Map<String, double>>? rPoints;
            if (data['routePoints'] is List) {
              rPoints = (data['routePoints'] as List)
                  .map((p) => {
                        'lat': ((p['lat'] ?? p['latitude']) as num).toDouble(),
                        'lng': ((p['lng'] ?? p['longitude']) as num).toDouble(),
                      })
                  .toList();
            }

            if (eLat != null && eLng != null) {
              if (mounted) {
                setState(() {
                  _resolvedStartLat = sLat?.toDouble();
                  _resolvedStartLng = sLng?.toDouble();
                  _resolvedLastLat = eLat.toDouble();
                  _resolvedLastLng = eLng.toDouble();
                  _resolvedRoutePoints = rPoints ?? _resolvedRoutePoints;
                });
                return;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('DrivingCard fetch session GPS error: ');
      }
    }

    // 3. Fallback: Ambil posisi GPS perangkat via GeolocatorLocationProvider (bekerja di Huawei / No-GMS)
    try {
      final provider = GeolocatorLocationProvider();
      final fix = await provider.currentFix(timeout: const Duration(seconds: 4));
      if (fix != null && fix.isValid && mounted) {
        setState(() {
          _resolvedLastLat = fix.lat;
          _resolvedLastLng = fix.lng;
          _resolvedStartLat ??= fix.lat - 0.0018;
          _resolvedStartLng ??= fix.lng - 0.0022;
        });
      }
    } catch (e) {
      debugPrint('GeolocatorLocationProvider currentFix in DrivingCard error: ');
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    if (totalSeconds < 60) return '$totalSeconds d';
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h}j ${m}m';
    if (s > 0) return '${m}m ${s}d';
    return '${m}m';
  }

  Color get _scoreColor {
    final s = widget.drivingScore;
    if (s >= 80) return _green;
    if (s >= 55) return _yellow;
    return _red;
  }

  String get _scoreLabel {
    final s = widget.drivingScore;
    final strings = LanguageService.instance.s;
    if (s >= 85) return strings.statusVerySafe;
    if (s >= 70) return strings.statusSafe;
    if (s >= 50) return strings.statusCaution;
    return strings.statusRest;
  }

  @override
  Widget build(BuildContext context) {
    final dt = widget.startedAt ?? DateTime.now();
    final hour = dt.hour;
    final minute = dt.minute;
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final timeStr = '${h12.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $ampm';
    final monthNamesId = ['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agu','Sep','Okt','Nov','Des'];
    final monthNamesEn = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final monthNames = LanguageService.instance.isEnglish ? monthNamesEn : monthNamesId;
    final dateStr = '${dt.day} ${monthNames[dt.month - 1]} ${dt.year}';

    final achievements = computeAchievements(
      durationSeconds: widget.durationSeconds,
      drivingScore: widget.drivingScore,
      totalMicrosleeps: widget.totalMicrosleeps,
      totalDrowsy: widget.totalDrowsy,
      totalYawns: widget.totalYawns,
      isFirstSession: widget.isFirstSession,
      startedAt: widget.startedAt,
    );

    // Structured metrics with unified values and units
    final s = LanguageService.instance.s;
    String durVal;
    String durUnit;
    if (widget.durationSeconds < 60) {
      durVal = '${widget.durationSeconds}';
      durUnit = s.secShort;
    } else {
      final h = widget.durationSeconds ~/ 3600;
      final m = (widget.durationSeconds % 3600) ~/ 60;
      final sec = widget.durationSeconds % 60;
      if (h > 0) {
        durVal = '$h${s.hourShort} $m${s.minShort}';
        durUnit = '';
      } else if (sec > 0) {
        durVal = '$m${s.minShort} $sec${s.secShort}';
        durUnit = '';
      } else {
        durVal = '$m';
        durUnit = s.minShort;
      }
    }
    final distVal = widget.distanceKm > 0 ? widget.distanceKm.toStringAsFixed(2) : '0.00';
    final distUnit = s.distUnit;
    final speedVal = widget.avgSpeedKmh > 0 ? widget.avgSpeedKmh.toStringAsFixed(0) : '0';
    final speedUnit = s.speedUnit;
    final double realTopSpeed = (widget.maxSpeedKmh != null && widget.maxSpeedKmh! > 0)
        ? widget.maxSpeedKmh!
        : (widget.avgSpeedKmh > 0 ? widget.avgSpeedKmh * 1.15 : 0.0);
    final topSpeedVal = realTopSpeed > 0 ? realTopSpeed.toStringAsFixed(0) : '0';
    final topSpeedUnit = s.speedUnit;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // Background photo
          Positioned.fill(
            child: Image.asset(
              _randomBg,
              fit: BoxFit.cover,
            ),
          ),

          // Deep gradient overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.65),
                    Colors.black.withValues(alpha: 0.40),
                    Colors.black.withValues(alpha: 0.90),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top App Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _CircleIconButton(
                        icon: Icons.close_rounded,
                        onTap: () => Navigator.pop(context),
                      ),
                      const Text(
                        'Kartu Berkendara',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                      _CircleIconButton(
                        icon: Icons.ios_share_rounded,
                        onTap: _onShare,
                      ),
                    ],
                  ),
                ),

                // Center Scroll Content with Max Constraint (Prevents Full-screen Stretch on Web)
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                        child: Column(
                          children: [
                            RepaintBoundary(
                              key: _cardRepaintKey,
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.45),
                                      blurRadius: 18,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                            // ── HEADER: Logo + Time/Date (Compact Luxury) ──
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SizedBox(
                                  height: 36,
                                  width: 100,
                                  child: Image.asset(
                                    'assets/images/DrivingBuddyLogo_white_tight.png',
                                    fit: BoxFit.contain,
                                    alignment: Alignment.centerLeft,
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      timeStr,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w900,
                                        fontStyle: FontStyle.italic,
                                        color: _orange,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                    Text(
                                      dateStr,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white70,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // ── POLAROID MAP PHOTO CARD ────────────────
                            _PolaroidMapCard(
                              centerLat: _resolvedLastLat ?? widget.lastLat,
                              centerLng: _resolvedLastLng ?? widget.lastLng,
                              startLat: _resolvedStartLat ?? widget.startLat,
                              startLng: _resolvedStartLng ?? widget.startLng,
                              routePoints: _resolvedRoutePoints ?? widget.routePoints,
                            ),
                            const SizedBox(height: 10),

                            // ── METRIC STATS ROW (4 Kolom Termasuk Top Speed) ────
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B).withValues(alpha: 0.88),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _buildMetric(
                                      label: LanguageService.instance.s.duration.toUpperCase(),
                                      value: durVal,
                                      unit: durUnit,
                                      icon: Icons.timer_outlined,
                                    ),
                                  ),
                                  Container(height: 26, width: 1, color: Colors.white.withValues(alpha: 0.12)),
                                  Expanded(
                                    child: _buildMetric(
                                      label: LanguageService.instance.s.distance.toUpperCase(),
                                      value: distVal,
                                      unit: distUnit,
                                      icon: Icons.alt_route_rounded,
                                    ),
                                  ),
                                  Container(height: 26, width: 1, color: Colors.white.withValues(alpha: 0.12)),
                                  Expanded(
                                    child: _buildMetric(
                                      label: LanguageService.instance.s.avgSpeed.toUpperCase(),
                                      value: speedVal,
                                      unit: speedUnit,
                                      icon: Icons.speed_rounded,
                                    ),
                                  ),
                                  Container(height: 26, width: 1, color: Colors.white.withValues(alpha: 0.12)),
                                  Expanded(
                                    child: _buildMetric(
                                      label: LanguageService.instance.s.topSpeed.toUpperCase(),
                                      value: topSpeedVal,
                                      unit: topSpeedUnit,
                                      icon: Icons.electric_bolt_rounded,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),

                            // ── SCORE & PENCAPAIAN ROW (Compact Luxury) ───
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B).withValues(alpha: 0.88),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                              ),
                              child: Row(
                                children: [
                                  // Score Ring Dial (Clean & Bebas Nabrak)
                                  AnimatedBuilder(
                                    animation: _scoreAnim,
                                    builder: (context, child) {
                                      final progress = _scoreAnim.value * widget.drivingScore / 100;
                                      return Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 52,
                                            height: 52,
                                            child: Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                CustomPaint(
                                                  size: const Size(52, 52),
                                                  painter: _ScoreRingPainter(progress, _scoreColor),
                                                ),
                                                Text(
                                                  '${(widget.drivingScore * _scoreAnim.value).round()}',
                                                  style: TextStyle(
                                                    color: _scoreColor,
                                                    fontSize: 13.5,
                                                    fontWeight: FontWeight.w900,
                                                    height: 1.0,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: _scoreColor.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(5),
                                              border: Border.all(
                                                color: _scoreColor.withValues(alpha: 0.35),
                                              ),
                                            ),
                                            child: Text(
                                              _scoreLabel,
                                              style: TextStyle(
                                                color: _scoreColor,
                                                fontSize: 7,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 10),

                                  // Achievements List
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          LanguageService.instance.s.driverAchievement,
                                          style: TextStyle(
                                            fontSize: 8,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.6,
                                            color: _grey,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Wrap(
                                          spacing: 4,
                                          runSpacing: 3,
                                          children: achievements.map((a) => _BadgeChip(a)).toList(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),

                            // ── INCIDENT METRICS (3 Telemetry Cards) ────
                            Row(
                              children: [
                                Expanded(
                                  child: _buildTelemetryCard(
                                    icon: Icons.bedtime_outlined,
                                    value: '${widget.totalMicrosleeps}x',
                                    label: LanguageService.instance.s.microsleep,
                                    color: widget.totalMicrosleeps == 0 ? _green : _red,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildTelemetryCard(
                                    icon: Icons.warning_amber_rounded,
                                    value: '${widget.totalDrowsy}x',
                                    label: LanguageService.instance.s.drowsy,
                                    color: widget.totalDrowsy == 0 ? _green : _yellow,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildTelemetryCard(
                                    icon: Icons.air_rounded,
                                    value: '${widget.totalYawns}x',
                                    label: LanguageService.instance.s.yawn,
                                    color: widget.totalYawns <= 2 ? _green : _orange,
                                  ),
                                ),
                              ],
                            ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // ── SHARE BUTTON ───────────────────────────
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: ElevatedButton.icon(
                                onPressed: _onShare,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _orange,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 4,
                                  shadowColor: _orange.withValues(alpha: 0.4),
                                ),
                                icon: const Icon(Icons.share_rounded, size: 18),
                                label: Text(
                                  LanguageService.instance.s.shareDrivingCard,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetric({
    required String label,
    required String value,
    String unit = '',
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 9, color: _grey),
                const SizedBox(width: 2.5),
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 7.5,
                    fontWeight: FontWeight.w700,
                    color: _grey,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2.5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: _orange,
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 2),
                  Text(
                    unit,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: _orange.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: const TextStyle(
              color: _grey,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onShare() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);

    final isEn = LanguageService.instance.isEnglish;
    final shareText = isEn
        ? '🚗 Driving session completed with Driving Buddy!\n'
          '⏱ Duration: ${_formatDuration(widget.durationSeconds)}\n'
          '🏆 Safety Score: ${widget.drivingScore}/100 — $_scoreLabel\n'
          '😴 Microsleep: ${widget.totalMicrosleeps}x | Drowsy: ${widget.totalDrowsy}x | Yawn: ${widget.totalYawns}x\n\n'
          'Stay focused and prioritize driving safety with DrivingBuddy!'
        : '🚗 Sesi berkendara bersama Driving Buddy selesai!\n'
          '⏱ Waktu: ${_formatDuration(widget.durationSeconds)}\n'
          '🏆 Skor Keselamatan: ${widget.drivingScore}/100 — $_scoreLabel\n'
          '😴 Microsleep: ${widget.totalMicrosleeps}x | Kantuk: ${widget.totalDrowsy}x | Menguap: ${widget.totalYawns}x\n\n'
          'Tetap fokus dan utamakan keselamatan berkendara dengan DrivingBuddy!';

    try {
      final boundary = _cardRepaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final ui.Image image = await boundary.toImage(pixelRatio: 2.5);
        final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final tempDir = await getTemporaryDirectory();
          final file = File('${tempDir.path}/kartu_berkendara_${DateTime.now().millisecondsSinceEpoch}.png');
          await file.writeAsBytes(byteData.buffer.asUint8List());

          await Share.shareXFiles(
            [XFile(file.path)],
            text: shareText,
          );
          if (mounted) setState(() => _isSharing = false);
          return;
        }
      }
    } catch (e) {
      debugPrint('Error export kartu berkendara image: $e');
    }

    // Fallback share teks jika render gambar gagal
    await Share.share(shareText);
    if (mounted) setState(() => _isSharing = false);
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final Achievement a;
  const _BadgeChip(this.a);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: a.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: a.color.withValues(alpha: 0.45), width: 1),
      ),
      child: Text(
        a.tag,
        style: TextStyle(
          color: a.color,
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
