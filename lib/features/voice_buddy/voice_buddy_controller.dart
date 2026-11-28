import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/thresholds.dart';
import '../../models/detection_result.dart';
import '../../services/device_control_service.dart';
import '../../services/driving_notification_service.dart';
import '../../services/language_service.dart';
import '../llm_chat/llm_chat.dart';
import '../nearby_places/data/direct_osm_places_api.dart';
import '../nearby_places/data/location_provider.dart';
import '../nearby_places/logic/nearby_controller.dart';
import '../nearby_places/logic/place_launcher.dart';
import '../nearby_places/models/nearby_place.dart';
import '../nearby_places/models/place_category.dart';
import '../spotify_island/spotify_island_controller.dart';
import 'buddy_stt_service.dart';
import 'buddy_tts_service.dart';
import 'buddy_voice_config.dart';
import 'wake_word_matcher.dart';

enum SiriOrbPhase {
  hidden,
  summon,
  idle,
  listening,
  thinking,
  speaking,
  dismissing,
}

class VoiceBuddyController extends ChangeNotifier {
  VoiceBuddyController({
    required this.nearby,
    String Function()? sessionIdProvider,
    DetectionResult Function()? driverResultProvider,
    int Function()? tripMinutesProvider,
    this.requireFirebaseAuth = true,
    LlmChatApi? chatApi,
    BuddySttService? stt,
    BuddyTtsService? tts,
  }) : _sessionIdProvider = sessionIdProvider ?? (() => 'local-driver'),
       _driverResultProvider =
           driverResultProvider ?? (() => DetectionResult.initial),
       _tripMinutesProvider = tripMinutesProvider ?? (() => 0),
       _chatApi = chatApi ?? LlmChatApi(),
       _stt = stt ?? BuddySttService(),
       _tts = tts ?? BuddyTtsService() {
    BuddyVoiceConfig.instance.addListener(_onConfigChanged);
    _stt.inputEnergy.addListener(_syncEnergy);
    _stt.inputFrequency.addListener(_syncEnergy);
    _stt.livePartialText.addListener(_onPartialChanged);
    _tts.speechEnergy.addListener(_syncEnergy);
    _tts.speechFrequency.addListener(_syncEnergy);

    if (requireFirebaseAuth) {
      try {
        _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
          if (user == null || !user.emailVerified) {
            _insideAuthenticatedApp = false;
            unawaited(_forceSilenceOnAuthExit());
          }
        });
      } catch (_) {}
    }
  }

  static const String _prefEnabledKey = 'buddy_voice_enabled';
  static const Duration _dismissAnimDuration = Duration(milliseconds: 280);

  final NearbyPlacesController nearby;
  String Function() _sessionIdProvider;
  DetectionResult Function() _driverResultProvider;
  int Function() _tripMinutesProvider;
  final bool requireFirebaseAuth;

  final LlmChatApi _chatApi;
  final BuddySttService _stt;
  final BuddyTtsService _tts;
  final DirectOsmPlacesApi _directPlaces = DirectOsmPlacesApi();
  final GeolocatorLocationProvider _fallbackGps = GeolocatorLocationProvider();
  StreamSubscription<User?>? _authSub;

  bool _enabled = false;
  bool _insideAuthenticatedApp = false;
  bool _appInForeground = true;
  bool _emergencyMuted = false;
  bool _busyTurn = false;
  bool _holdingPtt = false;
  bool _followUpListening = false;
  bool _drowsyReminderActive = false;
  bool _isDrivingActive = false;
  int _turnId = 0;
  DateTime _pttDownAt = DateTime.fromMillisecondsSinceEpoch(0);

  SiriOrbPhase _phase = SiriOrbPhase.hidden;
  String _transcriptText = '';
  String _replyText = '';
  double _orbEnergy = 0.0;
  double _orbFrequency = 0.45;
  DateTime _lastDrowsySpeech = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _dismissTimer;
  Timer? _resumeAfterCallTimer;
  Timer? _watchdog;
  DateTime _lastTurnEnd = DateTime.fromMillisecondsSinceEpoch(0);

  static const Duration _echoGuard = Duration(milliseconds: 650);
  static const Duration _turnWatchdog = Duration(seconds: 90);
  static const Duration _initialWakeSilenceTimeout = Duration(milliseconds: 3200);
  static const Duration _followUpSilenceTimeout = Duration(milliseconds: 4200);
  static const int _maxFollowUpTurns = 12;

  bool get isEnabled => _enabled;
  bool get isHoldingPtt => _holdingPtt;
  bool get isFollowUpListening => _followUpListening;
  bool get isDrowsyReminderActive => _drowsyReminderActive;
  SiriOrbPhase get phase => _phase;
  bool get isSheetVisible => _phase != SiriOrbPhase.hidden;
  String get transcriptText => _transcriptText;
  String get replyText => _replyText;
  double get orbEnergy => _orbEnergy;
  double get orbFrequency => _orbFrequency;
  String get activeNickname => BuddyVoiceConfig.instance.activeNickname;
  BuddyVoiceProfile get voiceProfile => BuddyVoiceConfig.instance.profile;

  bool get _isAllowedInCurrentScreen {
    if (!_insideAuthenticatedApp || !_appInForeground) return false;
    if (!requireFirebaseAuth) return true;
    try {
      final u = FirebaseAuth.instance.currentUser;
      return u != null && u.emailVerified;
    } catch (_) {
      return _insideAuthenticatedApp;
    }
  }

  void setEcoMode(bool enabled) {
    _stt.setEcoMode(enabled);
  }

  Future<void> setInsideAuthenticatedApp(bool inside) async {
    if (_insideAuthenticatedApp == inside) return;
    _insideAuthenticatedApp = inside;
    if (!inside) {
      await _forceSilenceOnAuthExit();
    } else if (_enabled && _appInForeground && !_emergencyMuted && !_busyTurn) {
      await _resumePassiveWakeWatch();
    }
  }

  Future<void> _forceSilenceOnAuthExit() async {
    _turnId++;
    _dismissTimer?.cancel();
    _resumeAfterCallTimer?.cancel();
    _holdingPtt = false;
    _followUpListening = false;
    _drowsyReminderActive = false;
    _busyTurn = false;
    _stt.finishActiveCaptureNow();
    await _stt.pauseWakeWordWatch();
    await _tts.stop();
    if (_phase != SiriOrbPhase.hidden) {
      _phase = SiriOrbPhase.hidden;
      notifyListeners();
    }
  }

  void bindDrivingTelemetry({
    required String Function() sessionIdProvider,
    required DetectionResult Function() driverResultProvider,
    required int Function() tripMinutesProvider,
  }) {
    _sessionIdProvider = sessionIdProvider;
    _driverResultProvider = driverResultProvider;
    _tripMinutesProvider = tripMinutesProvider;
  }

  /// Menangani keluar aplikasi (Home, Screenshot, pindah ke Maps/Spotify, layar kunci, atau panggilan masuk):
  /// - Langsung sembunyikan Orb ke mode idle tanpa pernah salah memutar suara "Furina capek"!
  /// - Bersihkan cache gambar di memori agar RAM saat berjalan di latar belakang sangat hemat.
  /// - Otomatis kembali siaga ~1.8 detik sesudah kembali ke dalam aplikasi (dan telepon sudah selesai).
  void handleAppLifecycle(AppLifecycleState state, {bool isDriving = false}) {
    _isDrivingActive = isDriving;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _appInForeground = false;
      _resumeAfterCallTimer?.cancel();
      _turnId++;
      _dismissTimer?.cancel();
      _holdingPtt = false;
      _followUpListening = false;
      _drowsyReminderActive = false;
      _busyTurn = false;
      _stt.finishActiveCaptureNow();
      _stt.setAppBackgrounded(true, keepActiveInDrive: false);
      unawaited(_stt.pauseWakeWordWatch());
      unawaited(_tts.stop());
      if (_phase != SiriOrbPhase.hidden) {
        _phase = SiriOrbPhase.hidden;
        notifyListeners();
      }
      try {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      } catch (_) {}
    } else if (state == AppLifecycleState.inactive) {
      // Saat user menekan tombol Screenshot / notifikasi bar / telepon masuk mendadak:
      // bila Orb sedang terbuka, batalkan giliran dengan tenang agar socket putus tidak dianggap "capek"
      if (_phase != SiriOrbPhase.hidden) {
        _turnId++;
        _dismissTimer?.cancel();
        _holdingPtt = false;
        _followUpListening = false;
        _drowsyReminderActive = false;
        _busyTurn = false;
        _stt.finishActiveCaptureNow();
        unawaited(_tts.stop());
        _phase = SiriOrbPhase.hidden;
        notifyListeners();
      }
    } else if (state == AppLifecycleState.resumed) {
      _appInForeground = true;
      _stt.setAppBackgrounded(false, keepActiveInDrive: isDriving);
      _resumeAfterCallTimer?.cancel();
      _resumeAfterCallTimer = Timer(const Duration(milliseconds: 1800), () async {
        if (!_enabled || !_isAllowedInCurrentScreen || _emergencyMuted || _busyTurn) {
          return;
        }
        if (await DeviceControlService.instance.isInPhoneOrVoipCall()) {
          return;
        }
        await _resumePassiveWakeWatch();
      });
    }
  }

  Future<void> init({bool insideMainApp = false}) async {
    _insideAuthenticatedApp = insideMainApp;
    await BuddyVoiceConfig.instance.load();
    await SpotifyIslandController.instance.init();
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEnabled = prefs.getBool(_prefEnabledKey) ?? false;
      if (savedEnabled) {
        final granted = kIsWeb || (await Permission.microphone.status).isGranted;
        if (granted) {
          _enabled = true;
          notifyListeners();
          if (_isAllowedInCurrentScreen) {
            await _resumePassiveWakeWatch();
          }
        }
      }
    } catch (_) {}
  }

  void _onConfigChanged() {
    notifyListeners();
    if (_enabled && _isAllowedInCurrentScreen && !_busyTurn && !_emergencyMuted) {
      unawaited(_resumePassiveWakeWatch());
    }
  }

  void _syncEnergy() {
    double e = 0.0;
    double f = _orbFrequency;
    if (_phase == SiriOrbPhase.speaking) {
      e = _tts.speechEnergy.value;
      f = _tts.speechFrequency.value;
    } else if (_phase == SiriOrbPhase.listening) {
      e = _stt.inputEnergy.value;
      f = _stt.inputFrequency.value;
    }
    if ((e - _orbEnergy).abs() > 0.015 || (f - _orbFrequency).abs() > 0.02) {
      _orbEnergy = e;
      _orbFrequency = f;
      notifyListeners();
    }
  }

  void _onPartialChanged() {
    if (_phase == SiriOrbPhase.listening) {
      final partial = _stt.livePartialText.value.trim();
      if (partial.isNotEmpty && partial != _transcriptText) {
        _transcriptText = partial;
        notifyListeners();
      }
    }
  }

  Future<bool> setEnabled(bool wantEnabled) async {
    if (wantEnabled) {
      final granted = await _stt.ensureMicPermission();
      if (!granted) {
        _enabled = false;
        _saveEnabledPref(false);
        notifyListeners();
        return false;
      }
      _enabled = true;
      _saveEnabledPref(true);
      notifyListeners();
      if (_isAllowedInCurrentScreen && !_emergencyMuted) {
        await _resumePassiveWakeWatch();
      }
      return true;
    } else {
      _turnId++;
      _enabled = false;
      _holdingPtt = false;
      _followUpListening = false;
      _drowsyReminderActive = false;
      _saveEnabledPref(false);
      _dismissTimer?.cancel();
      await _stt.pauseWakeWordWatch();
      await _tts.stop();
      _phase = SiriOrbPhase.hidden;
      _transcriptText = '';
      _replyText = '';
      _busyTurn = false;
      notifyListeners();
      return false;
    }
  }

  void _saveEnabledPref(bool val) {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool(_prefEnabledKey, val);
    }).catchError((_) {});
  }

  /// Saat Sirine Darurat Microsleep berbunyi:
  /// 1. Musik Spotify langsung di-pause paksa demi keselamatan pengemudi!
  /// 2. Asisten suara langsung membisu agar sirine darurat terdengar 100%.
  void setEmergencyAlertActive(bool active) {
    if (_emergencyMuted == active) return;
    _emergencyMuted = active;
    if (active) {
      _turnId++;
      _dismissTimer?.cancel();
      _holdingPtt = false;
      _followUpListening = false;
      _drowsyReminderActive = false;
      _stt.finishActiveCaptureNow();
      unawaited(_tts.stop());
      unawaited(_stt.pauseWakeWordWatch());
      unawaited(SpotifyIslandController.instance.pauseForEmergencyAlarm());
      if (_phase != SiriOrbPhase.hidden) {
        _phase = SiriOrbPhase.hidden;
        _busyTurn = false;
        notifyListeners();
      }
    } else {
      unawaited(DeviceControlService.instance.setAudioDucking(enable: false));
      if (_enabled && _isAllowedInCurrentScreen) {
        unawaited(_resumePassiveWakeWatch());
      }
    }
  }

  /// Peringatan Kantuk Halus (0ms rekaman suara lokal untuk Furina, Jane & John, tanpa teks "Silakan bicara sekarang...")
  Future<void> maybeSpeakDrowsyReminder({required int yawnCount}) async {
    if (!_enabled || !_isAllowedInCurrentScreen || _emergencyMuted || _busyTurn) {
      return;
    }
    if (await DeviceControlService.instance.isInPhoneOrVoipCall()) {
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastDrowsySpeech) < Thresholds.buddyDrowsyTtsCooldown) {
      return;
    }
    _lastDrowsySpeech = now;
    final myTurn = ++_turnId;
    _busyTurn = true;
    _drowsyReminderActive = true;
    _dismissTimer?.cancel();
    await _stt.pauseWakeWordWatch();

    final curProf = voiceProfile;
    final chosenDrowsy = _tts.pickDrowsyReminderText(
      yawnCount: yawnCount,
      profile: curProf,
    );
    _transcriptText = '';
    _replyText = chosenDrowsy;
    _setPhase(SiriOrbPhase.summon);

    if (myTurn != _turnId || !_enabled || !_isAllowedInCurrentScreen || _emergencyMuted) {
      _drowsyReminderActive = false;
      _busyTurn = false;
      return;
    }

    await _tts.speakDrowsyReminder(
      profile: curProf,
      yawnCount: yawnCount,
      chosenText: chosenDrowsy,
      onPlaybackStart: () {
        if (myTurn != _turnId) return;
        _replyText = chosenDrowsy;
        _setPhase(SiriOrbPhase.speaking);
      },
    );
    if (myTurn != _turnId) return;
    _drowsyReminderActive = false;
    _scheduleDismissAndResume();
  }

  /// Ketuk bola kaca:
  /// - TIDAK PERNAH menghilangkan Orb secara tak sengaja!
  /// - Jika asisten sedang berbicara (`speaking`), ketukan menyela pembicaraan agar pengguna bisa langsung bicara.
  /// - Jika asisten sedang mendengarkan / berpikir, hanya memicu efek kilatan cahaya kaca (*glass flare*).
  Future<void> onOrbTapped() async {
    if (!_isAllowedInCurrentScreen || _emergencyMuted) return;
    if (_phase == SiriOrbPhase.speaking && !_drowsyReminderActive) {
      _dismissTimer?.cancel();
      final myTurn = ++_turnId;
      _busyTurn = true;
      await _tts.stop();
      if (myTurn != _turnId) return;
      await _listenAndAnswerAfterWake(turnId: myTurn);
    }
  }

  Future<void> onPushToTalkDown() async {
    if (!_isAllowedInCurrentScreen || _emergencyMuted) return;
    if (await DeviceControlService.instance.isInPhoneOrVoipCall()) return;
    final granted = await _stt.ensureMicPermission();
    if (!granted) return;

    _dismissTimer?.cancel();
    _drowsyReminderActive = false;
    _pttDownAt = DateTime.now();
    _holdingPtt = true;
    notifyListeners();

    if (_phase == SiriOrbPhase.speaking) {
      await _tts.stop();
    } else if (_phase == SiriOrbPhase.listening) {
      _holdingPtt = false;
      _stt.finishActiveCaptureNow();
      notifyListeners();
      return;
    } else if (_busyTurn && _phase != SiriOrbPhase.dismissing) {
      return;
    }

    final myTurn = ++_turnId;
    _busyTurn = true;
    await _listenAndAnswerAfterWake(holdMode: true, turnId: myTurn);
  }

  void onPushToTalkUp() {
    if (!_holdingPtt) return;
    _holdingPtt = false;
    final heldMs = DateTime.now().difference(_pttDownAt).inMilliseconds;
    if (heldMs >= 420) {
      _stt.finishActiveCaptureNow();
    } else {
      _stt.releaseHoldToAutoCutoff();
    }
    notifyListeners();
  }

  Future<void> dismissSheet() async {
    _turnId++;
    _dismissTimer?.cancel();
    _holdingPtt = false;
    _followUpListening = false;
    _drowsyReminderActive = false;
    _busyTurn = false;
    _stt.finishActiveCaptureNow();
    await _tts.stop();
    if (_phase != SiriOrbPhase.hidden) {
      _setPhase(SiriOrbPhase.dismissing);
      await Future<void>.delayed(_dismissAnimDuration);
      if (_phase == SiriOrbPhase.dismissing) {
        _setPhase(SiriOrbPhase.hidden);
      }
    }
    if (_enabled && _isAllowedInCurrentScreen && !_emergencyMuted) {
      await _resumePassiveWakeWatch();
    }
  }

  bool _isWakeMatchCandidate(String candidate) {
    final m = WakeWordMatcher.match(
      candidate,
      profile: voiceProfile,
      activeNickname: activeNickname,
    );
    return m.kind == WakeMatchKind.wakeOnly ||
        m.kind == WakeMatchKind.commandWithWake;
  }

  Future<void> _resumePassiveWakeWatch() async {
    if (!_enabled || !_isAllowedInCurrentScreen || _emergencyMuted || _busyTurn) {
      return;
    }
    await _stt.startWakeWordWatch(
      onUtterance: _handlePassiveUtterance,
      isWakeCandidate: _isWakeMatchCandidate,
    );
  }

  Future<void> _handlePassiveUtterance(String transcript) async {
    if (!_enabled || !_isAllowedInCurrentScreen || _emergencyMuted || _busyTurn) {
      return;
    }
    if (await DeviceControlService.instance.isInPhoneOrVoipCall()) {
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastTurnEnd) < _echoGuard) {
      await _resumePassiveWakeWatch();
      return;
    }

    final match = WakeWordMatcher.match(
      transcript,
      profile: voiceProfile,
      activeNickname: activeNickname,
    );
    if (match.kind == WakeMatchKind.none) {
      await _resumePassiveWakeWatch();
      return;
    }
    if (match.kind == WakeMatchKind.cancel) {
      if (_phase != SiriOrbPhase.hidden) {
        await dismissSheet();
      } else {
        await _resumePassiveWakeWatch();
      }
      return;
    }

    final myTurn = ++_turnId;
    _busyTurn = true;
    _drowsyReminderActive = false;
    _dismissTimer?.cancel();
    await _stt.pauseWakeWordWatch();

    if (match.kind == WakeMatchKind.wakeOnly) {
      final chosenAck = _tts.pickWakeAckText(voiceProfile);
      _transcriptText = transcript;
      _replyText = chosenAck;
      _setPhase(SiriOrbPhase.summon);
      if (myTurn != _turnId) return;
      if (!_enabled || !_isAllowedInCurrentScreen || _emergencyMuted) {
        _busyTurn = false;
        return;
      }
      await _tts.speakWakeAck(
        voiceProfile,
        chosenText: chosenAck,
        onPlaybackStart: () {
          if (myTurn != _turnId) return;
          _replyText = chosenAck;
          _setPhase(SiriOrbPhase.speaking);
        },
      );
      if (myTurn != _turnId) return;
      if (!_enabled || !_isAllowedInCurrentScreen || _emergencyMuted) {
        _busyTurn = false;
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (myTurn != _turnId) return;
      await _listenAndAnswerAfterWake(turnId: myTurn);
      return;
    }

    _transcriptText = match.remainingCommand;
    _replyText = '';
    _setPhase(SiriOrbPhase.summon);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (myTurn != _turnId) return;
    await _processCommandWithLlm(match.remainingCommand, turnId: myTurn);
  }

  Future<void> _listenAndAnswerAfterWake({
    bool holdMode = false,
    bool isFollowUp = false,
    int followUpDepth = 0,
    int? turnId,
  }) async {
    final myTurn = turnId ?? _turnId;
    if (myTurn != _turnId) return;
    if (!_isAllowedInCurrentScreen || _emergencyMuted) {
      _followUpListening = false;
      _busyTurn = false;
      return;
    }
    if (await DeviceControlService.instance.isInPhoneOrVoipCall()) {
      await dismissSheet();
      return;
    }

    final isEn = LanguageService.instance.isEnglish;
    _followUpListening = isFollowUp;
    _drowsyReminderActive = false;
    if (!isFollowUp) {
      _transcriptText = isEn ? 'Listening...' : 'Mendengarkan...';
      _replyText = '';
    }
    _setPhase(SiriOrbPhase.listening);

    final query = await _stt.captureAndTranscribeCommand(
      buddyNameHint: activeNickname,
      holdMode: holdMode,
      initialSilenceTimeout:
          isFollowUp ? _followUpSilenceTimeout : _initialWakeSilenceTimeout,
    );
    if (myTurn != _turnId) return;

    _holdingPtt = false;
    _followUpListening = false;
    if (!_isAllowedInCurrentScreen || _emergencyMuted) {
      _busyTurn = false;
      return;
    }
    if (query.trim().isEmpty) {
      await dismissSheet();
      return;
    }

    if (WakeWordMatcher.isCancelIntent(
      query,
      profile: voiceProfile,
      activeNickname: activeNickname,
    )) {
      await dismissSheet();
      return;
    }

    final stripped = WakeWordMatcher.match(
      query,
      profile: voiceProfile,
      activeNickname: activeNickname,
    );
    if (stripped.kind == WakeMatchKind.cancel) {
      await dismissSheet();
      return;
    }
    if (stripped.kind == WakeMatchKind.wakeOnly) {
      await _listenAndAnswerAfterWake(
        isFollowUp: isFollowUp,
        followUpDepth: followUpDepth,
        turnId: myTurn,
      );
      return;
    }
    final effectiveQuery = stripped.kind == WakeMatchKind.commandWithWake
        ? stripped.remainingCommand
        : query.trim();

    final signOff = WakeWordMatcher.isConversationSignOff(
      effectiveQuery,
      profile: voiceProfile,
      activeNickname: activeNickname,
    );

    _transcriptText = effectiveQuery;
    _replyText = '';
    await _processCommandWithLlm(
      effectiveQuery,
      followUpDepth: followUpDepth,
      closeAfterReply: signOff,
      turnId: myTurn,
    );
  }

  Future<void> _processCommandWithLlm(
    String userMessage, {
    int followUpDepth = 0,
    bool closeAfterReply = false,
    int? turnId,
  }) async {
    final myTurn = turnId ?? _turnId;
    if (myTurn != _turnId) return;
    if (!_isAllowedInCurrentScreen || _emergencyMuted) {
      _busyTurn = false;
      return;
    }
    _followUpListening = false;
    _drowsyReminderActive = false;
    _replyText = '';
    _setPhase(SiriOrbPhase.thinking);

    final currentProf = voiceProfile;

    // 1. Cek Perintah Suara Musik Spotify ("setelkan lagu ...", "putar lagu ...", "pause lagu", "next lagu")
    final handledSpotify = await _tryHandleSpotifyVoiceCommand(
      userMessage,
      profile: currentProf,
      turnId: myTurn,
    );
    if (handledSpotify || myTurn != _turnId) return;

    // 2. Cek Perintah Navigasi Langsung ke Google Maps ("arahkan saya ke Indomaret terdekat", "buka maps ke ...")
    if (_isNavigationRequest(userMessage)) {
      await _handleDirectMapsNavigation(
        userMessage,
        profile: currentProf,
        turnId: myTurn,
      );
      return;
    }

    final places = await _gatherRelevantPlaces(userMessage);
    if (myTurn != _turnId) return;

    final det = _driverResultProvider();
    final state = LlmDriverState.fromDetection(
      det,
      tripMinutes: _tripMinutesProvider(),
    );
    final sid = LlmChatApi.sanitizeSessionId(_sessionIdProvider());

    final res = await _chatApi.sendSafe(
      sessionId: sid,
      message: userMessage,
      driverState: state,
      buddyName: activeNickname,
      voiceProfile: currentProf.name,
      nearbyPlaces: places,
    );
    if (myTurn != _turnId) return;
    if (!_isAllowedInCurrentScreen || _emergencyMuted || _phase == SiriOrbPhase.hidden) {
      _busyTurn = false;
      return;
    }

    // Pisahkan error putus sinyal seluler ("SOS saja" / terowongan) vs kuota server habis!
    final isNetworkSignalLost = res.fallback &&
        (res.error == 'unreachable' || res.error == 'timeout');
    if (isNetworkSignalLost) {
      final isEn = LanguageService.instance.isEnglish;
      final offlineMsg = BuddyTtsService.offlineSignalTextFor(
        currentProf,
        isEnglish: isEn,
      );
      _replyText = offlineMsg;
      notifyListeners();
      await _tts.speakOfflineSignalNotice(
        currentProf,
        onPlaybackStart: () {
          if (myTurn != _turnId) return;
          _replyText = offlineMsg;
          _setPhase(SiriOrbPhase.speaking);
        },
      );
      if (myTurn != _turnId) return;
      _scheduleDismissAndResume();
      return;
    }

    final isFurinaTired = res.fallback && currentProf == BuddyVoiceProfile.furina;
    final displayReply = isFurinaTired
        ? BuddyTtsService.furinaTiredText
        : res.reply;

    // Tampilkan teks jawaban seketika (~0.4 detik) begitu LLM selesai berpikir tanpa menunggu unduhan audio!
    _replyText = displayReply;
    notifyListeners();

    final shouldSwitchToJane = await _tts.speakReply(
      profile: currentProf,
      text: res.reply,
      isTiredFallback: isFurinaTired,
      isDrowsyDriver:
          det.status == DriverStatus.drowsy || det.status == DriverStatus.sleep,
      onPlaybackStart: () {
        if (myTurn != _turnId) return;
        _replyText = displayReply;
        _setPhase(SiriOrbPhase.speaking);
      },
    );
    if (myTurn != _turnId) return;

    if (shouldSwitchToJane || isFurinaTired) {
      await BuddyTtsService.activateJaneHandoff();
      if (isFurinaTired &&
          _isAllowedInCurrentScreen &&
          !_emergencyMuted &&
          _phase != SiriOrbPhase.hidden) {
        final isEn = LanguageService.instance.isEnglish;
        final janeFollowUp = isEn
            ? 'Hi! Jane is here with you now. Drive safely and call me anytime!'
            : 'Halo! Sekarang Jane yang temenin kamu di jalan ya. Panggil Jane kapan saja!';
        _replyText = janeFollowUp;
        notifyListeners();
        await _tts.speakReply(
          profile: BuddyVoiceProfile.jane,
          text: janeFollowUp,
          onPlaybackStart: () {
            if (myTurn != _turnId) return;
            _replyText = janeFollowUp;
            _setPhase(SiriOrbPhase.speaking);
          },
        );
        if (myTurn != _turnId) return;
      }
    }

    final isFarewell = closeAfterReply ||
        WakeWordMatcher.isConversationSignOff(
          userMessage,
          profile: voiceProfile,
          activeNickname: activeNickname,
        );

    if (isFarewell || followUpDepth >= _maxFollowUpTurns) {
      _scheduleDismissAndResume();
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (myTurn != _turnId) return;
    if (!_isAllowedInCurrentScreen || _emergencyMuted || _phase == SiriOrbPhase.hidden) {
      _busyTurn = false;
      return;
    }
    await _listenAndAnswerAfterWake(
      isFollowUp: true,
      followUpDepth: followUpDepth + 1,
      turnId: myTurn,
    );
  }

  Future<bool> _tryHandleSpotifyVoiceCommand(
    String userMessage, {
    required BuddyVoiceProfile profile,
    required int turnId,
  }) async {
    final trimmedMsg = userMessage.trim();
    final low = trimmedMsg.toLowerCase();
    final spotifyCtrl = SpotifyIslandController.instance;
    final isEn = LanguageService.instance.isEnglish;

    // 1. Perintah menghentikan / menutup lagu sepenuhnya (tanpa keluar aplikasi)
    final isStopOrClose = RegExp(
      r'\b(?:hentikan|stop|matikan|matiin|tutup|udahin|sudahi)\s+(?:lagu(?:nya)?|musik(?:nya)?|spotify)\b|\b(?:lagu(?:nya)?|musik(?:nya)?)\s+(?:dihentikan|distop|dimatikan|stop\s+dulu|matiin\s+aja)\b',
      caseSensitive: false,
    ).hasMatch(low);
    if (isStopOrClose && spotifyCtrl.isVisible) {
      await spotifyCtrl.closeIsland();
      final stopMsg = isEn
          ? 'Okay, I have stopped the music for you.'
          : 'Oke, musiknya udah aku hentikan ya.';
      _replyText = stopMsg;
      notifyListeners();
      await _tts.speakReply(
        profile: profile,
        text: stopMsg,
        onPlaybackStart: () {
          if (turnId != _turnId) return;
          _replyText = stopMsg;
          _setPhase(SiriOrbPhase.speaking);
        },
      );
      if (turnId != _turnId) return true;
      _scheduleDismissAndResume();
      return true;
    }

    // 2. Perintah jeda sementara (pause)
    final isPauseCmd = RegExp(
      r'\b(?:pause|jeda)\s+(?:lagu(?:nya)?|musik(?:nya)?|dulu)?\b',
      caseSensitive: false,
    ).hasMatch(low);
    if (isPauseCmd && spotifyCtrl.isVisible) {
      await spotifyCtrl.pausePlayback();
      final pauseMsg = isEn
          ? 'Paused the song for now.'
          : 'Oke, lagunya aku jeda dulu ya.';
      _replyText = pauseMsg;
      notifyListeners();
      await _tts.speakReply(
        profile: profile,
        text: pauseMsg,
        onPlaybackStart: () {
          if (turnId != _turnId) return;
          _replyText = pauseMsg;
          _setPhase(SiriOrbPhase.speaking);
        },
      );
      if (turnId != _turnId) return true;
      _scheduleDismissAndResume();
      return true;
    }

    // 3. Perintah lanjutkan lagu (resume)
    final isResumeCmd = RegExp(
      r'\b(?:lanjutkan|lanjutin|lanjut\s+putar|play\s+lagi|nyalakan\s+lagi)\s*(?:lagu(?:nya)?|musik(?:nya)?)?\b',
      caseSensitive: false,
    ).hasMatch(low);
    if (isResumeCmd && spotifyCtrl.isVisible && !spotifyCtrl.isPlaying) {
      await dismissSheet();
      await spotifyCtrl.resumePlayback();
      return true;
    }

    // 4. Perintah lagu sebelumnya / ulangi lagu
    final isPrevCmd = RegExp(
      r'\b(?:lagu\s+sebelumnya|musik\s+sebelumnya|balik\s+ke\s+lagu\s+tadi|previous\s+song|ulang\s+lagu(?:nya)?)\b',
      caseSensitive: false,
    ).hasMatch(low);
    if (isPrevCmd && spotifyCtrl.isVisible) {
      final prevTrack = await spotifyCtrl.skipPrevious();
      if (turnId != _turnId) return true;
      final prevMsg = isEn
          ? 'Going back to ${prevTrack.title} by ${prevTrack.artist}.'
          : 'Oke, balik ke lagu ${prevTrack.title} dari ${prevTrack.artist} ya.';
      _replyText = prevMsg;
      notifyListeners();
      await _tts.speakReply(
        profile: profile,
        text: prevMsg,
        onPlaybackStart: () {
          if (turnId != _turnId) return;
          _replyText = prevMsg;
          _setPhase(SiriOrbPhase.speaking);
        },
      );
      if (turnId != _turnId) return true;
      await dismissSheet();
      return true;
    }

    // 5. Perintah ganti ke lagu spesifik ATAU setel lagu baru:
    //    mis. "ganti lagu ke Last Night on Earth", "ubah lagu Cancer", "setelkan lagu ..."
    final switchSpecificMatch = RegExp(
      r'^(?:tolong\s+|coba\s+|eh\s+)?(?:ganti|gantiin|ubah|pindah(?:kan)?)\s+(?:lagu(?:nya)?|musik(?:nya)?)\s+(?:ke|jadi|dengan)?\s*(.+?)(?:\s+di\s+spotify|\s+lewat\s+spotify|\s+dong|\s+ya)?$',
      caseSensitive: false,
    ).firstMatch(trimmedMsg);

    // 6. Perintah ganti lagu berikutnya secara umum (tanpa menyebut judul spesifik)
    final isGenericNext = switchSpecificMatch == null &&
        RegExp(
          r'\b(?:next\s+lagu|next\s+musik|next\s+song|skip\s+lagu|lagu\s+selanjutnya|lagu\s+berikutnya|lagu\s+lain|ganti\s+lagu(?:nya)?|ganti\s+musik(?:nya)?)\b',
          caseSensitive: false,
        ).hasMatch(low);
    if (isGenericNext && spotifyCtrl.isVisible) {
      await spotifyCtrl.pausePlayback();
      final nextTrack = await spotifyCtrl.skipNext();
      if (turnId != _turnId) return true;
      await spotifyCtrl.pausePlayback();
      final nextMsg = isEn
          ? 'Switching to ${nextTrack.title} by ${nextTrack.artist} now.'
          : 'Oke, kita ganti ke lagu ${nextTrack.title} dari ${nextTrack.artist} ya.';
      _replyText = nextMsg;
      notifyListeners();
      await _tts.speakReply(
        profile: profile,
        text: nextMsg,
        onPlaybackStart: () {
          if (turnId != _turnId) return;
          _replyText = nextMsg;
          _setPhase(SiriOrbPhase.speaking);
        },
      );
      if (turnId != _turnId) return true;
      await dismissSheet();
      await spotifyCtrl.resumePlayback();
      return true;
    }

    final playMatch = switchSpecificMatch ??
        RegExp(
          r'(?:tolong\s+|coba\s+)?(?:setelkan|setelin|setel|putarkan|putarin|putar|play|nyalakan|nyalain|mainkan)\s+(?:lagu\s+|musik\s+)?(.+?)(?:\s+di\s+spotify|\s+lewat\s+spotify|\s+dong|\s+ya)?$',
          caseSensitive: false,
        ).firstMatch(trimmedMsg);

    final bool mentionsSpotifyConnect =
        low.contains('hubungkan spotify') || low.contains('konek spotify') || low.contains('connect spotify');

    if (playMatch == null && !mentionsSpotifyConnect) {
      return false;
    }

    await spotifyCtrl.init();
    if (turnId != _turnId) return true;

    // Jika pengguna belum klik Hubungkan, otomatis aktifkan Dynamic Island in-app agar lagu tetap langsung jalan mulus!
    if (!spotifyCtrl.isConnected) {
      await spotifyCtrl.connectSpotify(openAppToAuthorize: false);
    }

    if (mentionsSpotifyConnect && playMatch == null) {
      final alreadyMsg = isEn
          ? 'Spotify Dynamic Island is active! Just tell me what song you want to hear.'
          : 'Pemutar Spotify Dynamic Island kamu sudah aktif kok, tinggal bilang mau diputerin lagu apa ya.';
      _replyText = alreadyMsg;
      notifyListeners();
      await _tts.speakReply(
        profile: profile,
        text: alreadyMsg,
        onPlaybackStart: () {
          if (turnId != _turnId) return;
          _replyText = alreadyMsg;
          _setPhase(SiriOrbPhase.speaking);
        },
      );
      if (turnId != _turnId) return true;
      await _listenAndAnswerAfterWake(isFollowUp: true, turnId: turnId);
      return true;
    }

    final rawSongQuery = (playMatch?.group(1) ?? '')
        .replaceAll(RegExp(r'\bspotify\b', caseSensitive: false), '')
        .trim();
    if (rawSongQuery.isEmpty) return false;

    final track = await spotifyCtrl.fetchTrackMetadata(rawSongQuery);
    if (turnId != _turnId) return true;

    // Hentikan lagu lama bila sedang berputar supaya suara asisten jernih sebelum lagu baru mulai
    if (spotifyCtrl.isPlaying) {
      await spotifyCtrl.pausePlayback();
    }

    final confirmMsg = isEn
        ? 'Okay, playing ${track.title} by ${track.artist} right here for you.'
        : 'Oke, aku puterin lagu ${track.title} dari ${track.artist} sekarang ya.';
    _replyText = confirmMsg;
    notifyListeners();
    await _tts.speakReply(
      profile: profile,
      text: confirmMsg,
      onPlaybackStart: () {
        if (turnId != _turnId) return;
        _replyText = confirmMsg;
        _setPhase(SiriOrbPhase.speaking);
      },
    );
    if (turnId != _turnId) return true;

    // Sembunyikan Orb ke mode idle, lalu langsung jalankan stream di Dynamic Island (TANPA keluar ke halaman Spotify!)
    await dismissSheet();
    await spotifyCtrl.playSongOnIsland(track, isDrivingSession: _isDrivingActive);
    return true;
  }

  PlaceCategory? _detectPlaceCategory(String query) {
    final low = query.toLowerCase();
    if (low.contains('indomaret') ||
        low.contains('alfamart') ||
        low.contains('alfamidi') ||
        low.contains('minimarket') ||
        low.contains('warung') ||
        low.contains('beli minum')) {
      return PlaceCategory.minimarket;
    }
    if (low.contains('spbu') ||
        low.contains('bensin') ||
        low.contains('pertamina') ||
        low.contains('pom')) {
      return PlaceCategory.spbu;
    }
    if (low.contains('hotel') ||
        low.contains('menginap') ||
        low.contains('penginapan') ||
        low.contains('motel')) {
      return PlaceCategory.lodging;
    }
    if (low.contains('rest area') || low.contains('istirahat')) {
      return PlaceCategory.restArea;
    }
    return null;
  }

  Future<List<NearbyPlace>> _resolveRawPlaces(String query) async {
    final low = query.toLowerCase();
    final wantedCat = _detectPlaceCategory(query);

    List<NearbyPlace> raw = nearby.placesFor(wantedCat);
    DriverFix? fix = nearby.fix;
    if (fix == null || !fix.isValid) {
      try {
        fix = await _fallbackGps.currentFix(timeout: const Duration(seconds: 4));
      } catch (_) {}
    }

    if (raw.isEmpty && fix != null && fix.isValid) {
      try {
        final direct = await _directPlaces.nearby(
          lat: fix.lat,
          lng: fix.lng,
          category: wantedCat,
          headingDeg: fix.headingDeg,
          limit: 8,
        );
        raw = direct.places;
      } catch (_) {}
    }

    if (low.contains('indomaret')) {
      final filtered = raw
          .where((p) => p.name.toLowerCase().contains('indomaret'))
          .toList();
      if (filtered.isNotEmpty) raw = filtered;
    } else if (low.contains('alfamart')) {
      final filtered = raw
          .where((p) => p.name.toLowerCase().contains('alfamart'))
          .toList();
      if (filtered.isNotEmpty) raw = filtered;
    } else if (low.contains('alfamidi')) {
      final filtered = raw
          .where((p) => p.name.toLowerCase().contains('alfamidi'))
          .toList();
      if (filtered.isNotEmpty) raw = filtered;
    }
    return raw;
  }

  Future<List<LlmNearbyPlaceBrief>> _gatherRelevantPlaces(String query) async {
    final raw = await _resolveRawPlaces(query);
    return raw
        .take(5)
        .map(
          (p) => LlmNearbyPlaceBrief(
            name: p.name,
            category: p.categoryLabel.isNotEmpty ? p.categoryLabel : p.categoryKey,
            distanceM: p.distanceM.round(),
            address: p.address,
            ahead: p.ahead,
          ),
        )
        .toList();
  }

  bool _isNavigationRequest(String query) {
    final low = query.toLowerCase();
    return low.contains('arahkan') ||
        low.contains('arahin') ||
        low.contains('antar saya') ||
        low.contains('antarkan') ||
        low.contains('anterin') ||
        low.contains('tunjukkan jalan') ||
        low.contains('navigasi') ||
        low.contains('rute ke') ||
        low.contains('buka maps') ||
        low.contains('buka google map') ||
        low.contains('navigate to') ||
        low.contains('directions to');
  }

  String _extractCleanDestinationLabel(String query) {
    final cleaned = query
        .replaceAll(
          RegExp(
            r'^(?:tolong\s+|coba\s+)?(?:arahkan|arahin|antarkan|anterin|navigasi|tunjukkan\s+jalan|buka\s+google\s+maps?|buka\s+maps?|rute)(?:\s+saya|\s+aku)?(?:\s+ke|\s+menuju)?\s*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    return cleaned.isNotEmpty ? cleaned : query.trim();
  }

  Future<void> _handleDirectMapsNavigation(
    String userMessage, {
    required BuddyVoiceProfile profile,
    required int turnId,
  }) async {
    final rawPlaces = await _resolveRawPlaces(userMessage);
    if (turnId != _turnId) return;

    final isEn = LanguageService.instance.isEnglish;
    final NearbyPlace? target = rawPlaces.isNotEmpty ? rawPlaces.first : null;
    final destLabel = target != null
        ? target.name
        : _extractCleanDestinationLabel(userMessage);

    final navReply = target != null
        ? (isEn
              ? 'Okay, opening Google Maps route to ${target.name}, about ${target.distanceM.round()} meters away.'
              : 'Oke, aku bukain rute Google Maps ke ${target.name} sekarang ya, jaraknya sekitar ${target.distanceM.round()} meter.')
        : (isEn
              ? 'Okay, opening Google Maps route to $destLabel now.'
              : 'Oke, aku bukain Google Maps menuju $destLabel sekarang ya.');

    _replyText = navReply;
    notifyListeners();

    await _tts.speakReply(
      profile: profile,
      text: navReply,
      onPlaybackStart: () {
        if (turnId != _turnId) return;
        _replyText = navReply;
        _setPhase(SiriOrbPhase.speaking);
      },
    );
    if (turnId != _turnId) return;

    // Munculkan notifikasi persisten/balik cepat persis seperti klik manual tempat terdekat!
    if (_isDrivingActive) {
      await DrivingNotificationService.instance.showMonitoringNotification();
    } else {
      await DrivingNotificationService.instance.showQuickReturnNotification(
        title: '📍 Navigasi ke $destLabel Aktif',
        body: 'Ketuk notifikasi ini kapan saja untuk kembali ke Driving Buddy.',
      );
    }

    // Sembunyikan asisten ke mode idle sebelum berpindah ke Google Maps
    await dismissSheet();

    if (target != null) {
      await PlaceLauncher.navigate(target);
    } else {
      final fix = nearby.fix;
      await PlaceLauncher.openLiveSearchInBrowser(
        destLabel,
        fix?.lat,
        fix?.lng,
      );
    }
  }

  void _scheduleDismissAndResume({
    Duration delay = const Duration(milliseconds: 520),
  }) {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(delay, () async {
      if (_phase != SiriOrbPhase.hidden) {
        _setPhase(SiriOrbPhase.dismissing);
        await Future<void>.delayed(_dismissAnimDuration);
        if (_phase == SiriOrbPhase.dismissing) {
          _setPhase(SiriOrbPhase.hidden);
        }
      }
      _drowsyReminderActive = false;
      _busyTurn = false;
      if (_enabled && _isAllowedInCurrentScreen && !_emergencyMuted) {
        await _resumePassiveWakeWatch();
      }
    });
  }

  void _setPhase(SiriOrbPhase next) {
    if (_phase == next) return;
    _phase = next;
    _watchdog?.cancel();
    if (next == SiriOrbPhase.hidden) {
      _lastTurnEnd = DateTime.now();
    } else {
      _watchdog = Timer(_turnWatchdog, () {
        if (_phase != SiriOrbPhase.hidden) unawaited(dismissSheet());
      });
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _insideAuthenticatedApp = false;
    _dismissTimer?.cancel();
    _resumeAfterCallTimer?.cancel();
    _watchdog?.cancel();
    _authSub?.cancel();
    BuddyVoiceConfig.instance.removeListener(_onConfigChanged);
    _stt.inputEnergy.removeListener(_syncEnergy);
    _stt.inputFrequency.removeListener(_syncEnergy);
    _stt.livePartialText.removeListener(_onPartialChanged);
    _tts.speechEnergy.removeListener(_syncEnergy);
    _tts.speechFrequency.removeListener(_syncEnergy);
    unawaited(_stt.dispose());
    unawaited(_tts.dispose());
    _directPlaces.close();
    _chatApi.close();
    super.dispose();
  }
}
