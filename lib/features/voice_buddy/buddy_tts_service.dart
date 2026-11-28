import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../services/device_control_service.dart';
import '../../services/language_service.dart';
import '../llm_chat/llm_chat_config.dart';
import '../spotify_island/spotify_island_controller.dart';
import 'buddy_voice_config.dart';

enum _CloudTtsStatus {
  played,
  exhausted503,
  networkError,
}

class BuddyTtsService {
  BuddyTtsService({http.Client? httpClient})
    : _http = httpClient ?? http.Client(),
      _ownsHttp = httpClient == null;

  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();
  final http.Client _http;
  final bool _ownsHttp;
  final math.Random _rng = math.Random();

  final ValueNotifier<double> speechEnergy = ValueNotifier<double>(0.0);
  final ValueNotifier<double> speechFrequency = ValueNotifier<double>(0.45);
  final ValueNotifier<bool> isSpeaking = ValueNotifier<bool>(false);

  Timer? _envelopeTimer;
  Completer<void>? _activeSpeak;
  Completer<void>? _nativeSpeakDone;
  bool _initialized = false;
  bool _nativeBusy = false;
  bool _cancelled = false;
  String _resolvedIdLocale = 'id-ID';

  static const String furinaTiredText =
      'Maaf ya... Furina lagi capek nih, butuh istirahat. Mungkin kamu mau bicara sama Jane?';
  static const String furinaTiredAsset = 'audio/furina/tired.wav';

  static const List<(String, String)> _furinaWakeReplies = [
    ('audio/furina/wake_1.wav', 'Ya? Ada apa?'),
    ('audio/furina/wake_2.wav', 'Ya? Mau tanya apa?'),
    ('audio/furina/wake_3.wav', 'Ya? Gimana sayang...?'),
  ];

  static const List<(String, String)> _janeWakeReplies = [
    ('audio/jane/wake_1.wav', 'Ya? Ada yang bisa Jane bantu?'),
    ('audio/jane/wake_2.wav', 'Halo! Mau tanya apa nih?'),
    ('audio/jane/wake_3.wav', 'Iya, Jane dengerin kok!'),
  ];

  static const List<(String, String)> _johnWakeReplies = [
    ('audio/john/wake_1.wav', 'Ya bro? Ada yang bisa John bantu?'),
    ('audio/john/wake_2.wav', 'Siap! Mau tanya apa nih?'),
    ('audio/john/wake_3.wav', 'Iya bro, John dengerin!'),
  ];

  static String offlineSignalTextFor(BuddyVoiceProfile profile, {bool isEnglish = false}) {
    if (isEnglish) {
      return 'Internet signal is currently lost, but I am still right here watching your alertness on the road!';
    }
    return switch (profile) {
      BuddyVoiceProfile.furina =>
        'Eh, sinyalnya lagi putus nih... Tapi tenang ya, Rina tetap di sini jagain kamu menyetir kok!',
      BuddyVoiceProfile.john =>
        'Waduh, sinyal internet lagi hilang nih bro... Tenang aja, sensor keselamatan tetap aktif jagain kamu!',
      BuddyVoiceProfile.jane =>
        'Wah, sinyal internet lagi putus nih... Tapi tenang, Jane tetap siaga jagain mata kamu di jalan ya!',
    };
  }

  static String offlineSignalAssetFor(BuddyVoiceProfile profile) {
    return 'audio/${profile.name}/offline_signal.wav';
  }

  List<(String, String)> _wakePoolFor(BuddyVoiceProfile p) {
    return switch (p) {
      BuddyVoiceProfile.furina => _furinaWakeReplies,
      BuddyVoiceProfile.john => _johnWakeReplies,
      BuddyVoiceProfile.jane => _janeWakeReplies,
    };
  }

  List<(String, String)> _drowsyPoolFor(BuddyVoiceProfile p, {required int yawnCount}) {
    final folder = p.name;
    if (yawnCount >= 2) {
      return [
        (
          'audio/$folder/drowsy_yawn.wav',
          switch (p) {
            BuddyVoiceProfile.john =>
              'Eh bro, kamu udah menguap dua kali nih dalam lima menit! Kalau ngantuk, menepi dulu sebentar ya.',
            _ =>
              'Eh, kamu sudah menguap dua kali nih dalam lima menit! Kalau mulai ngantuk, menepi sebentar ya.',
          },
        ),
      ];
    }
    return [
      (
        'audio/$folder/drowsy_eyes.wav',
        switch (p) {
          BuddyVoiceProfile.furina => 'Aduh, mengantuk ya? Coba cari tempat istirahat ya.',
          BuddyVoiceProfile.john =>
            'Waduh, mata kamu mulai sayu tuh... Coba cari rest area terdekat dulu yuk!',
          BuddyVoiceProfile.jane =>
            'Aduh, matamu mulai kelihatan sayu nih... Yuk cari tempat istirahat sebentar ya!',
        },
      ),
      (
        'audio/$folder/drowsy_general.wav',
        switch (p) {
          BuddyVoiceProfile.john =>
            'Kelihatannya kamu mulai capek nyetir nih. Istirahat sebentar yuk biar fokus lagi!',
          _ =>
            'Kamu kelihatan mulai lelah di jalan. Yuk istirahat sebentar biar segar lagi!',
        },
      ),
    ];
  }

  Future<void> _ensureInit() async {
    if (_initialized) return;
    _initialized = true;
    _player.onPlayerComplete.listen((_) => _finishActive());

    try {
      _tts.setStartHandler(() {
        _nativeBusy = true;
      });
      _tts.setCompletionHandler(() {
        _nativeBusy = false;
        _finishNative();
      });
      _tts.setCancelHandler(() {
        _nativeBusy = false;
        _finishNative();
      });
      _tts.setErrorHandler((_) {
        _nativeBusy = false;
        _finishNative();
      });

      await _tts.setVolume(1.0);

      bool idOk = false;
      try {
        final avail = await _tts.isLanguageAvailable('id-ID');
        idOk = avail == true || avail == 1 || avail == 0;
      } catch (_) {}
      if (idOk) {
        _resolvedIdLocale = 'id-ID';
      } else {
        try {
          final inAvail = await _tts.isLanguageAvailable('in-ID');
          if (inAvail == true || inAvail == 1 || inAvail == 0) {
            _resolvedIdLocale = 'in-ID';
          }
        } catch (_) {}
      }
      await _tts.setLanguage(_resolvedIdLocale);
    } catch (_) {}
  }

  /// Hangatkan engine audio & TTS saat aplikasi dibuka agar panggilan pertama langsung responsif.
  Future<void> warmUp() => _ensureInit();

  String pickWakeAckText([BuddyVoiceProfile? profile]) {
    final p = profile ?? BuddyVoiceConfig.instance.profile;
    final isEn = LanguageService.instance.isEnglish;
    if (isEn && p != BuddyVoiceProfile.furina) {
      return p == BuddyVoiceProfile.john
          ? 'Yes? How can John help?'
          : 'Hi! What can Jane help you with?';
    }
    final pool = _wakePoolFor(p);
    return pool[_rng.nextInt(pool.length)].$2;
  }

  Future<void> speakWakeAck(
    BuddyVoiceProfile profile, {
    String? chosenText,
    VoidCallback? onPlaybackStart,
  }) async {
    final isEn = LanguageService.instance.isEnglish;
    if (!isEn || profile == BuddyVoiceProfile.furina) {
      final pool = _wakePoolFor(profile);
      final pick = chosenText != null
          ? pool.firstWhere((e) => e.$2 == chosenText, orElse: () => pool[0])
          : pool[_rng.nextInt(pool.length)];
      await _speakLocalAssetImmediate(
        assetRelPath: pick.$1,
        text: pick.$2,
        profile: profile,
        onPlaybackStart: onPlaybackStart,
      );
      return;
    }
    final text = chosenText ?? pickWakeAckText(profile);
    await _speakWithAssetOrDynamic(
      profile: profile,
      text: text,
      onPlaybackStart: onPlaybackStart,
    );
  }

  String pickDrowsyReminderText({
    required int yawnCount,
    BuddyVoiceProfile? profile,
  }) {
    final p = profile ?? BuddyVoiceConfig.instance.profile;
    final pool = _drowsyPoolFor(p, yawnCount: yawnCount);
    return pool[_rng.nextInt(pool.length)].$2;
  }

  Future<void> speakDrowsyReminder({
    required BuddyVoiceProfile profile,
    required int yawnCount,
    String? chosenText,
    VoidCallback? onPlaybackStart,
  }) async {
    final pool = _drowsyPoolFor(profile, yawnCount: yawnCount);
    final pick = chosenText != null
        ? pool.firstWhere((e) => e.$2 == chosenText, orElse: () => pool[0])
        : pool[_rng.nextInt(pool.length)];
    await _speakLocalAssetImmediate(
      assetRelPath: pick.$1,
      text: pick.$2,
      profile: profile,
      onPlaybackStart: onPlaybackStart,
    );
  }

  Future<void> speakOfflineSignalNotice(
    BuddyVoiceProfile profile, {
    VoidCallback? onPlaybackStart,
  }) async {
    final isEn = LanguageService.instance.isEnglish;
    final txt = offlineSignalTextFor(profile, isEnglish: isEn);
    if (!isEn) {
      await _speakLocalAssetImmediate(
        assetRelPath: offlineSignalAssetFor(profile),
        text: txt,
        profile: profile,
        onPlaybackStart: onPlaybackStart,
      );
      return;
    }
    await _speakWithAssetOrDynamic(
      profile: profile,
      text: txt,
      onPlaybackStart: onPlaybackStart,
    );
  }

  Future<void> _speakLocalAssetImmediate({
    required String assetRelPath,
    required String text,
    required BuddyVoiceProfile profile,
    VoidCallback? onPlaybackStart,
  }) async {
    await stop();
    _cancelled = false;
    await _ensureInit();
    await DeviceControlService.instance.setAudioDucking(enable: true);
    await SpotifyIslandController.instance.setBuddySpeechDucking(true);
    try {
      final wavBytes = await _loadAssetBytes('assets/$assetRelPath');
      if (wavBytes != null && wavBytes.lengthInBytes > 256) {
        isSpeaking.value = true;
        onPlaybackStart?.call();
        _startWavOrSyllableEnvelope(text, wavBytes: wavBytes);
        final done = Completer<void>();
        _activeSpeak = done;
        await _player.setReleaseMode(ReleaseMode.stop);
        await _player.setVolume(1.0);
        await _player.play(AssetSource(assetRelPath));
        await done.future.timeout(const Duration(seconds: 15), onTimeout: () {});
        return;
      }
      await _speakWithAssetOrDynamic(
        profile: profile,
        text: text,
        onPlaybackStart: onPlaybackStart,
      );
    } finally {
      _stopEnvelope();
      isSpeaking.value = false;
      await SpotifyIslandController.instance.setBuddySpeechDucking(false);
      await DeviceControlService.instance.setAudioDucking(enable: false);
    }
  }

  static Future<void> activateJaneHandoff() async {
    if (BuddyVoiceConfig.instance.profile == BuddyVoiceProfile.furina) {
      final rawNick = BuddyVoiceConfig.instance.rawCustomNickname.trim().toLowerCase();
      if (rawNick == 'rina' || rawNick == 'furina') {
        await BuddyVoiceConfig.instance.setCustomNickname('');
      }
      await BuddyVoiceConfig.instance.setProfile(BuddyVoiceProfile.jane);
    }
  }

  /// Mengembalikan `true` HANYA jika Furina benar-benar habis kuota di seluruh provider (`503`)
  /// dan otomatis berpindah ke Jane (bukan karena putus sinyal / tekan tombol Home!).
  Future<bool> speakReply({
    required BuddyVoiceProfile profile,
    required String text,
    bool isTiredFallback = false,
    bool isDrowsyDriver = false,
    Uint8List? prefetchedAudioBytes,
    String? prefetchedAudioMime,
    VoidCallback? onPlaybackStart,
  }) async {
    if (isTiredFallback && profile == BuddyVoiceProfile.furina) {
      await _speakLocalAssetImmediate(
        assetRelPath: furinaTiredAsset,
        text: furinaTiredText,
        profile: BuddyVoiceProfile.furina,
        onPlaybackStart: onPlaybackStart,
      );
      await activateJaneHandoff();
      return true;
    }

    final usedTiredHandoff = await _speakWithAssetOrDynamic(
      profile: profile,
      text: text,
      prefetchedAudioBytes: prefetchedAudioBytes,
      prefetchedAudioMime: prefetchedAudioMime,
      onPlaybackStart: onPlaybackStart,
    );
    if (usedTiredHandoff) {
      await activateJaneHandoff();
    }
    return usedTiredHandoff;
  }

  List<String> _splitForStreamingTts(String text) {
    final trimmed = text.trim();
    // Pertahankan seluruh balasan dalam 1 panggilan TTS tunggal sampai 450 karakter
    // agar warna suara & intonasi antar kalimat 100% konsisten (tidak berubah orang di tengah jalan).
    if (trimmed.length <= 450) return [trimmed];
    final parts = trimmed
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.length <= 1) return [trimmed];

    String first = parts.first;
    int idx = 1;
    while (first.length < 38 && idx < parts.length) {
      first = '$first ${parts[idx]}';
      idx++;
    }
    if (idx >= parts.length) return [trimmed];
    final rest = parts.sublist(idx).join(' ');
    return rest.isEmpty ? [first] : [first, rest];
  }

  Future<bool> _speakWithAssetOrDynamic({
    required BuddyVoiceProfile profile,
    required String text,
    String? furinaAssetPath,
    Uint8List? prefetchedAudioBytes,
    String? prefetchedAudioMime,
    VoidCallback? onPlaybackStart,
  }) async {
    await stop();
    _cancelled = false;
    await _ensureInit();
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    bool notifiedStart = false;
    void fireStartOnce() {
      if (!notifiedStart && !_cancelled) {
        notifiedStart = true;
        isSpeaking.value = true;
        onPlaybackStart?.call();
      }
    }

    await DeviceControlService.instance.setAudioDucking(enable: true);
    await SpotifyIslandController.instance.setBuddySpeechDucking(true);
    try {
      if (profile == BuddyVoiceProfile.furina && furinaAssetPath != null) {
        final wavBytes = await _loadAssetBytes('assets/$furinaAssetPath');
        if (wavBytes != null && wavBytes.lengthInBytes > 256) {
          fireStartOnce();
          _startWavOrSyllableEnvelope(trimmed, wavBytes: wavBytes);
          final done = Completer<void>();
          _activeSpeak = done;
          await _player.setReleaseMode(ReleaseMode.stop);
          await _player.setVolume(1.0);
          await _player.play(AssetSource(furinaAssetPath));
          await done.future.timeout(const Duration(seconds: 14), onTimeout: () {});
          return furinaAssetPath == furinaTiredAsset;
        }
      }

      if (prefetchedAudioBytes != null && prefetchedAudioBytes.length > 256) {
        final ok = await _playAudioBytes(
          trimmed,
          profile: profile,
          bytes: prefetchedAudioBytes,
          contentType: prefetchedAudioMime ?? 'audio/mpeg',
          onAudioReady: fireStartOnce,
        );
        if (ok) return false;
        if (_cancelled) return false;
      }

      // Sintesis tunggal utuh (atau split hanya jika > 450 karakter) agar intonasi & suara tetap seragam.
      final chunks = _splitForStreamingTts(trimmed);
      Future<http.Response?>? nextPrefetch;
      if (chunks.length > 1) {
        nextPrefetch = _fetchCloudTtsBytes(chunks[1], profile: profile);
      }

      final firstStatus = await _playCloudChunk(
        chunks[0],
        profile: profile,
        onAudioReady: fireStartOnce,
      );
      if (_cancelled) return false;

      if (firstStatus == _CloudTtsStatus.played) {
        if (chunks.length > 1 && !_cancelled) {
          final prefetchedResp = await nextPrefetch;
          if (!_cancelled && prefetchedResp != null && prefetchedResp.statusCode == 200 && prefetchedResp.bodyBytes.length >= 256) {
            await _playRawResponseBytes(
              chunks[1],
              profile: profile,
              resp: prefetchedResp,
              onAudioReady: fireStartOnce,
            );
          } else if (!_cancelled) {
            await _playCloudChunk(
              chunks[1],
              profile: profile,
              onAudioReady: fireStartOnce,
            );
          }
        }
        return false;
      }

      // Hanya jika server eksplisit mengembalikan HTTP 503 (seluruh provider Furina benar-benar habis),
      // barulah putar tired.wav & pindah otomatis ke Jane!
      if (profile == BuddyVoiceProfile.furina &&
          firstStatus == _CloudTtsStatus.exhausted503 &&
          !_cancelled) {
        final tiredBytes = await _loadAssetBytes('assets/$furinaTiredAsset');
        if (tiredBytes != null && tiredBytes.lengthInBytes > 256) {
          fireStartOnce();
          _startWavOrSyllableEnvelope(furinaTiredText, wavBytes: tiredBytes);
          final done = Completer<void>();
          _activeSpeak = done;
          await _player.setReleaseMode(ReleaseMode.stop);
          await _player.setVolume(1.0);
          await _player.play(AssetSource(furinaTiredAsset));
          await done.future.timeout(const Duration(seconds: 14), onTimeout: () {});
        }
        await activateJaneHandoff();
        if (!_cancelled) {
          await _playCloudChunk(
            trimmed,
            profile: BuddyVoiceProfile.jane,
            onAudioReady: fireStartOnce,
          );
        }
        return true;
      }

      // Jika terjadi gangguan jaringan seluler ("SOS saja" / terowongan), putar rekaman lokal offline
      // supaya tetap bersuara natural di HP Huawei/non-GMS tanpa salah memicu "Furina capek"!
      if (!_cancelled) {
        final offPath = offlineSignalAssetFor(profile);
        final offBytes = await _loadAssetBytes('assets/$offPath');
        if (offBytes != null && offBytes.lengthInBytes > 256) {
          fireStartOnce();
          _startWavOrSyllableEnvelope(offlineSignalTextFor(profile), wavBytes: offBytes);
          final done = Completer<void>();
          _activeSpeak = done;
          await _player.setReleaseMode(ReleaseMode.stop);
          await _player.setVolume(1.0);
          await _player.play(AssetSource(offPath));
          await done.future.timeout(const Duration(seconds: 14), onTimeout: () {});
          return false;
        }
        fireStartOnce();
        _startWavOrSyllableEnvelope(trimmed);
        await _speakNative(profile, trimmed);
      }
      return false;
    } finally {
      _stopEnvelope();
      isSpeaking.value = false;
      await SpotifyIslandController.instance.setBuddySpeechDucking(false);
      await DeviceControlService.instance.setAudioDucking(enable: false);
    }
  }

  Future<Uint8List?> _loadAssetBytes(String fullAssetKey) async {
    try {
      final data = await rootBundle.load(fullAssetKey);
      if (data.lengthInBytes <= 256) return null;
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    }
  }

  Future<http.Response?> _fetchCloudTtsBytes(
    String text, {
    required BuddyVoiceProfile profile,
    Duration timeout = const Duration(seconds: 26),
  }) async {
    try {
      await LlmChatConfig.shared.load();
      final isEn = LanguageService.instance.isEnglish;
      final lang = isEn ? 'en' : 'id';
      final uri = Uri.parse('${LlmChatConfig.shared.baseUrl}/tts');
      return await _http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'text': text,
              'voice_profile': profile.name,
              'language': lang,
            }),
          )
          .timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  Future<_CloudTtsStatus> _playCloudChunk(
    String text, {
    required BuddyVoiceProfile profile,
    VoidCallback? onAudioReady,
  }) async {
    final resp = await _fetchCloudTtsBytes(text, profile: profile);
    if (_cancelled) return _CloudTtsStatus.networkError;
    if (resp == null) return _CloudTtsStatus.networkError;
    if (resp.statusCode == 503) return _CloudTtsStatus.exhausted503;
    if (resp.statusCode != 200 || resp.bodyBytes.length < 256) {
      return _CloudTtsStatus.networkError;
    }
    final ok = await _playRawResponseBytes(
      text,
      profile: profile,
      resp: resp,
      onAudioReady: onAudioReady,
    );
    return ok ? _CloudTtsStatus.played : _CloudTtsStatus.networkError;
  }

  Future<bool> _playRawResponseBytes(
    String text, {
    required BuddyVoiceProfile profile,
    required http.Response resp,
    VoidCallback? onAudioReady,
  }) {
    return _playAudioBytes(
      text,
      profile: profile,
      bytes: resp.bodyBytes,
      contentType: resp.headers['content-type'] ?? '',
      onAudioReady: onAudioReady,
    );
  }

  Future<bool> _playAudioBytes(
    String text, {
    required BuddyVoiceProfile profile,
    required Uint8List bytes,
    required String contentType,
    VoidCallback? onAudioReady,
  }) async {
    try {
      if (_cancelled) return false;
      final dir = await getTemporaryDirectory();
      final isMp3 = contentType.contains('mpeg') ||
          contentType.contains('mp3') ||
          (bytes.length >= 3 &&
              ((bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) ||
                  (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0)));
      final ext = isMp3 ? 'mp3' : 'wav';
      final file = File(
        '${dir.path}/buddy_${profile.name}_${DateTime.now().microsecondsSinceEpoch}.$ext',
      );
      await file.writeAsBytes(bytes, flush: true);

      if (_cancelled) {
        unawaited(file.delete().catchError((_) => file));
        return false;
      }

      onAudioReady?.call();
      _startWavOrSyllableEnvelope(
        text,
        wavBytes: isMp3 ? null : bytes,
      );
      final done = Completer<void>();
      _activeSpeak = done;
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setVolume(1.0);
      await _player.play(DeviceFileSource(file.path));
      await done.future.timeout(const Duration(seconds: 28), onTimeout: () {});
      unawaited(file.delete().catchError((_) => file));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _speakNative(BuddyVoiceProfile profile, String text) async {
    try {
      await _configureNativeVoice(profile);
      final done = Completer<void>();
      _nativeSpeakDone = done;
      _nativeBusy = true;
      final res = await _tts.speak(text);
      if (res == 0) {
        await _tts.setLanguage(_resolvedIdLocale);
        await _tts.speak(text);
      }
      final estMs = (text.length * 85 + 1800).clamp(2500, 18000);
      await done.future.timeout(
        Duration(milliseconds: estMs),
        onTimeout: () {},
      );
    } catch (_) {
    } finally {
      _nativeBusy = false;
      _nativeSpeakDone = null;
    }
  }

  Future<void> _configureNativeVoice(BuddyVoiceProfile profile) async {
    final wantMale = profile == BuddyVoiceProfile.john;
    final isEn = LanguageService.instance.isEnglish;
    final targetLang = isEn ? 'en-US' : _resolvedIdLocale;

    await _tts.setVolume(1.0);
    await _tts.setLanguage(targetLang);
    try {
      final rawVoices = await _tts.getVoices;
      if (rawVoices is List) {
        final langPrefix = isEn ? 'en' : 'id';
        final candidates = rawVoices
            .whereType<Map>()
            .map((v) => Map<String, String>.fromEntries(
                  v.entries.map((e) => MapEntry(e.key.toString(), e.value.toString())),
                ))
            .where((v) {
              final loc = (v['locale'] ?? '').toLowerCase();
              return loc.startsWith(langPrefix) || (!isEn && loc.startsWith('in'));
            })
            .toList();
        if (candidates.isNotEmpty) {
          Map<String, String>? picked;
          if (wantMale) {
            picked = candidates.cast<Map<String, String>?>().firstWhere(
              (v) {
                final n = (v!['name'] ?? '').toLowerCase();
                return n.contains('male') || n.contains('ardi') || n.contains('idd') || n.contains('dfz') || n.contains('end') || n.contains('m0');
              },
              orElse: () => null,
            );
          } else {
            picked = candidates.cast<Map<String, String>?>().firstWhere(
              (v) {
                final n = (v!['name'] ?? '').toLowerCase();
                return n.contains('female') || n.contains('gadis') || n.contains('idc') || n.contains('f0');
              },
              orElse: () => null,
            );
          }
          if (picked != null) {
            await _tts.setVoice(picked);
          }
        }
      }
    } catch (_) {}
    await _tts.setSpeechRate(0.52);
    await _tts.setPitch(wantMale ? 0.84 : 1.04);
  }

  void _startWavOrSyllableEnvelope(String text, {Uint8List? wavBytes}) {
    _envelopeTimer?.cancel();
    const int frameMs = 35;
    final wavFrames = wavBytes != null
        ? _extractWavSpectralFrames(wavBytes, frameMs: frameMs)
        : null;

    if (wavFrames != null && wavFrames.isNotEmpty) {
      int idx = 0;
      _envelopeTimer = Timer.periodic(const Duration(milliseconds: frameMs), (_) {
        if (idx < wavFrames.length) {
          final frame = wavFrames[idx++];
          speechEnergy.value = frame.$1;
          speechFrequency.value = frame.$2;
        } else {
          speechEnergy.value = (speechEnergy.value * 0.65).clamp(0.0, 1.0);
        }
      });
      return;
    }

    int tick = 0;
    final clean = text.toLowerCase();
    final chars = clean.isNotEmpty ? clean : 'a';
    final words = clean.split(RegExp(r'\s+')).length.clamp(1, 40);
    final totalFrames = ((words * 340) / frameMs).ceil().clamp(8, 500);

    _envelopeTimer = Timer.periodic(const Duration(milliseconds: frameMs), (_) {
      tick++;
      final progress = (tick / totalFrames).clamp(0.0, 1.0);
      final charIdx = ((progress * (chars.length - 1)).round()).clamp(0, chars.length - 1);
      final ch = chars[charIdx];

      final isOpenVowel = ch == 'a' || ch == 'o' || ch == 'e';
      final isBrightVowel = ch == 'i' || ch == 'u';
      final isSibilant = ch == 's' || ch == 'c' || ch == 'z' || ch == 'f' || ch == 'k' || ch == 't';
      final isPause = ch == ' ' || ch == ',' || ch == '.' || ch == '?' || ch == '!';

      final syllabicPulse = 0.5 + 0.5 * math.sin(tick * 0.68);
      double targetE;
      double targetF;

      if (isPause) {
        targetE = 0.08 + 0.06 * syllabicPulse;
        targetF = 0.35;
      } else if (isOpenVowel) {
        targetE = 0.62 + 0.32 * syllabicPulse;
        targetF = 0.38 + 0.14 * math.sin(tick * 0.35);
      } else if (isBrightVowel) {
        targetE = 0.48 + 0.28 * syllabicPulse;
        targetF = 0.66 + 0.16 * math.cos(tick * 0.42);
      } else if (isSibilant) {
        targetE = 0.34 + 0.22 * syllabicPulse;
        targetF = 0.86;
      } else {
        targetE = 0.38 + 0.24 * syllabicPulse;
        targetF = 0.52;
      }

      speechEnergy.value = (speechEnergy.value * 0.35 + targetE * 0.65).clamp(0.0, 1.0);
      speechFrequency.value = (speechFrequency.value * 0.45 + targetF * 0.55).clamp(0.15, 1.0);
    });
  }

  List<(double, double)>? _extractWavSpectralFrames(Uint8List bytes, {required int frameMs}) {
    if (bytes.length < 44) return null;
    if (bytes[0] != 0x52 || bytes[1] != 0x49 || bytes[2] != 0x46 || bytes[3] != 0x46) {
      return null;
    }
    final bd = ByteData.sublistView(bytes);
    int offset = 12;
    int channels = 1;
    int sampleRate = 24000;
    int bitsPerSample = 16;
    int audioFormat = 1;
    int dataStart = -1;
    int dataSize = 0;

    while (offset + 8 <= bytes.length) {
      final id0 = bytes[offset];
      final id1 = bytes[offset + 1];
      final id2 = bytes[offset + 2];
      final id3 = bytes[offset + 3];
      final chunkSize = bd.getUint32(offset + 4, Endian.little);
      offset += 8;

      if (id0 == 0x66 && id1 == 0x6D && id2 == 0x74 && id3 == 0x20) {
        if (offset + 16 <= bytes.length) {
          audioFormat = bd.getUint16(offset, Endian.little);
          channels = bd.getUint16(offset + 2, Endian.little).clamp(1, 2);
          sampleRate = bd.getUint32(offset + 4, Endian.little).clamp(8000, 96000);
          bitsPerSample = bd.getUint16(offset + 14, Endian.little);
        }
      } else if (id0 == 0x64 && id1 == 0x61 && id2 == 0x74 && id3 == 0x61) {
        dataStart = offset;
        dataSize = math.min(chunkSize, bytes.length - offset);
        break;
      }
      offset += chunkSize + (chunkSize.isOdd ? 1 : 0);
    }

    if (dataStart < 0 || dataSize <= 0) return null;
    if (audioFormat != 1 && audioFormat != 3) return null;

    final bytesPerSample = (bitsPerSample ~/ 8).clamp(2, 4);
    final frameSamples = ((sampleRate * frameMs) ~/ 1000).clamp(64, 8192);
    final stepBytes = frameSamples * channels * bytesPerSample;
    if (stepBytes <= 0) return null;

    final frames = <(double, double)>[];
    double maxRms = 0.01;
    final rawMetrics = <(double, double)>[];

    for (int pos = dataStart; pos + stepBytes <= dataStart + dataSize; pos += stepBytes) {
      double sumSq = 0.0;
      int zeroCrossings = 0;
      double prevSample = 0.0;
      int count = 0;

      final stride = channels * bytesPerSample * 2;
      for (int i = pos; i + bytesPerSample <= pos + stepBytes; i += stride) {
        double sample = 0.0;
        if (audioFormat == 1 && bitsPerSample == 16) {
          sample = bd.getInt16(i, Endian.little) / 32768.0;
        } else if (audioFormat == 3 && bitsPerSample == 32) {
          sample = bd.getFloat32(i, Endian.little);
          if (!sample.isFinite) sample = 0.0;
        }
        sumSq += sample * sample;
        if (count > 0 && ((sample >= 0.0 && prevSample < 0.0) || (sample < 0.0 && prevSample >= 0.0))) {
          zeroCrossings++;
        }
        prevSample = sample;
        count++;
      }

      final rms = count > 0 ? math.sqrt(sumSq / count) : 0.0;
      if (rms > maxRms) maxRms = rms;
      final zcr = count > 1 ? (zeroCrossings / (count - 1)) : 0.15;
      rawMetrics.add((rms, zcr));
    }

    for (final m in rawMetrics) {
      final normE = math.pow((m.$1 / maxRms).clamp(0.0, 1.0), 0.72).toDouble();
      final normF = ((m.$2 - 0.03) / 0.34).clamp(0.18, 1.0);
      frames.add((normE, normF));
    }
    return frames;
  }

  void _stopEnvelope() {
    _envelopeTimer?.cancel();
    _envelopeTimer = null;
    speechEnergy.value = 0.0;
  }

  void _finishActive() {
    final c = _activeSpeak;
    _activeSpeak = null;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
  }

  void _finishNative() {
    final c = _nativeSpeakDone;
    _nativeSpeakDone = null;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
  }

  Future<void> stop() async {
    _cancelled = true;
    _stopEnvelope();
    isSpeaking.value = false;
    try {
      await _player.stop();
    } catch (_) {}
    if (_nativeBusy) {
      try {
        await _tts.stop();
      } catch (_) {}
      _nativeBusy = false;
    }
    _finishActive();
    _finishNative();
    await DeviceControlService.instance.setAudioDucking(enable: false);
  }

  Future<void> dispose() async {
    await stop();
    if (_ownsHttp) {
      _http.close();
    }
    await _player.dispose();
  }
}
