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

  /// Link halaman profil tempat di Google Maps.
  /// Membawa koordinat presisi agar Google Maps langsung menampilkan pin merah di lokasi aslinya.
  static Uri placePageUri(NearbyPlace place) {
    final coordStr = '${place.lat.toStringAsFixed(6)},${place.lng.toStringAsFixed(6)}';
    final query = place.name.isNotEmpty
        ? '$coordStr (${place.name})'
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

    // Fallback native geo
    final geoUri = Uri.parse('geo:$coordStr?q=$coordStr(${Uri.encodeComponent(place.name)})');
    try {
      if (await canLaunchUrl(geoUri)) {
        final opened = await (opener ?? _defaultOpener)(geoUri);
        if (opened) return true;
      }
    } catch (_) {}

    return _open(navigationUri(place), opener);
  }

  /// Buka detail / pin lokasi: coba Google Maps native (geo:) terlebih dahulu
  /// agar tidak membuka browser web yang rentan memunculkan layar putih kosong.
  static Future<bool> openPlacePage(NearbyPlace place, {UrlOpener? opener}) async {
    final coordStr = '${place.lat.toStringAsFixed(6)},${place.lng.toStringAsFixed(6)}';
    final nativeGeoUri = Uri.parse('geo:$coordStr?q=$coordStr(${Uri.encodeComponent(place.name)})');
    try {
      if (await canLaunchUrl(nativeGeoUri)) {
        final opened = await (opener ?? _defaultOpener)(nativeGeoUri);
        if (opened) return true;
      }
    } catch (_) {}

    return _open(placePageUri(place), opener);
  }

  /// Buka langsung via Browser Web (Google Maps via Chrome / Browser HP).
  /// Opsi utama untuk perangkat HUAWEI (tanpa Google Mobile Services / GMS)
  /// agar peta 100% akurat dan tidak dialihkan ke Petal Maps yang kurang presisi.
  static Future<bool> openInBrowser(NearbyPlace place, {bool isNavigation = true, UrlOpener? opener}) async {
    final uri = isNavigation ? navigationUri(place) : placePageUri(place);
    return _open(uri, opener);
  }

  /// Buka via aplikasi navigasi bawaan perangkat (Google Maps App atau Petal Maps).
  static Future<bool> openInNativeApp(NearbyPlace place, {bool isNavigation = true, UrlOpener? opener}) async {
    final coordStr = '${place.lat.toStringAsFixed(6)},${place.lng.toStringAsFixed(6)}';
    if (isNavigation) {
      final nativeNav = Uri.parse('google.navigation:q=$coordStr&mode=d');
      try {
        if (await canLaunchUrl(nativeNav)) {
          final opened = await (opener ?? _defaultOpener)(nativeNav);
          if (opened) return true;
        }
      } catch (_) {}
    }

    final nativeGeo = Uri.parse('geo:$coordStr?q=$coordStr(${Uri.encodeComponent(place.name)})');
    try {
      if (await canLaunchUrl(nativeGeo)) {
        final opened = await (opener ?? _defaultOpener)(nativeGeo);
        if (opened) return true;
      }
    } catch (_) {}

    // Fallback jika tidak ada app peta
    return _open(isNavigation ? navigationUri(place) : placePageUri(place), opener);
  }

  /// Buka pencarian Google Maps live via Browser Web (Chrome)
  static Future<bool> openLiveSearchInBrowser(String query, double? lat, double? lng, {UrlOpener? opener}) async {
    Uri uri;
    if (lat != null && lng != null) {
      final encodedQuery = Uri.encodeComponent(query);
      final latStr = lat.toStringAsFixed(6);
      final lngStr = lng.toStringAsFixed(6);
      uri = Uri.parse('https://www.google.com/maps/search/$encodedQuery/@$latStr,$lngStr,15z');
    } else {
      uri = Uri.https('www.google.com', '/maps/search/', <String, String>{
        'api': '1',
        'query': query,
      });
    }
    return _open(uri, opener);
  }

  /// Buka pencarian Google Maps live via Aplikasi Maps Bawaan
  static Future<bool> openLiveSearchInApp(String query, double? lat, double? lng, {UrlOpener? opener}) async {
    final nativeUri = (lat != null && lng != null)
        ? Uri.parse('geo:$lat,$lng?q=${Uri.encodeComponent(query)}')
        : Uri.parse('geo:0,0?q=${Uri.encodeComponent(query)}');
    try {
      if (await canLaunchUrl(nativeUri)) {
        final opened = await (opener ?? _defaultOpener)(nativeUri);
        if (opened) return true;
      }
    } catch (_) {}

    return openLiveSearchInBrowser(query, lat, lng, opener: opener);
  }

  static Future<bool> _open(Uri uri, UrlOpener? opener) async {
    try {
      return await (opener ?? _defaultOpener)(uri);
    } catch (_) {
      return false;
    }
  }
}
