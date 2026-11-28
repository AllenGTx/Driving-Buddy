import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../services/device_control_service.dart';
import '../../services/language_service.dart';
import '../llm_chat/llm_chat_config.dart';
import 'buddy_voice_config.dart';

class BuddySttService {
  BuddySttService({http.Client? httpClient})
    : _http = httpClient ?? http.Client(),
      _ownsHttp = httpClient == null;

  /// Jeda hening sesudah pengemudi selesai bicara (~1.25 detik agar respons cepat).
  static const Duration siriTrailingSilenceCutoff = Duration(milliseconds: 1250);

  /// Batas tunggu suara pertama sesudah orb terbuka (2.2 detik).
  static const Duration siriInitialSilenceTimeout = Duration(milliseconds: 2200);

  final SpeechToText _speech = SpeechToText();
  final AudioRecorder _recorder = AudioRecorder();
  final http.Client _http;
  final bool _ownsHttp;

  final ValueNotifier<double> inputEnergy = ValueNotifier<double>(0.0);
  final ValueNotifier<double> inputFrequency = ValueNotifier<double>(0.42);
  final ValueNotifier<String> livePartialText = ValueNotifier<String>('');

  double _prevNormEnergy = 0.0;
  double _smoothedFreq = 0.42;

  bool _speechReady = false;
  String _resolvedSpeechLocale = 'id_ID';

  bool _watchActive = false;
  bool _appBackgrounded = false;
  bool _ecoMode = false;
  Future<void>? _wakeLoopFuture;
  Completer<void>? _wakeWindowCompleter;
  DateTime? _serverSttDownUntil;

  StreamSubscription<Amplitude>? _ampSub;
  Completer<void>? _activeCaptureCompleter;
  bool _forceCompleteCapture = false;
  bool _holdModeActive = false;

  void Function(String finalTranscript)? _onWakeSegment;
  bool Function(String candidate)? _wakeCandidateMatcher;

  Future<bool> ensureMicPermission() async {
    if (kIsWeb) return true;
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final res = await Permission.microphone.request();
    return res.isGranted;
  }

  Future<bool> _ensureSpeechInit() async {
    if (_speechReady) return true;
    try {
      _speechReady = await _speech.initialize(debugLogging: false);
      if (_speechReady) {
        final locales = await _speech.locales();
        // Pilih locale sesuai preferensi modul bahasa pengguna:
        // modul Inggris → cari en-US/en-GB; modul Indonesia → cari id/in
        final isEn = LanguageService.instance.isEnglish;
        for (final loc in locales) {
          final id = loc.localeId.toLowerCase();
          if (isEn) {
            if (id.startsWith('en')) {
              _resolvedSpeechLocale = loc.localeId;
              break;
            }
          } else {
            if (id.startsWith('id') || id.startsWith('in')) {
              _resolvedSpeechLocale = loc.localeId;
              break;
            }
          }
        }
      }
    } catch (_) {
      _speechReady = false;
    }
    return _speechReady;
  }

  /// Mode Siaga Universal (Acoustic VAD Micro-Burst):
  /// - Bekerja di 100% HP Android (Huawei, Xiaomi, Vivo, Oppo, Samsung) tanpa bunyi 'beep' sistem.
  /// - Saat ruangan/kabin hening: 0 request internet, 0 token AI, hemat baterai.
  /// - Hanya saat terdeteksi semburan suara manusia singkat (~0.3s-3.2s), klip mikro dicek ke STT;
  ///   jika cocok nama Buddy ("Rina", "Ei Rina", "Hei Rina", "Jane", "John"), langsung menyahut!
  Future<void> startWakeWordWatch({
    required void Function(String transcript) onUtterance,
    bool Function(String candidate)? isWakeCandidate,
  }) async {
    _onWakeSegment = onUtterance;
    _wakeCandidateMatcher = isWakeCandidate;
    if (_watchActive && _wakeLoopFuture != null) return;
    _watchActive = true;
    if (_appBackgrounded) return;
    _wakeLoopFuture = _runAcousticWakeLoop();
  }

  void setEcoMode(bool enabled) {
    _ecoMode = enabled;
  }

  void setAppBackgrounded(bool backgrounded, {bool keepActiveInDrive = false}) {
    final shouldPause = backgrounded && !keepActiveInDrive;
    if (_appBackgrounded == shouldPause) return;
    _appBackgrounded = shouldPause;
    if (_appBackgrounded) {
      final w = _wakeWindowCompleter;
      if (w != null && !w.isCompleted) w.complete();
    } else if (_watchActive && _wakeLoopFuture == null) {
      _wakeLoopFuture = _runAcousticWakeLoop();
    }
  }

  Future<void> pauseWakeWordWatch() async {
    _watchActive = false;
    final w = _wakeWindowCompleter;
    if (w != null && !w.isCompleted) {
      w.complete();
    }
    final running = _wakeLoopFuture;
    if (running != null) {
      try {
        await running.timeout(const Duration(milliseconds: 900));
      } catch (_) {}
      _wakeLoopFuture = null;
    }
    inputEnergy.value = 0.0;
    try {
      if (_speech.isListening) {
        await _speech.stop();
      }
    } catch (_) {}
  }

  Future<void> _runAcousticWakeLoop() async {
    double rollingAmbientDb = -44.0;
    bool calibratedOnce = false;

    try {
      final tempDir = await getTemporaryDirectory();
      while (_watchActive && !_appBackgrounded) {
        // Skenario Panggilan Telepon / WA VoIP: lepas mikrofon penuh selama panggilan berlangsung!
        if (await DeviceControlService.instance.isInPhoneOrVoipCall()) {
          await Future<void>.delayed(const Duration(seconds: 3));
          continue;
        }
        if (!await _recorder.hasPermission()) {
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }

        // Jika server sedang offline total, gunakan fallback SpeechToText on-device
        // PENTING: JANGAN panggil SpeechRecognizer saat musik sedang aktif, karena SpeechRecognizer.listen()
        // di Android merebut AudioFocus tiap ~1 detik dan membuat lagu Spotify tersendat-sendat!
        final offlineNow = _serverSttDownUntil != null &&
            DateTime.now().isBefore(_serverSttDownUntil!);
        if (offlineNow) {
          final musicPlaying = await DeviceControlService.instance.isSystemMusicActive();
          if (!musicPlaying) {
            await _listenOfflineWakeOnce();
            await Future<void>.delayed(const Duration(milliseconds: 400));
            continue;
          }
          // Jika musik aktif dan server sempat timeout, beri jeda singkat lalu lanjut pakai recorder akustik (non-intrusif)
          _serverSttDownUntil = null;
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }

        final segPath =
            '${tempDir.path}/buddy_wake_seg_${DateTime.now().millisecondsSinceEpoch}.wav';
        bool heardBurst = false;
        int speechTicks = 0;
        int quietAfterSpeechTicks = 0;
        int windowTicks = 0;
        double burstPeakDb = -42.0;

        final int pollMs = _ecoMode ? 90 : 60;
        final windowDone = Completer<void>();
        _wakeWindowCompleter = windowDone;
        StreamSubscription<Amplitude>? sub;

        try {
          await _recorder.start(
            const RecordConfig(
              encoder: AudioEncoder.wav,
              sampleRate: 16000,
              numChannels: 1,
              autoGain: true,
              echoCancel: true,
              noiseSuppress: true,
              androidConfig: AndroidRecordConfig(
                audioSource: AndroidAudioSource.voiceRecognition,
                manageBluetooth: false,
              ),
            ),
            path: segPath,
          );

          sub = _recorder
              .onAmplitudeChanged(Duration(milliseconds: pollMs))
              .listen((amp) {
            if (!_watchActive || _appBackgrounded) {
              if (!windowDone.isCompleted) windowDone.complete();
              return;
            }
            windowTicks++;
            final curDb = amp.current.isFinite
                ? amp.current.clamp(-60.0, 0.0)
                : -60.0;

            // Kalibrasi baseline SEKALI di awal tanpa meracuni lantai bising tiap jendela berulang!
            // Jika suara keras muncul tepat saat awal loop, cap pada -38 dB agar tetap peka.
            if (!calibratedOnce) {
              rollingAmbientDb = curDb.clamp(-58.0, -40.0);
              calibratedOnce = true;
            } else if (!heardBurst && curDb < rollingAmbientDb + 3.0) {
              rollingAmbientDb =
                  (rollingAmbientDb * 0.90 + curDb * 0.10).clamp(-58.0, -32.0);
            }

            // onsetDb: lebih rendah = lebih sensitif dari jarak jauh (posisi mengemudi ~50-70cm)
            final onsetDb = math.max(-52.0, rollingAmbientDb + 1.5);
            final endDb = heardBurst
                ? math.max(rollingAmbientDb + 0.8, burstPeakDb - 16.0)
                : onsetDb;

            if (curDb >= endDb) {
              speechTicks++;
              quietAfterSpeechTicks = 0;
              if (curDb > burstPeakDb) burstPeakDb = curDb;
              if (speechTicks >= 1) {
                heardBurst = true;
              }
              if (heardBurst && speechTicks >= 58 && !windowDone.isCompleted) {
                windowDone.complete();
              }
            } else if (heardBurst) {
              quietAfterSpeechTicks++;
              // Jeda ~420ms (7 tick x 60ms) agar sapaan 2 kata ("Yo John", "Hei Jane") tidak terpotong di tengah!
              if (quietAfterSpeechTicks >= 7 && !windowDone.isCompleted) {
                windowDone.complete();
              }
            } else {
              speechTicks = 0;
              if (windowTicks >= 95 && !windowDone.isCompleted) {
                windowDone.complete();
              }
            }
          });

          await windowDone.future.timeout(
            const Duration(milliseconds: 6200),
            onTimeout: () {},
          );
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
        } finally {
          _wakeWindowCompleter = null;
          await sub?.cancel();
          try {
            await _recorder.stop();
          } catch (_) {}
        }

        if (!_watchActive || _appBackgrounded) {
          unawaited(File(segPath).delete().catchError((_) => File(segPath)));
          break;
        }

        if (heardBurst && speechTicks >= 2) {
          final text = await _uploadToServerStt(
            filePath: segPath,
            buddyNameHint: BuddyVoiceConfig.instance.activeNickname,
            mode: 'wake',
            timeout: const Duration(milliseconds: 3500),
          );
          unawaited(File(segPath).delete().catchError((_) => File(segPath)));

          if (!_watchActive || _appBackgrounded) break;
          final cleaned = (text ?? '').trim();
          // Tolak transkripsi sangat pendek (1 huruf seperti "J") — noise musik atau batuk
          final cleanedAlpha = cleaned.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
          if (cleaned.isNotEmpty && cleanedAlpha.length >= 2) {
            final isMatch = _wakeCandidateMatcher?.call(cleaned) ?? false;
            if (isMatch) {
              _watchActive = false;
              _wakeLoopFuture = null;
              _onWakeSegment?.call(cleaned);
              return;
            }
          }
        } else {
          unawaited(File(segPath).delete().catchError((_) => File(segPath)));
        }
      }
    } finally {
      _wakeLoopFuture = null;
    }
  }

  Future<void> _listenOfflineWakeOnce() async {
    final ok = await _ensureSpeechInit();
    if (!ok || !_watchActive || _appBackgrounded) {
      await Future<void>.delayed(const Duration(seconds: 2));
      return;
    }
    final done = Completer<void>();
    String heard = '';
    try {
      await _speech.listen(
        listenOptions: SpeechListenOptions(
          localeId: _resolvedSpeechLocale,
          partialResults: true,
          cancelOnError: false,
          listenFor: const Duration(seconds: 6),
          pauseFor: const Duration(seconds: 1),
        ),
        onResult: (res) {
          heard = res.recognizedWords.trim();
          if (heard.isNotEmpty &&
              (_wakeCandidateMatcher?.call(heard) ?? false)) {
            if (!done.isCompleted) done.complete();
          } else if (res.finalResult && !done.isCompleted) {
            done.complete();
          }
        },
      );
      await done.future.timeout(const Duration(seconds: 7), onTimeout: () {});
    } catch (_) {
    } finally {
      try {
        if (_speech.isListening) await _speech.stop();
      } catch (_) {}
    }

    if (_watchActive &&
        !_appBackgrounded &&
        heard.isNotEmpty &&
        (_wakeCandidateMatcher?.call(heard) ?? false)) {
      _watchActive = false;
      _onWakeSegment?.call(heard);
    }
  }

  /// Dipanggil saat tombol Push-to-Talk dilepas sesudah ditahan agar rekaman langsung dikirim (0ms jeda).
  void finishActiveCaptureNow() {
    _forceCompleteCapture = true;
    _holdModeActive = false;
    final c = _activeCaptureCompleter;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
  }

  /// Jika pengguna hanya mengetuk singkat tombol Push-to-Talk (<420ms), alihkan ke mode potong otomatis 1.65 detik.
  void releaseHoldToAutoCutoff() {
    _holdModeActive = false;
  }

  /// Rekam ucapan pengemudi dengan DSP peredam bising kabin + Adaptive VAD (jeda 1.65 detik),
  /// lalu transkripsikan lewat rantai failover akurat: Groq Whisper -> Gemini Audio -> Native STT.
  Future<String> captureAndTranscribeCommand({
    required String buddyNameHint,
    Duration maxDuration = const Duration(seconds: 9),
    Duration initialSilenceTimeout = siriInitialSilenceTimeout,
    Duration trailingSilenceCutoff = siriTrailingSilenceCutoff,
    bool holdMode = false,
  }) async {
    await pauseWakeWordWatch();
    livePartialText.value = '';
    _forceCompleteCapture = false;
    _holdModeActive = holdMode;

    final serverTemporarilyDown = _serverSttDownUntil != null &&
        DateTime.now().isBefore(_serverSttDownUntil!);
    if (serverTemporarilyDown) {
      return _fallbackNativeCapture(
        maxDuration: maxDuration,
        initialSilenceTimeout: initialSilenceTimeout,
        pauseFor: trailingSilenceCutoff,
      );
    }

    String? recordedPath;
    bool recorderRan = false;
    bool heardVoice = false;
    int activeSpeechTicks = 0;
    int silentTicks = 0;
    int initialQuietTicks = 0;
    int totalTicks = 0;
    double ambientFloorDb = -42.0;
    double peakSpeechDb = -38.0;

    const int pollMs = 40;
    final int minSpeechOnsetTicks = (180 / pollMs).round();
    final int maxInitialQuietTicks =
        (initialSilenceTimeout.inMilliseconds / pollMs).ceil();
    final int maxTrailingSilentTicks =
        (trailingSilenceCutoff.inMilliseconds / pollMs).round();

    try {
      final tempDir = await getTemporaryDirectory();
      final outPath =
          '${tempDir.path}/buddy_cmd_${DateTime.now().millisecondsSinceEpoch}.wav';

      if (await _recorder.hasPermission()) {
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
            autoGain: true,
            echoCancel: true,
            noiseSuppress: true,
            androidConfig: AndroidRecordConfig(
              audioSource: AndroidAudioSource.voiceRecognition,
              manageBluetooth: false,
            ),
          ),
          path: outPath,
        );
        recorderRan = true;
        recordedPath = outPath;

        final done = Completer<void>();
        _activeCaptureCompleter = done;
        _ampSub?.cancel();
        _ampSub = _recorder
            .onAmplitudeChanged(const Duration(milliseconds: pollMs))
            .listen((amp) {
          totalTicks++;
          final curDb = amp.current.isFinite
              ? amp.current.clamp(-60.0, 0.0)
              : -60.0;
          final maxDb = amp.max.isFinite ? amp.max.clamp(-60.0, 0.0) : curDb;

          if (totalTicks <= 4) {
            ambientFloorDb = totalTicks == 1
                ? curDb.clamp(-52.0, -26.0)
                : (ambientFloorDb * 0.7 + curDb.clamp(-52.0, -26.0) * 0.3);
          } else if (!heardVoice && curDb < ambientFloorDb + 3.0) {
            ambientFloorDb =
                (ambientFloorDb * 0.92 + curDb * 0.08).clamp(-52.0, -25.0);
          }

          if (curDb > peakSpeechDb) {
            peakSpeechDb = curDb;
          }

          final onsetThresholdDb = math.max(-42.0, ambientFloorDb + 4.5);
          final sustainThresholdDb = heardVoice
              ? math.max(ambientFloorDb + 2.5, peakSpeechDb - 13.0)
              : onsetThresholdDb;

          final isSpeakingNow = curDb >= sustainThresholdDb;
          final norm =
              ((curDb - (ambientFloorDb - 4.0)) / 32.0).clamp(0.0, 1.0);
          final crest = ((maxDb - curDb).abs() / 18.0).clamp(0.0, 0.35);
          _pushLiveSignal(
            isSpeakingNow ? math.max(norm, 0.18) : norm * 0.45,
            crestHint: crest,
          );

          if (_forceCompleteCapture && !done.isCompleted) {
            done.complete();
            return;
          }

          if (isSpeakingNow) {
            activeSpeechTicks++;
            silentTicks = 0;
            if (activeSpeechTicks >= minSpeechOnsetTicks) {
              heardVoice = true;
            }
          } else if (heardVoice) {
            silentTicks++;
            if (!_holdModeActive &&
                silentTicks >= maxTrailingSilentTicks &&
                !done.isCompleted) {
              done.complete();
            }
          } else {
            activeSpeechTicks = 0;
            initialQuietTicks++;
            if (!_holdModeActive &&
                initialQuietTicks >= maxInitialQuietTicks &&
                !done.isCompleted) {
              done.complete();
            }
          }
        });

        await done.future.timeout(maxDuration, onTimeout: () {});
        _activeCaptureCompleter = null;
        await _ampSub?.cancel();
        _ampSub = null;
        recordedPath = await _recorder.stop();
      }
    } catch (_) {
      _activeCaptureCompleter = null;
      try {
        await _recorder.stop();
      } catch (_) {}
    } finally {
      _activeCaptureCompleter = null;
      inputEnergy.value = 0.0;
    }

    final validCapture =
        heardVoice || (_forceCompleteCapture && totalTicks >= 6);

    if (recordedPath != null && validCapture) {
      final serverTranscript = await _uploadToServerStt(
        filePath: recordedPath,
        buddyNameHint: buddyNameHint,
        mode: 'command',
      );
      unawaited(File(recordedPath).delete().catchError((_) => File(recordedPath!)));
      if (serverTranscript != null) {
        return serverTranscript.trim();
      }
      return '';
    } else if (recordedPath != null) {
      unawaited(File(recordedPath).delete().catchError((_) => File(recordedPath!)));
    }

    if (recorderRan && !validCapture) {
      return '';
    }

    return _fallbackNativeCapture(
      maxDuration: maxDuration,
      initialSilenceTimeout: initialSilenceTimeout,
      pauseFor: trailingSilenceCutoff,
    );
  }

  Future<String?> _uploadToServerStt({
    required String filePath,
    required String buddyNameHint,
    String mode = 'command',
    Duration timeout = const Duration(seconds: 6),
  }) async {
    try {
      final file = File(filePath);
      if (!file.existsSync() || file.lengthSync() < 400) return null;
      await LlmChatConfig.shared.load();
      final uri = Uri.parse('${LlmChatConfig.shared.baseUrl}/stt');
      // Kirim preferensi bahasa ke backend: 'en' untuk modul Inggris, 'id' untuk Indonesia.
      // Whisper akan menggunakannya untuk melokalisasi transkripsi lebih akurat.
      final lang = LanguageService.instance.isEnglish ? 'en' : 'id';
      final req = http.MultipartRequest('POST', uri)
        ..fields['hint'] = buddyNameHint
        ..fields['mode'] = mode
        ..fields['lang'] = lang
        ..files.add(await http.MultipartFile.fromPath('file', filePath));
      final streamed = await _http.send(req).timeout(timeout);
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode == 200) {
        _serverSttDownUntil = null;
        final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          return (decoded['text'] as String?)?.trim() ?? '';
        }
        return '';
      }
      _serverSttDownUntil = DateTime.now().add(const Duration(seconds: 30));
    } catch (_) {
      _serverSttDownUntil = DateTime.now().add(const Duration(seconds: 30));
    }
    return null;
  }

  Future<String> _fallbackNativeCapture({
    Duration maxDuration = const Duration(seconds: 6),
    Duration initialSilenceTimeout = siriInitialSilenceTimeout,
    Duration pauseFor = siriTrailingSilenceCutoff,
  }) async {
    final ok = await _ensureSpeechInit();
    if (!ok) return '';
    final completer = Completer<String>();
    _activeCaptureCompleter = completer;
    String latest = '';
    bool heardOnset = false;
    Timer? initialSilenceTimer;

    initialSilenceTimer = Timer(initialSilenceTimeout, () {
      if (!heardOnset && latest.isEmpty && !completer.isCompleted) {
        completer.complete('');
      }
    });

    try {
      await _speech.listen(
        listenOptions: SpeechListenOptions(
          localeId: _resolvedSpeechLocale,
          partialResults: true,
          cancelOnError: false,
          listenFor: maxDuration,
          pauseFor: pauseFor,
        ),
        onSoundLevelChange: (level) {
          final norm = ((level + 2.0) / 12.0).clamp(0.0, 1.0);
          _pushLiveSignal(norm);
          if (norm > 0.20) {
            heardOnset = true;
            initialSilenceTimer?.cancel();
          }
        },
        onResult: (res) {
          latest = res.recognizedWords.trim();
          if (latest.isNotEmpty) {
            heardOnset = true;
            initialSilenceTimer?.cancel();
          }
          livePartialText.value = latest;
          if ((res.finalResult || _forceCompleteCapture) &&
              !completer.isCompleted) {
            completer.complete(latest);
          }
        },
      );
      return await completer.future.timeout(
        maxDuration + const Duration(milliseconds: 500),
        onTimeout: () => latest,
      );
    } catch (_) {
      return latest;
    } finally {
      _activeCaptureCompleter = null;
      initialSilenceTimer.cancel();
      inputEnergy.value = 0.0;
      try {
        if (_speech.isListening) await _speech.stop();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    _watchActive = false;
    final w = _wakeWindowCompleter;
    if (w != null && !w.isCompleted) w.complete();
    await _ampSub?.cancel();
    try {
      await _speech.stop();
    } catch (_) {}
    try {
      await _recorder.dispose();
    } catch (_) {}
    if (_ownsHttp) _http.close();
    inputEnergy.dispose();
    inputFrequency.dispose();
    livePartialText.dispose();
  }

  void _pushLiveSignal(double norm, {double crestHint = 0.0}) {
    final clamped = norm.clamp(0.0, 1.0);
    final flux = (clamped - _prevNormEnergy).abs();
    _prevNormEnergy = clamped;
    final rawFreq = (0.24 + flux * 2.45 + clamped * 0.34 + crestHint)
        .clamp(0.18, 1.0);
    _smoothedFreq += (rawFreq - _smoothedFreq) * 0.42;
    inputFrequency.value = _smoothedFreq;
    inputEnergy.value = clamped;
  }
}

