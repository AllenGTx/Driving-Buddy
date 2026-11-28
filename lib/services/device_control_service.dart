import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

  Future<bool> playSpotifyQuery(String query) async {
    if (kIsWeb) return false;
    try {
      final res = await _channel.invokeMethod<bool>('playSpotifyQuery', {
        'query': query,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
