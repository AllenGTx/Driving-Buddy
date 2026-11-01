import 'dart:math' as math;

/// 2D Kinematic Kalman Filter untuk memperhalus koordinat GPS secara real-time.
///
/// Standar matematika yang digunakan pada GPS tracking industri (Garmin, Strava):
/// - Menjejak state posisi (x, y) dan kecepatan (vx, vy) dalam meter.
/// - Memanfaatkan akurasi estimasi sensor (accuracyM) sebagai measurement noise covariance R.
/// - Menolak lonjakan posisi mendadak (multipath spikes saat melewati jembatan/gedung tinggi).
class GpsKalmanFilter {
  GpsKalmanFilter({this.maxAccelerationMps2 = 3.5});

  /// Batas akselerasi fisik kendaraan (m/s^2) untuk process noise Q.
  final double maxAccelerationMps2;

  double? _refLat;
  double? _refLng;
  double? _lastTimestampSec;

  // State: [posisi (m), kecepatan (m/s)]
  final List<double> _x = [0.0, 0.0]; // Latitude axis
  final List<double> _y = [0.0, 0.0]; // Longitude axis

  // Matriks Kovariansi Error 2x2
  final List<List<double>> _covX = [
    [10.0, 0.0],
    [0.0, 10.0],
  ];
  final List<List<double>> _covY = [
    [10.0, 0.0],
    [0.0, 10.0],
  ];

  double? filteredLat;
  double? filteredLng;

  /// Reset state filter (misal saat monitoring baru dimulai).
  void reset() {
    _refLat = null;
    _refLng = null;
    _lastTimestampSec = null;
    _x[0] = 0.0;
    _x[1] = 0.0;
    _y[0] = 0.0;
    _y[1] = 0.0;
    _covX[0][0] = 10.0;
    _covX[0][1] = 0.0;
    _covX[1][0] = 0.0;
    _covX[1][1] = 10.0;
    _covY[0][0] = 10.0;
    _covY[0][1] = 0.0;
    _covY[1][0] = 0.0;
    _covY[1][1] = 10.0;
    filteredLat = null;
    filteredLng = null;
  }

  /// Masukkan koordinat mentah GPS dan dapatkan koordinat halus hasil estimasi Kalman.
  Map<String, double> process({
    required double rawLat,
    required double rawLng,
    required double? accuracyM,
    required DateTime timestamp,
  }) {
    final double timestampSec = timestamp.millisecondsSinceEpoch / 1000.0;

    // Titik awal inisialisasi jangkar referensi lokal
    if (_refLat == null || _refLng == null) {
      _refLat = rawLat;
      _refLng = rawLng;
      _lastTimestampSec = timestampSec;
      filteredLat = rawLat;
      filteredLng = rawLng;
      return {'lat': rawLat, 'lng': rawLng};
    }

    final double dt = timestampSec - (_lastTimestampSec ?? timestampSec);
    // Terlalu rapat (< 0.1s), abaikan agar tidak overfit
    if (dt < 0.1) {
      return {'lat': filteredLat ?? rawLat, 'lng': filteredLng ?? rawLng};
    }

    // Jika terjadi blackout / terowongan (> 10s), re-center filter ke koordinat baru
    if (dt > 10.0) {
      reset();
      _refLat = rawLat;
      _refLng = rawLng;
      _lastTimestampSec = timestampSec;
      filteredLat = rawLat;
      filteredLng = rawLng;
      return {'lat': rawLat, 'lng': rawLng};
    }

    _lastTimestampSec = timestampSec;

    // Konversi koordinat lat/lng menjadi meter lokal relative ke titik awal referensi
    const double metersPerDegreeLat = 111319.5;
    final double metersPerDegreeLng =
        111319.5 * math.cos(_refLat! * math.pi / 180.0);

    final double measX = (rawLat - _refLat!) * metersPerDegreeLat;
    final double measY = (rawLng - _refLng!) * metersPerDegreeLng;

    // Measurement noise R berbanding lurus dengan kuadrat akurasi GPS HP
    final double rawAcc = accuracyM ?? 8.0;
    final double effectiveAcc = rawAcc.clamp(3.0, 30.0);
    final double r = effectiveAcc * effectiveAcc;
    final double a = maxAccelerationMps2;

    // Filter secara independen pada sumbu X (Lat) dan sumbu Y (Lng)
    _filterDimension(_x, _covX, measX, dt, r, a);
    _filterDimension(_y, _covY, measY, dt, r, a);

    // Konversi kembali dari meter lokal ke derajat lat/lng
    final double outLat = _refLat! + (_x[0] / metersPerDegreeLat);
    final double outLng = _refLng! + (_y[0] / metersPerDegreeLng);

    filteredLat = outLat;
    filteredLng = outLng;

    return {'lat': outLat, 'lng': outLng};
  }

  void _filterDimension(
    List<double> state,
    List<List<double>> P,
    double z,
    double dt,
    double r,
    double a,
  ) {
    // 1. Predict
    final double xPred = state[0] + (state[1] * dt);
    final double vPred = state[1];

    final double a2 = a * a;
    final double dt2 = dt * dt;
    final double dt3 = dt2 * dt;
    final double dt4 = dt3 * dt;

    final double p00 =
        P[0][0] +
        dt * (P[1][0] + P[0][1]) +
        (dt2 * P[1][1]) +
        (0.25 * dt4 * a2);
    final double p01 = P[0][1] + (dt * P[1][1]) + (0.5 * dt3 * a2);
    final double p10 = P[1][0] + (dt * P[1][1]) + (0.5 * dt3 * a2);
    final double p11 = P[1][1] + (dt2 * a2);

    // 2. Update (Measurement Innovation & Kalman Gain)
    final double yInnov = z - xPred;
    final double s = p00 + r;
    final double k0 = p00 / s;
    final double k1 = p10 / s;

    state[0] = xPred + (k0 * yInnov);
    state[1] = vPred + (k1 * yInnov);

    P[0][0] = (1.0 - k0) * p00;
    P[0][1] = (1.0 - k0) * p01;
    P[1][0] = p10 - (k1 * p00);
    P[1][1] = p11 - (k1 * p01);
  }
}
