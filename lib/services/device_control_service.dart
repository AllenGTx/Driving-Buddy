import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SpotifyPlaybackSnapshot {
  const SpotifyPlaybackSnapshot({
    required this.listenerGranted,
    required this.hasSession,
    required this.isPlaying,
    required this.isAd,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.positionMs,
    required this.artUri,
    required this.artHash,
    this.artBytes,
  });

  final bool listenerGranted;
  final bool hasSession;
  final bool isPlaying;
  final bool isAd;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final int positionMs;
  final String artUri;
  final String artHash;
  final Uint8List? artBytes;

  static SpotifyPlaybackSnapshot? fromMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) return null;
    Uint8List? decodedArt;
    final b64 = (raw['artBase64'] ?? '').toString();
    if (b64.isNotEmpty) {
      try {
        decodedArt = base64Decode(b64);
      } catch (_) {}
    }
    return SpotifyPlaybackSnapshot(
      listenerGranted: raw['listenerGranted'] == true,
      hasSession: raw['hasSession'] == true,
      isPlaying: raw['isPlaying'] == true,
      isAd: raw['isAd'] == true,
      title: (raw['title'] ?? '').toString().trim(),
      artist: (raw['artist'] ?? '').toString().trim(),
      album: (raw['album'] ?? '').toString().trim(),
      durationMs: (raw['durationMs'] as num?)?.toInt() ?? 0,
      positionMs: (raw['positionMs'] as num?)?.toInt() ?? 0,
      artUri: (raw['artUri'] ?? '').toString().trim(),
      artHash: (raw['artHash'] ?? '').toString().trim(),
      artBytes: decodedArt,
    );
  }
}

/// Jembatan native Android ringan untuk:
/// 1. Deteksi panggilan telepon / WhatsApp VoIP aktif (`AudioManager.mode`) tanpa izin privasi tambahan.
/// 2. Audio Ducking CarPlay (kecilkan musik Spotify ~25% saat Buddy bicara, pause penuh saat sirine darurat).
/// 3. Kontrol pemutaran Spotify (`MEDIA_PLAY_FROM_SEARCH` & tombol media Prev/Play-Pause/Next di background).
class DeviceControlService {
  DeviceControlService._();
  static final DeviceControlService instance = DeviceControlService._();

  static const MethodChannel _channel = MethodChannel(
    'com.drivingbuddy/device_control',
  );

  Future<bool> isInPhoneOrVoipCall() async {
    if (kIsWeb) return false;
    try {
      final res = await _channel.invokeMethod<bool>('isInPhoneOrVoipCall');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setAudioDucking({
    required bool enable,
    bool exclusive = false,
  }) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<bool>('setAudioDucking', {
        'enable': enable,
        'exclusive': exclusive,
      });
    } catch (_) {}
  }

  Future<bool> isSpotifyInstalled() async {
    if (kIsWeb) return false;
    try {
      final res = await _channel.invokeMethod<bool>('isSpotifyInstalled');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isSystemMusicActive() async {
    if (kIsWeb) return false;
    try {
      final res = await _channel.invokeMethod<bool>('isMusicActive');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendMediaCommand(String command) async {
    if (kIsWeb) return false;
    try {
      final res = await _channel.invokeMethod<bool>('sendMediaCommand', {
        'command': command,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String> playSpotifyQuery(
    String query, {
    String title = '',
    String artist = '',
  }) async {
    if (kIsWeb) return 'failed';
    try {
      final res = await _channel.invokeMethod<dynamic>('playSpotifyQuery', {
        'query': query,
        'title': title,
        'artist': artist,
      });
      if (res is String && res.isNotEmpty) return res;
      if (res == true) return 'ok';
      return 'failed';
    } catch (_) {
      return 'failed';
    }
  }

  Future<bool> isNotificationAccessGranted() async {
    if (kIsWeb) return false;
    try {
      final res = await _channel.invokeMethod<bool>('isNotificationAccessGranted');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openNotificationAccessSettings() async {
    if (kIsWeb) return false;
    try {
      final res = await _channel.invokeMethod<bool>('openNotificationAccessSettings');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openSpotifyApp() async {
    if (kIsWeb) return false;
    try {
      final res = await _channel.invokeMethod<bool>('openSpotifyApp');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<SpotifyPlaybackSnapshot?> getSpotifyPlaybackState({
    String lastArtHash = '',
  }) async {
    if (kIsWeb) return null;
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getSpotifyPlaybackState',
        {'lastArtHash': lastArtHash},
      );
      return SpotifyPlaybackSnapshot.fromMap(res);
    } catch (_) {
      return null;
    }
  }

  Future<bool> seekSpotify(int positionMs) async {
    if (kIsWeb) return false;
    try {
      final res = await _channel.invokeMethod<bool>('seekSpotify', {
        'positionMs': positionMs,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setDynamicIslandSessionActive(bool active) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<bool>('setDynamicIslandSessionActive', {
        'active': active,
      });
    } catch (_) {}
  }

  Future<bool> isDynamicIslandSessionActive() async {
    if (kIsWeb) return false;
    try {
      final res = await _channel.invokeMethod<bool>('isDynamicIslandSessionActive');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
