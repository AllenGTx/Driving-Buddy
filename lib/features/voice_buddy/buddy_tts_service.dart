import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../services/language_service.dart';
import '../llm_chat/llm_chat_config.dart';
import 'buddy_voice_config.dart';

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
  String _resolvedIdLocale = 'id-ID';

  static const String furinaTiredText =
      'Maaf ya... Furina lagi capek nih, butuh istirahat. Mungkin kamu mau bicara sama Jane?';
  static const String furinaTiredAsset = 'audio/furina/tired.wav';

  static const List<(String, String)> _furinaWakeReplies = [
    ('audio/furina/wake_1.wav', 'Ya? Ada apa?'),
    ('audio/furina/wake_2.wav', 'Ya? Mau tanya apa?'),
    ('audio/furina/wake_3.wav', 'Ya? Gimana sayang...?'),
  ];

  static const List<String> _janeWakeRepliesId = [
    'Ya? Ada yang bisa Jane bantu?',
    'Halo, mau tanya apa nih?',
    'Iya, Jane dengerin kok.',
  ];

  static const List<String> _johnWakeRepliesId = [
    'Ya? Ada yang bisa dibantu?',
    'Siap, mau tanya apa?',
    'Iya bro, John dengerin.',
  ];

  static const List<(String, String)> _drowsyYawnLines = [
    (
      'audio/furina/drowsy_yawn.wav',
      'Eh, kamu sudah menguap dua kali nih dalam lima menit. Kalau mulai ngantuk, menepi sebentar ya.',
    ),
  ];

  static const List<(String, String)> _drowsyEyeLines = [
    (
      'audio/furina/drowsy_eyes.wav',
      'Aduh, mengantuk ya? Coba cari tempat istirahat ya.',
    ),
    (
      'audio/furina/drowsy_general.wav',
      'Kamu kelihatan mulai lelah di jalan. Yuk istirahat sebentar biar segar lagi.',
    ),
  ];

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

      // Beri waktu singkat agar service TextToSpeech Android selesai binding di panggilan pertama
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await _tts.setVolume(1.0);

      // Android lama/ROM tertentu memakai 'in-ID' alih-alih 'id-ID'
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

  String pickWakeAckText([BuddyVoiceProfile? profile]) {
    final p = profile ?? BuddyVoiceConfig.instance.profile;
    final isEn = LanguageService.instance.isEnglish;
    if (p == BuddyVoiceProfile.furina) {
      return _furinaWakeReplies[_rng.nextInt(_furinaWakeReplies.length)].$2;
    }
    if (isEn) {
      return p == BuddyVoiceProfile.john
          ? 'Yes? How can I help?'
          : 'Hi! What can Jane help you with?';
    }
    final pool = p == BuddyVoiceProfile.john ? _johnWakeRepliesId : _janeWakeRepliesId;
    return pool[_rng.nextInt(pool.length)];
  }

  Future<void> speakWakeAck(
    BuddyVoiceProfile profile, {
    String? chosenText,
    VoidCallback? onPlaybackStart,
  }) async {
    if (profile == BuddyVoiceProfile.furina) {
      final pick = chosenText != null
          ? _furinaWakeReplies.firstWhere(
              (e) => e.$2 == chosenText,
              orElse: () => _furinaWakeReplies[0],
            )
          : _furinaWakeReplies[_rng.nextInt(_furinaWakeReplies.length)];
      await _speakWithAssetOrDynamic(
        profile: profile,
        text: pick.$2,
        furinaAssetPath: pick.$1,
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

  String pickDrowsyReminderText({required int yawnCount}) {
    final pool = yawnCount >= 2 ? _drowsyYawnLines : _drowsyEyeLines;
    return pool[_rng.nextInt(pool.length)].$2;
  }

  Future<void> speakDrowsyReminder({
    required BuddyVoiceProfile profile,
    required int yawnCount,
    String? chosenText,
    VoidCallback? onPlaybackStart,
  }) async {
    final pool = yawnCount >= 2 ? _drowsyYawnLines : _drowsyEyeLines;
    final pick = chosenText != null
        ? pool.firstWhere((e) => e.$2 == chosenText, orElse: () => pool[0])
        : pool[_rng.nextInt(pool.length)];
    await _speakWithAssetOrDynamic(
      profile: profile,
      text: pick.$2,
      furinaAssetPath: profile == BuddyVoiceProfile.furina ? pick.$1 : null,
      onPlaybackStart: onPlaybackStart,
    );
  }

  /// Segera pindahkan profil aktif dari Furina ke Jane saat Furina lelah / habis kuota.
  static Future<void> activateJaneHandoff() async {
    if (BuddyVoiceConfig.instance.profile == BuddyVoiceProfile.furina) {
      final rawNick = BuddyVoiceConfig.instance.rawCustomNickname.trim().toLowerCase();
      if (rawNick == 'rina' || rawNick == 'furina') {
        await BuddyVoiceConfig.instance.setCustomNickname('');
      }
      await BuddyVoiceConfig.instance.setProfile(BuddyVoiceProfile.jane);
    }
  }

  /// Mengembalikan `true` jika Furina lelah (`tired.wav`) dan otomatis berpindah ke Jane.
  Future<bool> speakReply({
    required BuddyVoiceProfile profile,
    required String text,
    bool isTiredFallback = false,
    bool isDrowsyDriver = false,
    VoidCallback? onPlaybackStart,
  }) async {
    if (isTiredFallback && profile == BuddyVoiceProfile.furina) {
      // 1) Putar suara pamit Furina ("Maaf ya... Furina lagi capek nih... Mungkin kamu mau bicara sama Jane?")
      await _speakWithAssetOrDynamic(
        profile: BuddyVoiceProfile.furina,
        text: furinaTiredText,
        furinaAssetPath: furinaTiredAsset,
        onPlaybackStart: onPlaybackStart,
      );
      // 2) Langsung pindahkan profil aktif ke Jane secara otomatis!
      await activateJaneHandoff();
      return true;
    }

    final usedTiredHandoff = await _speakWithAssetOrDynamic(
      profile: profile,
      text: text,
      onPlaybackStart: onPlaybackStart,
    );
    if (usedTiredHandoff) {
      await activateJaneHandoff();
    }
    return usedTiredHandoff;
  }

  Future<bool> _speakWithAssetOrDynamic({
    required BuddyVoiceProfile profile,
    required String text,
    String? furinaAssetPath,
    VoidCallback? onPlaybackStart,
  }) async {
    await stop();
    await _ensureInit();
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    bool notifiedStart = false;
    void fireStartOnce() {
      if (!notifiedStart) {
        notifiedStart = true;
        isSpeaking.value = true;
        onPlaybackStart?.call();
      }
    }

    try {
      if (profile == BuddyVoiceProfile.furina) {
        // 1. Jika ada file WAV offline lokal (wake_1..3, drowsy, tired), putar seketika (0 kuota)
        if (furinaAssetPath != null) {
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

        // 2. Cloud Furina TTS (RVC v2 -> Free Neural Fallback di server)
        final playedRemote = await _tryRemoteCloudTts(
          trimmed,
          profile: BuddyVoiceProfile.furina,
          onAudioReady: fireStartOnce,
        );
        if (playedRemote) return false;

        // 3. Jika internet mati / server benar-benar tidak terjangkau: putar pesan pamit Furina -> otomatis pindah ke Jane -> Jane bacakan jawabannya!
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
        fireStartOnce();
        _startWavOrSyllableEnvelope(trimmed);
        await _speakNative(BuddyVoiceProfile.jane, trimmed);
        return true;
      }

      // Jane (Female Buddy) & John (Male Buddy):
      // Prioritas 1: Suara Neural Manusia Alami Gratis dari Cloud (GadisNeural / ArdiNeural -> natural, bukan robot!)
      final playedNeural = await _tryRemoteCloudTts(
        trimmed,
        profile: profile,
        onAudioReady: fireStartOnce,
        timeout: const Duration(seconds: 8),
      );
      if (playedNeural) return false;

      // Prioritas 2 (Offline / Tanpa Internet): Suara bawaan HP Android yang sudah dikalibrasi
      fireStartOnce();
      _startWavOrSyllableEnvelope(trimmed);
      await _speakNative(profile, trimmed);
      return false;
    } finally {
      _stopEnvelope();
      isSpeaking.value = false;
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

  Future<bool> _tryRemoteCloudTts(
    String text, {
    required BuddyVoiceProfile profile,
    VoidCallback? onAudioReady,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      await LlmChatConfig.shared.load();
      final isEn = LanguageService.instance.isEnglish;
      final lang = isEn ? 'en' : 'id';
      final uri = Uri.parse('${LlmChatConfig.shared.baseUrl}/tts');
      final resp = await _http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json; charset=utf-8'},
            body:
                '{"text":${_jsonEscape(text)},"voice_profile":"${profile.name}","language":"$lang"}',
          )
          .timeout(timeout);
      if (resp.statusCode != 200 || resp.bodyBytes.length < 256) return false;

      final dir = await getTemporaryDirectory();
      final isMp3 = (resp.headers['content-type'] ?? '').contains('mpeg');
      final ext = isMp3 ? 'mp3' : 'wav';
      final file = File(
        '${dir.path}/buddy_${profile.name}_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await file.writeAsBytes(resp.bodyBytes, flush: true);

      onAudioReady?.call();
      _startWavOrSyllableEnvelope(
        text,
        wavBytes: isMp3 ? null : resp.bodyBytes,
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
        // Jika engine menolak percobaan pertama, reset bahasa standar lalu ulang sekali
        await _tts.setLanguage(_resolvedIdLocale);
        await _tts.speak(text);
      }
      // Estimasi durasi aman berdasarkan panjang teks agar tidak pernah menggantung selamanya
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
    // Kecepatan & tinggi nada dibuat luwes agar suara bawaan HP tidak kaku
    await _tts.setSpeechRate(0.52);
    await _tts.setPitch(wantMale ? 0.86 : 1.05);

    try {
      final rawVoices = await _tts.getVoices;
      if (rawVoices is List) {
        Map<String, String>? chosen;
        final langPrefix = isEn ? 'en' : 'id';
        for (final item in rawVoices) {
          if (item is Map) {
            final locale = (item['locale'] ?? '').toString();
            final locLow = locale.toLowerCase();
            final name = (item['name'] ?? '').toString().toLowerCase();
            final matchesLang = isEn
                ? locLow.startsWith('en')
                : (locLow.startsWith(langPrefix) || locLow.startsWith('in'));
            if (!matchesLang) continue;

            final looksMale =
                name.contains('male') && !name.contains('female') ||
                name.contains('idd-') ||
                name.contains('idc-') ||
                name.contains('iom-') ||
                name.contains('#male');
            final looksFemale =
                name.contains('female') ||
                name.contains('ida-') ||
                name.contains('idb-') ||
                name.contains('network') && !looksMale ||
                name.contains('#female');

            if ((wantMale && looksMale) || (!wantMale && looksFemale)) {
              chosen = {
                'name': item['name'].toString(),
                'locale': locale,
              };
              break;
            }
          }
        }
        if (chosen != null) {
          await _tts.setVoice(chosen);
        }
      }
    } catch (_) {}
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
    _envelopeTimer = Timer.periodic(const Duration(milliseconds: frameMs), (_) {
      tick++;
      final t = tick * (frameMs / 1000.0);
      final charPos = ((t * 13.5).floor()) % chars.length;
      final ch = chars[charPos];
      final isPause = ch == ',' || ch == '.' || ch == '?' || ch == '!';
      final isSibilant =
          ch == 's' || ch == 'c' || ch == 'z' || ch == 'f' || ch == 'h' || ch == 't' || ch == 'k';
      final isHighVowel = ch == 'i' || ch == 'e' || ch == 'y';

      final carrier = math.sin(t * 24.0) * 0.5 + 0.5;
      final phrase = math.sin(t * 4.8 + words * 0.3) * 0.35 + 0.65;
      final targetE = isPause
          ? 0.08
          : ((carrier * phrase) * (isSibilant ? 0.72 : 1.0)).clamp(0.14, 0.96);
      final targetF = isPause
          ? 0.25
          : (isSibilant
                ? 0.88
                : (isHighVowel ? 0.66 : 0.38 + 0.16 * math.sin(t * 9.0)));
      speechEnergy.value = targetE;
      speechFrequency.value = targetF.clamp(0.20, 0.98);
    });
  }

  List<(double, double)>? _extractWavSpectralFrames(
    Uint8List bytes, {
    int frameMs = 35,
  }) {
    if (bytes.lengthInBytes < 44) return null;
    if (bytes[0] != 0x52 ||
        bytes[1] != 0x49 ||
        bytes[2] != 0x46 ||
        bytes[3] != 0x46 ||
        bytes[8] != 0x57 ||
        bytes[9] != 0x41 ||
        bytes[10] != 0x56 ||
        bytes[11] != 0x45) {
      return null;
    }

    final bd = ByteData.sublistView(bytes);
    int audioFormat = 0;
    int channels = 1;
    int sampleRate = 24000;
    int bitsPerSample = 16;
    int dataOffset = -1;
    int dataLength = 0;

    int pos = 12;
    while (pos + 8 <= bytes.lengthInBytes) {
      final id0 = bytes[pos];
      final id1 = bytes[pos + 1];
      final id2 = bytes[pos + 2];
      final id3 = bytes[pos + 3];
      final chunkSize = bd.getUint32(pos + 4, Endian.little);
      final bodyStart = pos + 8;
      if (bodyStart > bytes.lengthInBytes) break;

      if (id0 == 0x66 && id1 == 0x6D && id2 == 0x74 && id3 == 0x20 && chunkSize >= 16) {
        if (bodyStart + 16 <= bytes.lengthInBytes) {
          audioFormat = bd.getUint16(bodyStart, Endian.little);
          channels = bd.getUint16(bodyStart + 2, Endian.little).clamp(1, 8);
          sampleRate = bd.getUint32(bodyStart + 4, Endian.little).clamp(8000, 96000);
          bitsPerSample = bd.getUint16(bodyStart + 14, Endian.little);
        }
      } else if (id0 == 0x64 && id1 == 0x61 && id2 == 0x74 && id3 == 0x61) {
        dataOffset = bodyStart;
        dataLength = math.min(chunkSize, bytes.lengthInBytes - bodyStart);
        break;
      }
      pos = bodyStart + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }

    if (dataOffset < 0 || dataLength <= 0) return null;
    if (!((audioFormat == 1 && bitsPerSample == 16) ||
        (audioFormat == 3 && bitsPerSample == 32))) {
      return null;
    }

    final bytesPerSample = bitsPerSample ~/ 8;
    final blockAlign = bytesPerSample * channels;
    final totalSamples = dataLength ~/ blockAlign;
    final samplesPerFrame = math.max(64, (sampleRate * frameMs) ~/ 1000);
    if (totalSamples < samplesPerFrame) return null;

    final rawRms = <double>[];
    final rawZcr = <double>[];

    for (int start = 0; start + samplesPerFrame <= totalSamples; start += samplesPerFrame) {
      double sumSq = 0.0;
      int zeroCrossings = 0;
      double prev = 0.0;
      final step = sampleRate >= 44100 ? 2 : 1;
      int count = 0;

      for (int i = 0; i < samplesPerFrame; i += step) {
        final byteIdx = dataOffset + (start + i) * blockAlign;
        double sample;
        if (audioFormat == 1) {
          sample = bd.getInt16(byteIdx, Endian.little) / 32768.0;
        } else {
          sample = bd.getFloat32(byteIdx, Endian.little).clamp(-1.0, 1.0);
        }
        sumSq += sample * sample;
        if (count > 0 && ((sample >= 0.0 && prev < 0.0) || (sample < 0.0 && prev >= 0.0))) {
          zeroCrossings++;
        }
        prev = sample;
        count++;
      }

      final rms = count > 0 ? math.sqrt(sumSq / count) : 0.0;
      final effFs = sampleRate / step;
      final zcrHz = count > 1 ? (zeroCrossings / (count - 1)) * (effFs * 0.5) : 350.0;
      rawRms.add(rms);
      rawZcr.add(zcrHz);
    }

    if (rawRms.isEmpty) return null;
    final sorted = List<double>.from(rawRms)..sort();
    final refPeak = math.max(0.06, sorted[(sorted.length * 0.92).floor().clamp(0, sorted.length - 1)]);

    final out = <(double, double)>[];
    for (int i = 0; i < rawRms.length; i++) {
      final normE = (rawRms[i] / refPeak).clamp(0.0, 1.0);
      final shapedE = normE < 0.05 ? 0.02 : math.pow(normE, 0.78).toDouble().clamp(0.04, 1.0);
      final normF = ((rawZcr[i] - 220.0) / 3000.0).clamp(0.18, 1.0);
      out.add((shapedE, normF));
    }
    return out;
  }

  void _stopEnvelope() {
    _envelopeTimer?.cancel();
    _envelopeTimer = null;
    speechEnergy.value = 0.0;
    speechFrequency.value = 0.45;
  }

  void _finishActive() {
    final c = _activeSpeak;
    _activeSpeak = null;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
  }

  void _finishNative() {
    final n = _nativeSpeakDone;
    _nativeSpeakDone = null;
    if (n != null && !n.isCompleted) {
      n.complete();
    }
  }

  Future<void> stop() async {
    _finishActive();
    _finishNative();
    _stopEnvelope();
    isSpeaking.value = false;
    try {
      await _player.stop();
    } catch (_) {}
    if (_nativeBusy) {
      _nativeBusy = false;
      try {
        await _tts.stop();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await stop();
    if (_ownsHttp) _http.close();
    await _player.dispose();
    speechEnergy.dispose();
    speechFrequency.dispose();
    isSpeaking.dispose();
  }

  static String _jsonEscape(String s) {
    final escaped = s
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ');
    return '"$escaped"';
  }
}
