import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../features/nearby_places/logic/geo_math.dart';

/// Layanan Map Matching berbasis Open Source Routing Machine (OSRM) 100% Gratis & Open-Source.
///
/// Mengambil koordinat GPS mentah (breadcrumbs) yang bergelombang dan
/// "menempelkannya" (snap-to-roads) tepat di garis tengah jalan aspal
/// OpenStreetMap, persis seperti yang dilakukan Waze, Strava, dan Google Maps.
class RoadMatchingService {
  RoadMatchingService._();

  static const String _osrmMatchUrl =
      'https://router.project-osrm.org/match/v1/driving/';
  static const String _osrmRouteUrl =
      'https://router.project-osrm.org/route/v1/driving/';
  static const Duration _timeout = Duration(seconds: 4);
  static const Map<String, String> _headers = {
    'User-Agent': 'DrivingBuddy/1.0 (com.drivingbuddy)',
    'Accept': 'application/json',
  };

  /// Mengubah kumpulan koordinat mentah GPS menjadi rute yang
  /// menempel 100% presisi di garis tengah jalan raya.
  ///
  /// Otomatis graceful fallback ke [rawPoints] jika sedang offline, timeout, atau sinyal lemah.
  static Future<List<Map<String, double>>> snapToRoads(
    List<Map<String, double>> rawPoints,
  ) async {
    if (rawPoints.length < 2) return rawPoints;

    try {
      // 1. Bersihkan & Downsample titik agar tidak melebihi kapasitas URL HTTP GET (~60-75 titik optimal)
      final sampledPoints = _downsamplePoints(
        rawPoints,
        maxPoints: 75,
        minSpacingM: 10.0,
      );
      if (sampledPoints.length < 2) return rawPoints;

      // 2. Format koordinat untuk OSRM: {lng},{lat};{lng},{lat}
      final coordsParam = sampledPoints
          .map(
            (p) =>
                '${p['lng']!.toStringAsFixed(6)},${p['lat']!.toStringAsFixed(6)}',
          )
          .join(';');

      // 3. Coba Endpoint Utama: OSRM Map Matching (/match)
      // radiuses=45: toleransi simpangan GPS melenceng hingga 45m dari garis jalan
      // gaps=ignore: jika ada celah GPS hilang, tetap sambungkan rute jalan raya
      final radiusesParam = List.filled(sampledPoints.length, '45').join(';');
      final matchUri = Uri.parse(
        '$_osrmMatchUrl$coordsParam?overview=full&geometries=geojson&radiuses=$radiusesParam&gaps=ignore&tidy=true',
      );

      final matchResponse = await http
          .get(matchUri, headers: _headers)
          .timeout(_timeout);

      if (matchResponse.statusCode == 200) {
        final data = jsonDecode(matchResponse.body) as Map<String, dynamic>;
        if (data['code'] == 'Ok' &&
            data['matchings'] is List &&
            (data['matchings'] as List).isNotEmpty) {
          final List<Map<String, double>> result = [];
          for (final m in data['matchings']) {
            final geom = m['geometry'];
            if (geom != null && geom['coordinates'] is List) {
              for (final coord in geom['coordinates']) {
                if (coord is List && coord.length >= 2) {
                  final double lng = (coord[0] as num).toDouble();
                  final double lat = (coord[1] as num).toDouble();
                  result.add({'lat': lat, 'lng': lng});
                }
              }
            }
          }
          if (result.length >= 2) {
            debugPrint(
              '[RoadMatching] Sukses snap-to-road via /match (${result.length} titik jalan presisi)',
            );
            return result;
          }
        }
      }

      // 4. Fallback: OSRM Routing (/route) jika /match mengembalikan NoMatch
      final routeUri = Uri.parse(
        '$_osrmRouteUrl$coordsParam?overview=full&geometries=geojson',
      );
      final routeResponse = await http
          .get(routeUri, headers: _headers)
          .timeout(_timeout);

      if (routeResponse.statusCode == 200) {
        final data = jsonDecode(routeResponse.body) as Map<String, dynamic>;
        if (data['code'] == 'Ok' &&
            data['routes'] is List &&
            (data['routes'] as List).isNotEmpty) {
          final geom = data['routes'][0]['geometry'];
          if (geom != null && geom['coordinates'] is List) {
            final List<Map<String, double>> result = [];
            for (final coord in geom['coordinates']) {
              if (coord is List && coord.length >= 2) {
                final double lng = (coord[0] as num).toDouble();
                final double lat = (coord[1] as num).toDouble();
                result.add({'lat': lat, 'lng': lng});
              }
            }
            if (result.length >= 2) {
              debugPrint(
                '[RoadMatching] Sukses snap-to-road via /route fallback (${result.length} titik jalan)',
              );
              return result;
            }
          }
        }
      }
    } catch (e) {
      debugPrint(
        '[RoadMatching] Gagal snap-to-road (aman fallback ke GPS asli): $e',
      );
    }

    // Jika gagal / offline, kembalikan titik asli tanpa membuat aplikasi error
    return rawPoints;
  }

  /// Algoritma Ramer-Douglas-Peucker (RDP): Menyederhanakan polyline GPS dengan membuang
  /// titik-titik redundan saat jalan lurus atau berhenti di lampu merah,
  /// tanpa merusak bentuk lekukan tikungan asli rute.
  static List<Map<String, double>> simplifyRdp(
    List<Map<String, double>> points, {
    double epsilonMeters = 2.5,
  }) {
    if (points.length < 3) return points;

    double dMax = 0.0;
    int index = 0;
    final int end = points.length - 1;

    for (int i = 1; i < end; i++) {
      final d = _perpendicularDistanceM(points[i], points.first, points.last);
      if (d > dMax) {
        index = i;
        dMax = d;
      }
    }

    if (dMax > epsilonMeters) {
      final rec1 = simplifyRdp(
        points.sublist(0, index + 1),
        epsilonMeters: epsilonMeters,
      );
      final rec2 = simplifyRdp(
        points.sublist(index),
        epsilonMeters: epsilonMeters,
      );
      return [...rec1.sublist(0, rec1.length - 1), ...rec2];
    } else {
      return [points.first, points.last];
    }
  }

  static double _perpendicularDistanceM(
    Map<String, double> pt,
    Map<String, double> lineStart,
    Map<String, double> lineEnd,
  ) {
    final x0 = pt['lat']!;
    final y0 = pt['lng']!;
    final x1 = lineStart['lat']!;
    final y1 = lineStart['lng']!;
    final x2 = lineEnd['lat']!;
    final y2 = lineEnd['lng']!;

    final dx = x2 - x1;
    final dy = y2 - y1;

    if (dx == 0 && dy == 0) {
      return haversineM(x0, y0, x1, y1);
    }

    final numerator = (dy * x0 - dx * y0 + x2 * y1 - y2 * x1).abs();
    final denominator = math.sqrt(dx * dx + dy * dy);

    // 1 derajat lat ~ 111,319.5 meter
    return (numerator / denominator) * 111319.5;
  }

  /// Downsample list koordinat agar tidak melebihi kapasitas URL GET OSRM,
  /// dengan tetap mempertahankan titik Start, Finish, dan tikungan rute.
  static List<Map<String, double>> _downsamplePoints(
    List<Map<String, double>> points, {
    required int maxPoints,
    required double minSpacingM,
  }) {
    // 1. Bersihkan titik redundan dengan Ramer-Douglas-Peucker (RDP) terlebih dahulu
    final cleaned = simplifyRdp(points, epsilonMeters: 2.0);
    if (cleaned.length <= maxPoints) {
      return cleaned;
    }

    final List<Map<String, double>> sampled = [];
    sampled.add(cleaned.first);

    // Filter berdasarkan jarak minimum dari titik terakhir yang diambil
    for (int i = 1; i < cleaned.length - 1; i++) {
      final last = sampled.last;
      final current = cleaned[i];
      final dist = haversineM(
        last['lat']!,
        last['lng']!,
        current['lat']!,
        current['lng']!,
      );
      if (dist >= minSpacingM) {
        sampled.add(current);
      }
    }

    // Jika setelah filter jarak masih melebihi maxPoints, ambil dengan stride rata
    if (sampled.length > maxPoints) {
      final stride = (sampled.length / (maxPoints - 1)).ceil();
      final List<Map<String, double>> strided = [];
      for (int i = 0; i < sampled.length - 1; i += stride) {
        strided.add(sampled[i]);
      }
      strided.add(cleaned.last);
      return strided;
    }

    // Pastikan titik Finish selalu ada di ujung
    if (sampled.last != cleaned.last) {
      sampled.add(cleaned.last);
    }

    return sampled;
  }
}
