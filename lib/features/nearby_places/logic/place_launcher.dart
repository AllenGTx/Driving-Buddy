import 'package:url_launcher/url_launcher.dart';

import '../models/nearby_place.dart';

// ============================================================================
// PELUNCUR — membuka Google Maps ke tempat yang dipilih.
// Tidak ada layar putih: navigasi selalu memakai koordinat valid lat,lng
// ============================================================================

/// Pembuka URL (diganti versi palsu di tes).
typedef UrlOpener = Future<bool> Function(Uri uri);

class PlaceLauncher {
  const PlaceLauncher._();

  static Future<bool> _defaultOpener(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Link navigasi mobil ke [place].
  /// Menggunakan format koordinat murni lat,lng pada parameter destination
  /// agar Google Maps tidak crash / tidak memunculkan layar putih kosong.
  static Uri navigationUri(NearbyPlace place) {
    final coordStr = '${place.lat.toStringAsFixed(6)},${place.lng.toStringAsFixed(6)}';
    return Uri.https('www.google.com', '/maps/dir/', <String, String>{
      'api': '1',
      'destination': coordStr,
      'travelmode': 'driving',
    });
  }

  /// Link halaman profil tempat di Google Maps (mencari nama bisnis dan alamat).
  static Uri placePageUri(NearbyPlace place) {
    final coordStr = '${place.lat.toStringAsFixed(6)},${place.lng.toStringAsFixed(6)}';
    final query = place.name.isNotEmpty
        ? (place.address.isNotEmpty
            ? '${place.name}, ${place.address}'
            : '${place.name}, Semarang')
        : coordStr;
    return Uri.https('www.google.com', '/maps/search/', <String, String>{
      'api': '1',
      'query': query,
    });
  }

  /// Buka navigasi: coba aplikasi Google Maps native dulu, fallback ke web.
  static Future<bool> navigate(NearbyPlace place, {UrlOpener? opener}) async {
    final coordStr = '${place.lat.toStringAsFixed(6)},${place.lng.toStringAsFixed(6)}';
    final nativeUri = Uri.parse('google.navigation:q=$coordStr&mode=d');
    try {
      if (await canLaunchUrl(nativeUri)) {
        final opened = await (opener ?? _defaultOpener)(nativeUri);
        if (opened) return true;
      }
    } catch (_) {}

    return _open(navigationUri(place), opener);
  }

  static Future<bool> openPlacePage(NearbyPlace place, {UrlOpener? opener}) async {
    return _open(placePageUri(place), opener);
  }

  static Future<bool> _open(Uri uri, UrlOpener? opener) async {
    try {
      return await (opener ?? _defaultOpener)(uri);
    } catch (_) {
      return false;
    }
  }
}
