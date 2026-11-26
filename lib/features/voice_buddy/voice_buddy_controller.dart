import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/thresholds.dart';
import '../../models/detection_result.dart';
import '../../services/language_service.dart';
import '../llm_chat/llm_chat.dart';
import '../nearby_places/data/direct_osm_places_api.dart';
import '../nearby_places/logic/nearby_controller.dart';
import '../nearby_places/models/nearby_place.dart';
import '../nearby_places/models/place_category.dart';
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
            // Begitu user keluar / berada di Login atau Register, matikan paksa pendengar suara!
            _insideAuthenticatedApp = false;
            unawaited(_forceSilenceOnAuthExit());
          }
        });
      } catch (_) {}
    }
  }

  static const String _prefEnabledKey = 'buddy_voice_enabled';
  static const Duration _dismissAnimDuration = Duration(milliseconds: 300);

  final NearbyPlacesController nearby;
  String Function() _sessionIdProvider;
  DetectionResult Function() _driverResultProvider;
  int Function() _tripMinutesProvider;
  final bool requireFirebaseAuth;

  final LlmChatApi _chatApi;
  final BuddySttService _stt;
  final BuddyTtsService _tts;
  final DirectOsmPlacesApi _directPlaces = DirectOsmPlacesApi();
  StreamSubscription<User?>? _authSub;

  bool _enabled = false;
  bool _insideAuthenticatedApp = false;
  bool _emergencyMuted = false;
  bool _busyTurn = false;
  bool _holdingPtt = false;
  bool _followUpListening = false;
  int _turnId = 0;
  DateTime _pttDownAt = DateTime.fromMillisecondsSinceEpoch(0);

  SiriOrbPhase _phase = SiriOrbPhase.hidden;
  String _transcriptText = '';
  String _replyText = '';
  double _orbEnergy = 0.0;
  double _orbFrequency = 0.45;
  DateTime _lastDrowsySpeech = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _dismissTimer;
  Timer? _watchdog;
  DateTime _lastTurnEnd = DateTime.fromMillisecondsSinceEpoch(0);

  /// Jeda singkat agar gema speaker sendiri tidak langsung memicu panggilan ulang.
  static const Duration _echoGuard = Duration(milliseconds: 650);
  static const Duration _turnWatchdog = Duration(seconds: 90);
  static const Duration _initialWakeSilenceTimeout = Duration(milliseconds: 3200);
  static const Duration _followUpSilenceTimeout = Duration(milliseconds: 4200);
  static const int _maxFollowUpTurns = 12;

  bool get isEnabled => _enabled;
  bool get isHoldingPtt => _holdingPtt;
  bool get isFollowUpListening => _followUpListening;
  SiriOrbPhase get phase => _phase;
  bool get isSheetVisible => _phase != SiriOrbPhase.hidden;
  String get transcriptText => _transcriptText;
  String get replyText => _replyText;
  double get orbEnergy => _orbEnergy;
  double get orbFrequency => _orbFrequency;
  String get activeNickname => BuddyVoiceConfig.instance.activeNickname;
  BuddyVoiceProfile get voiceProfile => BuddyVoiceConfig.instance.profile;

  bool get _isAllowedInCurrentScreen {
    if (!_insideAuthenticatedApp) return false;
    if (!requireFirebaseAuth) return true;
    try {
      final u = FirebaseAuth.instance.currentUser;
      return u != null && u.emailVerified;
    } catch (_) {
      return _insideAuthenticatedApp;
    }
  }

  /// Dipanggil oleh `MainShell` saat pengguna sudah masuk ke dalam aplikasi utama
  /// (Beranda, Berkendara, Riwayat) dan otomatis dimatikan saat keluar ke Login/Register.
  Future<void> setInsideAuthenticatedApp(bool inside) async {
    if (_insideAuthenticatedApp == inside) return;
    _insideAuthenticatedApp = inside;
    if (!inside) {
      await _forceSilenceOnAuthExit();
    } else if (_enabled && !_emergencyMuted && !_busyTurn) {
      await _resumePassiveWakeWatch();
    }
  }

  Future<void> _forceSilenceOnAuthExit() async {
    _turnId++;
    _dismissTimer?.cancel();
    _holdingPtt = false;
    _followUpListening = false;
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

  void handleAppLifecycle(AppLifecycleState state, {bool isDriving = false}) {
    final backgrounded =
        state == AppLifecycleState.paused || state == AppLifecycleState.detached;
    _stt.setAppBackgrounded(backgrounded, keepActiveInDrive: isDriving);
  }

  Future<void> init({bool insideMainApp = false}) async {
    _insideAuthenticatedApp = insideMainApp;
    await BuddyVoiceConfig.instance.load();
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
  }

  void _onPartialChanged() {
    if (_phase == SiriOrbPhase.listening) {
      final p = _stt.livePartialText.value;
      if (p.isNotEmpty) {
        _transcriptText = p;
        notifyListeners();
      }
    }
  }

  void _syncEnergy() {
    final nextE = _phase == SiriOrbPhase.speaking
        ? _tts.speechEnergy.value
        : (_phase == SiriOrbPhase.listening ? _stt.inputEnergy.value : 0.0);
    final nextF = _phase == SiriOrbPhase.speaking
        ? _tts.speechFrequency.value
        : (_phase == SiriOrbPhase.listening ? _stt.inputFrequency.value : 0.42);
    if ((nextE - _orbEnergy).abs() > 0.012 ||
        (nextF - _orbFrequency).abs() > 0.025) {
      _orbEnergy = nextE;
      _orbFrequency = nextF;
      notifyListeners();
    }
  }

  Future<bool> setEnabled(bool next) async {
    if (_enabled == next) return _enabled;
    if (next) {
      final granted = await _stt.ensureMicPermission();
      if (!granted) {
        _enabled = false;
        notifyListeners();
        return false;
      }
      await BuddyVoiceConfig.instance.load();
      _enabled = true;
      _saveEnabledPref(true);
      notifyListeners();
      if (_isAllowedInCurrentScreen) {
        await _resumePassiveWakeWatch();
      }
      return true;
    } else {
      _turnId++;
      _enabled = false;
      _holdingPtt = false;
      _followUpListening = false;
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

  void setEmergencyAlertActive(bool active) {
    if (_emergencyMuted == active) return;
    _emergencyMuted = active;
    if (active) {
      _turnId++;
      _dismissTimer?.cancel();
      _holdingPtt = false;
      _followUpListening = false;
      _stt.finishActiveCaptureNow();
      unawaited(_tts.stop());
      unawaited(_stt.pauseWakeWordWatch());
      if (_phase != SiriOrbPhase.hidden) {
        _phase = SiriOrbPhase.hidden;
        _busyTurn = false;
        notifyListeners();
      }
    } else if (_enabled && _isAllowedInCurrentScreen) {
      unawaited(_resumePassiveWakeWatch());
    }
  }

  Future<void> maybeSpeakDrowsyReminder({required int yawnCount}) async {
    if (!_enabled || !_isAllowedInCurrentScreen || _emergencyMuted || _busyTurn) {
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastDrowsySpeech) < Thresholds.buddyDrowsyTtsCooldown) {
      return;
    }
    _lastDrowsySpeech = now;
    _busyTurn = true;
    _dismissTimer?.cancel();
    await _stt.pauseWakeWordWatch();

    final chosenDrowsy = _tts.pickDrowsyReminderText(yawnCount: yawnCount);
    _transcriptText = '';
    _replyText = '';
    _setPhase(SiriOrbPhase.summon);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!_enabled || !_isAllowedInCurrentScreen || _emergencyMuted) {
      _busyTurn = false;
      return;
    }
    await _tts.speakDrowsyReminder(
      profile: voiceProfile,
      yawnCount: yawnCount,
      chosenText: chosenDrowsy,
      onPlaybackStart: () {
        _replyText = chosenDrowsy;
        _setPhase(SiriOrbPhase.speaking);
      },
    );
    _scheduleDismissAndResume();
  }

  Future<void> onOrbTapped() async {
    if (!_isAllowedInCurrentScreen || _emergencyMuted) return;
    if (!_enabled) {
      final ok = await setEnabled(true);
      if (!ok) return;
    }
    _dismissTimer?.cancel();
    if (_phase == SiriOrbPhase.speaking) {
      final myTurn = ++_turnId;
      _busyTurn = true;
      await _tts.stop();
      if (myTurn != _turnId) return;
      await _listenAndAnswerAfterWake(turnId: myTurn);
      return;
    }
    if (!_busyTurn || _phase == SiriOrbPhase.dismissing) {
      final myTurn = ++_turnId;
      _busyTurn = true;
      await _listenAndAnswerAfterWake(turnId: myTurn);
    }
  }

  Future<void> onPushToTalkDown() async {
    if (!_isAllowedInCurrentScreen || _emergencyMuted) return;
    final granted = await _stt.ensureMicPermission();
    if (!granted) return;

    _dismissTimer?.cancel();
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
    _dismissTimer?.cancel();
    await _stt.pauseWakeWordWatch();

    if (match.kind == WakeMatchKind.wakeOnly) {
      final chosenAck = _tts.pickWakeAckText(voiceProfile);
      _transcriptText = transcript;
      _replyText = '';
      _setPhase(SiriOrbPhase.summon);
      await Future<void>.delayed(const Duration(milliseconds: 160));
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
    await Future<void>.delayed(const Duration(milliseconds: 160));
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

    final isEn = LanguageService.instance.isEnglish;
    _followUpListening = isFollowUp;
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
      // Pengguna sudah diam selesai mengobrol -> tutup Orb halus ala Siri (0 token)
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
    _replyText = '';
    _setPhase(SiriOrbPhase.thinking);

    final places = await _gatherRelevantPlaces(userMessage);
    if (myTurn != _turnId) return;

    final det = _driverResultProvider();
    final state = LlmDriverState.fromDetection(
      det,
      tripMinutes: _tripMinutesProvider(),
    );
    final sid = LlmChatApi.sanitizeSessionId(_sessionIdProvider());
    final currentProf = voiceProfile;

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
      if (res.fallback && currentProf == BuddyVoiceProfile.furina) {
        await BuddyTtsService.activateJaneHandoff();
      }
      _busyTurn = false;
      return;
    }

    final isFurinaTired = res.fallback && currentProf == BuddyVoiceProfile.furina;
    final displayReply = isFurinaTired
        ? BuddyTtsService.furinaTiredText
        : res.reply;

    final shouldSwitchToJane = await _tts.speakReply(
      profile: currentProf,
      text: res.reply,
      isTiredFallback: res.fallback,
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
            ? 'Hi! Jane is here with you now. Drive safely and call me anytime.'
            : 'Halo! Sekarang Jane yang temenin kamu di jalan ya. Panggil Jane kapan saja.';
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
      // Pengguna sudah pamit/selesai -> tutup Full-Screen Siri Orb + Scrim otomatis
      _scheduleDismissAndResume();
      return;
    }

    // Mode Percakapan Berkelanjutan (Multi-Turn):
    // Jeda akustik singkat 280ms agar ekor suara speaker tidak tertangkap mic,
    // lalu buka jendela dengar lanjutan tanpa perlu memanggil wake-word lagi!
    // Jika pengguna diam selama ~4.2 detik, Orb otomatis menutup halus ala Siri.
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

  Future<List<LlmNearbyPlaceBrief>> _gatherRelevantPlaces(String query) async {
    final low = query.toLowerCase();
    PlaceCategory? wantedCat;
    if (low.contains('indomaret') ||
        low.contains('alfamart') ||
        low.contains('alfamidi') ||
        low.contains('minimarket') ||
        low.contains('warung') ||
        low.contains('beli minum')) {
      wantedCat = PlaceCategory.minimarket;
    } else if (low.contains('spbu') ||
        low.contains('bensin') ||
        low.contains('pertamina') ||
        low.contains('pom')) {
      wantedCat = PlaceCategory.spbu;
    } else if (low.contains('hotel') ||
        low.contains('menginap') ||
        low.contains('penginapan') ||
        low.contains('motel')) {
      wantedCat = PlaceCategory.lodging;
    } else if (low.contains('rest area') || low.contains('istirahat')) {
      wantedCat = PlaceCategory.restArea;
    }

    List<NearbyPlace> raw = nearby.placesFor(wantedCat);
    final fix = nearby.fix;
    if (raw.isEmpty && fix != null) {
      try {
        final direct = await _directPlaces.nearby(
          lat: fix.lat,
          lng: fix.lng,
          category: wantedCat,
          headingDeg: fix.headingDeg,
          limit: 6,
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

  /// Begitu asisten selesai berbicara (~550ms jeda napas alami), langsung tutup
  /// Full-Screen Siri Orb + Scrim dengan animasi ala Siri Apple dan kembali ke siaga!
  void _scheduleDismissAndResume({
    Duration delay = const Duration(milliseconds: 550),
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
