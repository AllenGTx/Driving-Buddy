import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../services/device_control_service.dart';
import '../llm_chat/llm_chat_config.dart';

class SpotifyTrackInfo {
  const SpotifyTrackInfo({
    required this.title,
    required this.artist,
    required this.coverUrl,
    required this.previewUrl,
    required this.durationSec,
    required this.spotifyQuery,
    this.streamPath = '',
    this.coverBytes,
    this.isAd = false,
  });

  final String title;
  final String artist;
  final String coverUrl;
  final String previewUrl;
  final int durationSec;
  final String spotifyQuery;
  final String streamPath;
  final Uint8List? coverBytes;
  final bool isAd;

  SpotifyTrackInfo copyWith({
    String? title,
    String? artist,
    String? coverUrl,
    String? previewUrl,
    int? durationSec,
    String? spotifyQuery,
    String? streamPath,
    Uint8List? coverBytes,
    bool? isAd,
  }) {
    return SpotifyTrackInfo(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      coverUrl: coverUrl ?? this.coverUrl,
      previewUrl: previewUrl ?? this.previewUrl,
      durationSec: durationSec ?? this.durationSec,
      spotifyQuery: spotifyQuery ?? this.spotifyQuery,
      streamPath: streamPath ?? this.streamPath,
      coverBytes: coverBytes ?? this.coverBytes,
      isAd: isAd ?? this.isAd,
    );
  }

  factory SpotifyTrackInfo.fromJson(Map<String, dynamic> data, String fallbackQuery) {
    final title = (data['title'] ?? fallbackQuery).toString().trim();
    final artist = (data['artist'] ?? 'Spotify').toString().trim();
    final dur = ((data['duration_s'] ?? 210) as num).toInt().clamp(30, 900);
    final spQuery = (data['spotify_query'] ?? '$title $artist').toString().trim();
    final rawStreamPath = (data['stream_path'] ?? '').toString().trim();
    return SpotifyTrackInfo(
      title: title.isNotEmpty ? title : fallbackQuery,
      artist: artist.isNotEmpty ? artist : 'Spotify',
      coverUrl: (data['cover_url'] ?? '').toString(),
      previewUrl: (data['preview_url'] ?? '').toString(),
      durationSec: dur,
      spotifyQuery: spQuery,
      streamPath: rawStreamPath.isNotEmpty
          ? rawStreamPath
          : '/music/stream?q=${Uri.encodeQueryComponent(spQuery)}&dur=$dur',
    );
  }
}

class SpotifyIslandController extends ChangeNotifier {
  SpotifyIslandController._();
  static final SpotifyIslandController instance = SpotifyIslandController._();

  static const String _prefConnectedKey = 'spotify_buddy_connected_v1';

  final http.Client _http = http.Client();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _initialized = false;
  bool _isConnected = false;
  bool _isSpotifyInstalled = false;
  bool _isNotificationAccessGranted = false;
  bool _isVisible = false;
  bool _isClosing = false;
  bool _isExpanded = false;
  bool _nativeSpotifyMode = false;

  /// True HANYA saat stream audio benar-benar sedang mengeluarkan suara (PlayerState.playing),
  /// sehingga timer & piringan vinyl tidak pernah jalan duluan sebelum lagu terdengar!
  bool _isPlaying = false;
  bool _isBuffering = false;
  int _playSessionToken = 0;
  File? _activeMusicFile;

  String _lastArtHash = '';
  DateTime? _nativeLaunchGraceUntil;
  String _previousNativeSignature = '';
  Timer? _nativePollTimer;
  bool _syncInFlight = false;

  double _currentTimeSec = 0.0;
  double _durationSec = 210.0;

  // Guard agar onPlayerComplete tidak trigger auto-next saat user sedang drag slider
  bool _isSeeking = false;

  List<SpotifyTrackInfo> _playlist = const [];
  int _playlistIndex = 0;

  SpotifyTrackInfo _track = const SpotifyTrackInfo(
    title: 'Last Night on Earth',
    artist: 'Green Day',
    coverUrl: '',
    previewUrl: '',
    durationSec: 237,
    spotifyQuery: 'Last Night on Earth Green Day',
  );

  bool get isConnected => _isConnected;
  bool get isSpotifyInstalled => _isSpotifyInstalled;
  bool get isNotificationAccessGranted => _isNotificationAccessGranted;
  bool get isNativeSpotifyMode => _nativeSpotifyMode;
  bool get isVisible => _isVisible;
  bool get isClosing => _isClosing;
  bool get isExpanded => _isExpanded;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  double get currentTimeSec => _currentTimeSec;
  double get durationSec => _durationSec;
  SpotifyTrackInfo get currentTrack => _track;
  SpotifyTrackInfo? get nextTrack =>
      _playlist.length > 1 ? _playlist[(_playlistIndex + 1) % _playlist.length] : null;
  int get playlistCount => _playlist.length;

  Future<void> init() async {
    if (_initialized) {
      await refreshInstallStatus();
      return;
    }
    _initialized = true;

    await _audioPlayer.setReleaseMode(ReleaseMode.stop);

    // Sinkronkan status putar, waktu jalan, dan durasi murni dari event AudioPlayer nyata!
    _audioPlayer.onPlayerStateChanged.listen((state) {
      final nowPlaying = state == PlayerState.playing;
      bool changed = false;
      if (_isPlaying != nowPlaying) {
        _isPlaying = nowPlaying;
        changed = true;
      }
      if (nowPlaying && _isBuffering) {
        _isBuffering = false;
        changed = true;
      }
      if (changed) notifyListeners();
    });

    _audioPlayer.onPositionChanged.listen((pos) {
      if (!_isVisible || _isClosing) return;
      final sec = pos.inMilliseconds / 1000.0;
      if (sec > 0.05 && _isBuffering) {
        _isBuffering = false;
      }
      if (sec > _durationSec && sec < 900.0) {
        _durationSec = sec;
      }
      if ((sec - _currentTimeSec).abs() >= 0.2) {
        _currentTimeSec = sec.clamp(0.0, _durationSec);
        notifyListeners();
      }
    });

    _audioPlayer.onDurationChanged.listen((dur) {
      final sec = dur.inMilliseconds / 1000.0;
      if (sec >= 12.0 && (sec - _durationSec).abs() >= 1.0) {
        _durationSec = sec;
        if (_currentTimeSec > _durationSec) {
          _currentTimeSec = _durationSec;
        }
        notifyListeners();
      }
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      _isPlaying = false;
      _isBuffering = false;
      // Guard: jangan auto-skip jika lagu gagal dalam 3 detik pertama
      // (stream URL invalid = AudioPlayer selesai instan → bukan akhir lagu sungguhan)
      // Guard tambahan: jangan auto-skip saat user sedang drag slider
      final playedLongEnough = _currentTimeSec >= 3.0;
      _currentTimeSec = 0.0;
      notifyListeners();
      // Otomatis putar lagu berikutnya di antrean hanya jika lagu benar-benar sudah diputar
      if (playedLongEnough && !_isSeeking && _isVisible && !_isClosing && _playlist.length > 1) {
        unawaited(skipNext());
      }
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      _isConnected = prefs.getBool(_prefConnectedKey) ?? false;
    } catch (_) {}
    await refreshInstallStatus();
  }

  Future<void> refreshInstallStatus() async {
    _isSpotifyInstalled = await DeviceControlService.instance.isSpotifyInstalled();
    _isNotificationAccessGranted =
        await DeviceControlService.instance.isNotificationAccessGranted();
    if (!_isSpotifyInstalled && _isConnected) {
      _isConnected = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_prefConnectedKey, false);
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Mengaktifkan integrasi Spotify hanya jika aplikasi Spotify benar-benar terpasang di perangkat.
  Future<bool> connectSpotify({bool openAppToAuthorize = false}) async {
    await refreshInstallStatus();
    if (!_isSpotifyInstalled) {
      _isConnected = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_prefConnectedKey, false);
      } catch (_) {}
      notifyListeners();
      return false;
    }
    _isConnected = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefConnectedKey, true);
    } catch (_) {}
    notifyListeners();
    return true;
  }

  /// Sinkronkan lifecycle app:
  /// - Home (`paused`): lagu tetap berjalan, Dynamic Island tetap ada, polling sementara dihentikan.
  /// - Kembali dari Home (`resumed`): cek apakah session native masih aktif; jika iya, sync jam & lagu real-time.
  Future<void> handleAppLifecycle(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _nativePollTimer?.cancel();
      _nativePollTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      await refreshInstallStatus();
      if (_isVisible && !_isClosing) {
        if (_nativeSpotifyMode) {
          final sessionAlive =
              await DeviceControlService.instance.isDynamicIslandSessionActive();
          if (!sessionAlive) {
            await _hideIslandImmediately();
            return;
          }
          await syncFromNativeSpotifyNow();
          _startNativePlaybackPolling();
        } else {
          // Mode In-App Stream: Dynamic Island harus SELALU tetap ada selama musik diputar / aktif
          await DeviceControlService.instance.setDynamicIslandSessionActive(true);
          notifyListeners();
        }
      }
    }
  }

  Future<void> _hideIslandImmediately() async {
    _nativePollTimer?.cancel();
    _nativePollTimer = null;
    _playSessionToken++;
    _nativeSpotifyMode = false;
    _isVisible = false;
    _isClosing = false;
    _isExpanded = false;
    _isBuffering = false;
    _isPlaying = false;
    _currentTimeSec = 0.0;
    notifyListeners();
  }

  Future<void> disconnectSpotify() async {
    _isConnected = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefConnectedKey, false);
    } catch (_) {}
    if (_isVisible) {
      await closeIsland();
    } else {
      notifyListeners();
    }
  }

  /// Kecilkan volume musik sementara saat asisten suara sedang berbicara agar suara Buddy terdengar jelas.
  Future<void> setBuddySpeechDucking(bool duck) async {
    if (!_isVisible) return;
    try {
      await _audioPlayer.setVolume(duck ? 0.20 : 0.92);
    } catch (_) {}
  }

  void toggleExpanded() {
    if (!_isVisible || _isClosing) return;
    _isExpanded = !_isExpanded;
    notifyListeners();
  }

  void collapseExpanded() {
    if (!_isExpanded) return;
    _isExpanded = false;
    notifyListeners();
  }

  Future<SpotifyTrackInfo> fetchTrackMetadata(String rawQuery) async {
    try {
      await LlmChatConfig.shared.load();
      final uri = Uri.parse(
        '${LlmChatConfig.shared.baseUrl}/music/search?q=${Uri.encodeQueryComponent(rawQuery)}',
      );
      final resp = await _http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final rawTracks = data['tracks'];
        if (rawTracks is List && rawTracks.isNotEmpty) {
          final parsed = rawTracks
              .whereType<Map>()
              .map((m) => SpotifyTrackInfo.fromJson(Map<String, dynamic>.from(m), rawQuery))
              .toList();
          if (parsed.isNotEmpty) {
            _playlist = parsed;
            _playlistIndex = 0;
            return parsed.first;
          }
        }
        final single = SpotifyTrackInfo.fromJson(data, rawQuery);
        _playlist = [single];
        _playlistIndex = 0;
        return single;
      }
    } catch (_) {}

    final fallback = SpotifyTrackInfo(
      title: rawQuery,
      artist: 'Spotify',
      coverUrl: '',
      previewUrl: '',
      durationSec: 210,
      spotifyQuery: rawQuery,
      streamPath: '/music/stream?q=${Uri.encodeQueryComponent(rawQuery)}&dur=210',
    );
    _playlist = [fallback];
    _playlistIndex = 0;
    return fallback;
  }

  String _fetchedCoverSignature = '';

  /// Tampilkan metadata lagu di Dynamic Island TANPA memulai stream internal.
  /// Digunakan saat Spotify native yang memutar lagu (`playing on device`),
  /// lalu menyinkronkan lagu rekomendasi berikutnya, iklan, & waktu putar real-time dari MediaSession Spotify.
  Future<void> showIslandMetadataOnly(
    SpotifyTrackInfo track, {
    bool isDrivingSession = false,
    String? previousSessionSignature,
  }) async {
    await init();
    _playSessionToken++; // batalkan stream internal lama jika ada
    _nativeSpotifyMode = true;
    _lastArtHash = '';
    _fetchedCoverSignature = '';
    _nativeLaunchGraceUntil = DateTime.now().add(const Duration(seconds: 4));
    _previousNativeSignature = previousSessionSignature ?? '';

    if (_playlist.isEmpty || _playlist.every((t) => t.spotifyQuery != track.spotifyQuery)) {
      _playlist = [track, ..._playlist.where((t) => t.spotifyQuery != track.spotifyQuery)].take(8).toList();
      _playlistIndex = 0;
    }

    // Hentikan stream internal (Spotify native yang handle audio sepenuhnya)
    await _audioPlayer.stop();
    final oldFile = _activeMusicFile;
    _activeMusicFile = null;
    if (oldFile != null) unawaited(oldFile.delete().catchError((_) => oldFile));

    _track = track;
    _currentTimeSec = 0.0;
    _durationSec = track.durationSec.toDouble();
    _isClosing = false;
    _isVisible = true;
    _isPlaying = true;
    _isBuffering = false;
    notifyListeners();

    await DeviceControlService.instance.setDynamicIslandSessionActive(true);
    _startNativePlaybackPolling();
  }

  void _startNativePlaybackPolling() {
    _nativePollTimer?.cancel();
    // Interval 2 detik mencegah MethodChannel terlalu sering memanggil AudioManager
    // yang bisa menyebabkan stuttering pada beberapa ROM Android
    _nativePollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(syncFromNativeSpotifyNow());
    });
  }

  /// Hentikan polling sementara (misalnya saat ganti lagu) agar tidak bentrok.
  void pauseNativePolling() {
    _nativePollTimer?.cancel();
    _nativePollTimer = null;
  }

  /// Lanjutkan polling setelah jeda (misalnya setelah lagu baru mulai).
  void resumeNativePolling() {
    if (_isVisible && _nativeSpotifyMode) {
      _startNativePlaybackPolling();
    }
  }

  /// Baca state real-time langsung dari MediaSession Spotify (judul, artis, iklan, durasi, posisi ms).
  /// Dipanggil tiap 1 detik dan seketika saat pengguna kembali dari tombol Home.
  Future<void> syncFromNativeSpotifyNow() async {
    if (!_isVisible || _isClosing || !_nativeSpotifyMode || _syncInFlight) return;
    _syncInFlight = true;
    try {
      final snap = await DeviceControlService.instance.getSpotifyPlaybackState(
        lastArtHash: _lastArtHash,
      );
      if (!_isVisible || _isClosing || !_nativeSpotifyMode) return;

      if (snap != null) {
        _isNotificationAccessGranted = snap.listenerGranted;
        if (snap.listenerGranted && snap.hasSession) {
          final snapSig = '${snap.title}|${snap.artist}';
          final grace = _nativeLaunchGraceUntil;
          if (grace != null && DateTime.now().isBefore(grace)) {
            final stalePausedOldTrack = !snap.isPlaying &&
                _previousNativeSignature.isNotEmpty &&
                snapSig == _previousNativeSignature;
            if (stalePausedOldTrack) {
              return;
            }
          }
          _nativeLaunchGraceUntil = null;

          final nextTitle = snap.title.isNotEmpty
              ? snap.title
              : (snap.isAd ? 'Iklan Spotify' : _track.title);
          final nextArtist = snap.artist.isNotEmpty
              ? snap.artist
              : (snap.isAd ? 'Spotify Advertisement' : _track.artist);
          final nextDurSec = snap.durationMs >= 1000
              ? (snap.durationMs / 1000.0)
              : _durationSec;
          final nextPosSec = (snap.positionMs / 1000.0).clamp(0.0, nextDurSec);

          final trackChanged = nextTitle != _track.title ||
              nextArtist != _track.artist ||
              snap.isAd != _track.isAd;

          Uint8List? nextCoverBytes = _track.coverBytes;
          String nextCoverUrl = _track.coverUrl;
          if (snap.artBytes != null) {
            nextCoverBytes = snap.artBytes;
            _lastArtHash = snap.artHash;
          } else if (snap.isAd) {
            nextCoverBytes = null;
            nextCoverUrl = '';
            _lastArtHash = snap.artHash;
          } else if (trackChanged && snap.artHash != _lastArtHash) {
            nextCoverBytes = null;
            nextCoverUrl = '';
            _lastArtHash = snap.artHash;
            unawaited(_enrichCoverForTrack(nextTitle, nextArtist));
          }

          _track = _track.copyWith(
            title: nextTitle,
            artist: nextArtist,
            coverUrl: nextCoverUrl,
            coverBytes: nextCoverBytes,
            durationSec: nextDurSec.round().clamp(1, 3600),
            spotifyQuery: '$nextTitle $nextArtist'.trim(),
            isAd: snap.isAd,
          );
          _durationSec = nextDurSec;
          _currentTimeSec = nextPosSec;
          _isPlaying = snap.isPlaying;
          _isBuffering = false;
          notifyListeners();
          return;
        }
      }

      // Fallback bila Akses Notifikasi belum diaktifkan: tetap sinkronkan isMusicActive + timer pasif
      final playing = await DeviceControlService.instance.isSystemMusicActive();
      if (_isPlaying != playing) {
        _isPlaying = playing;
      }
      if (_isPlaying) {
        _currentTimeSec = (_currentTimeSec + 2.0).clamp(0.0, _durationSec);
      }
      notifyListeners();
    } catch (_) {
    } finally {
      _syncInFlight = false;
    }
  }

  Future<void> _enrichCoverForTrack(String title, String artist) async {
    final sig = '$title|$artist';
    if (_fetchedCoverSignature == sig || title.isEmpty) return;
    _fetchedCoverSignature = sig;
    try {
      await LlmChatConfig.shared.load();
      final q = Uri.encodeQueryComponent('$title $artist'.trim());
      final uri = Uri.parse('${LlmChatConfig.shared.baseUrl}/music/search?q=$q');
      final resp = await _http.get(uri).timeout(const Duration(seconds: 4));
      if (resp.statusCode != 200 || !_isVisible || _isClosing) return;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final rawTracks = data['tracks'];
      String foundCover = (data['cover_url'] ?? '').toString();
      if (rawTracks is List && rawTracks.isNotEmpty && rawTracks.first is Map) {
        foundCover = (rawTracks.first['cover_url'] ?? foundCover).toString();
      }
      if (foundCover.isNotEmpty && '${_track.title}|${_track.artist}' == sig) {
        _track = _track.copyWith(coverUrl: foundCover);
        notifyListeners();
      }
    } catch (_) {}
  }

  String _prewarmQuery = '';
  Future<Map<String, dynamic>?>? _prewarmFuture;
  String _prewarmYtQuery = '';
  Future<String?>? _prewarmYtUrlFuture;

  Future<AudioOnlyStreamInfo?> _pickBestM4aStream(
    YoutubeExplode yt,
    String videoId,
  ) async {
    StreamManifest? manifest;
    try {
      manifest = await yt.videos.streamsClient
          .getManifest(
            videoId,
            ytClients: [YoutubeApiClient.androidVr, YoutubeApiClient.ios],
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      try {
        manifest = await yt.videos.streamsClient
            .getManifest(
              videoId,
              ytClients: [YoutubeApiClient.tv, YoutubeApiClient.android],
            )
            .timeout(const Duration(seconds: 12));
      } catch (_) {
        manifest = null;
      }
    }
    if (manifest == null || manifest.audioOnly.isEmpty) return null;

    final m4aStreams = manifest.audioOnly
        .where((s) =>
            s.codec.mimeType.contains('mp4') ||
            s.codec.mimeType.contains('m4a'))
        .toList();
    final poolStreams = m4aStreams.isNotEmpty
        ? m4aStreams
        : manifest.audioOnly.toList();
    final compactM4a = poolStreams
        .where((s) => s.bitrate.kiloBitsPerSecond <= 165)
        .toList();
    final pickFrom = compactM4a.isNotEmpty ? compactM4a : poolStreams;
    return pickFrom.isNotEmpty
        ? pickFrom.reduce((a, b) =>
            a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b)
        : manifest.audioOnly.withHighestBitrate();
  }

  /// Pre-resolve metadata stream audio + URL YoutubeExplode secara paralel saat asisten berbicara.
  Future<void> prewarmTrackStream(SpotifyTrackInfo track) async {
    final q = track.spotifyQuery.trim();
    if (q.isEmpty) return;
    _prewarmQuery = q;
    _prewarmYtQuery = q;
    final metaFuture = () async {
      try {
        await LlmChatConfig.shared.load();
        final baseUrl = LlmChatConfig.shared.baseUrl;
        final encodedQ = Uri.encodeQueryComponent(q);
        final metaUri = Uri.parse('$baseUrl/music/stream?q=$encodedQ&dur=${track.durationSec}&mode=url');
        final metaResp = await _http.get(metaUri).timeout(const Duration(seconds: 9));
        if (metaResp.statusCode == 200) {
          return jsonDecode(metaResp.body) as Map<String, dynamic>;
        }
      } catch (_) {}
      return null;
    }();
    _prewarmFuture = metaFuture;

    _prewarmYtUrlFuture = () async {
      final data = await metaFuture;
      final vid = (data?['yt_video_id'] as String?)?.trim() ?? '';
      if (vid.isEmpty) return null;
      final yt = YoutubeExplode();
      try {
        final streamInfo = await _pickBestM4aStream(yt, vid);
        final u = streamInfo?.url.toString() ?? '';
        return u.startsWith('http') ? u : null;
      } catch (_) {
        return null;
      } finally {
        yt.close();
      }
    }();

    await metaFuture;
  }

  /// Memutar lagu otomatis 100% di dalam Dynamic Island Driving Buddy tanpa pernah membuka layar Spotify!
  /// Timer (`0:00`) dan piringan vinyl ditahan diam selama buffering dan baru berjalan saat audio berbunyi.
  Future<void> playSongOnIsland(
    SpotifyTrackInfo track, {
    bool isDrivingSession = false,
  }) async {
    await init();
    final myToken = ++_playSessionToken;
    _nativeSpotifyMode = false;
    _nativePollTimer?.cancel();
    _nativePollTimer = null;

    if (_playlist.isEmpty || _playlist.every((t) => t.spotifyQuery != track.spotifyQuery)) {
      _playlist = [track, ..._playlist.where((t) => t.spotifyQuery != track.spotifyQuery)].take(8).toList();
      _playlistIndex = 0;
    }

    await _audioPlayer.stop();

    _track = track;
    _currentTimeSec = 0.0;
    _durationSec = track.durationSec.toDouble();
    _isClosing = false;
    _isVisible = true;
    _isPlaying = false;
    _isBuffering = true;
    notifyListeners();

    await DeviceControlService.instance.setDynamicIslandSessionActive(true);
    await _startInAppTrackStream(track, sessionToken: myToken);
  }

  Future<void> _startInAppTrackStream(
    SpotifyTrackInfo track, {
    required int sessionToken,
  }) async {
    await LlmChatConfig.shared.load();
    if (sessionToken != _playSessionToken || !_isVisible || _isClosing) return;

    final baseUrl = LlmChatConfig.shared.baseUrl;
    final encodedQ = Uri.encodeQueryComponent(track.spotifyQuery);
    final dur = track.durationSec;

    // ── LANGKAH 1: Gunakan hasil prewarm jika query sama, atau minta metadata sumber audio utuh
    String? resolvedUrl;
    String? resolvedMode;
    String? resolvedMime;
    String? resolvedYtVideoId;
    int resolvedDur = 0;
    try {
      Map<String, dynamic>? data;
      if (_prewarmQuery == track.spotifyQuery.trim() && _prewarmFuture != null) {
        data = await _prewarmFuture;
      }
      if (data == null) {
        final metaUri = Uri.parse('$baseUrl/music/stream?q=$encodedQ&dur=$dur&mode=url');
        final metaResp = await _http.get(metaUri).timeout(const Duration(seconds: 10));
        if (metaResp.statusCode == 200) {
          data = jsonDecode(metaResp.body) as Map<String, dynamic>;
        }
      }
      if (data != null) {
        resolvedUrl = (data['url'] as String?)?.trim();
        resolvedMode = (data['mode'] as String?)?.trim();
        resolvedMime = (data['mime'] as String?)?.trim();
        resolvedYtVideoId = (data['yt_video_id'] as String?)?.trim();
        resolvedDur = (data['duration_s'] as num?)?.toInt() ?? 0;
        if (resolvedDur >= 60 && (resolvedDur - _durationSec).abs() >= 2.0) {
          _durationSec = resolvedDur.toDouble();
          notifyListeners();
        }
      }
    } catch (_) {}

    if (sessionToken != _playSessionToken || !_isVisible || _isClosing) return;

    // ── LANGKAH 1B: Jika backend mengembalikan yt_video_id (karena server terblokir label),
    // ekstrak langsung stream audio m4a penuh menggunakan IP HP pengguna sendiri.
    // Gunakan hasil prewarm jika sudah siap saat asisten berbicara, lalu putar langsung via UrlSource (instan <0.5s)!
    if (resolvedYtVideoId != null &&
        resolvedYtVideoId.isNotEmpty) {
      if (_prewarmYtQuery == track.spotifyQuery.trim() && _prewarmYtUrlFuture != null) {
        try {
          final prewarmedUrl = await _prewarmYtUrlFuture;
          if (sessionToken != _playSessionToken || !_isVisible || _isClosing) return;
          if (prewarmedUrl != null && prewarmedUrl.startsWith('http')) {
            if (resolvedDur > 60 && (_durationSec - resolvedDur).abs() >= 2) {
              _durationSec = resolvedDur.toDouble();
              notifyListeners();
            }
            await _audioPlayer.setVolume(0.92);
            await _audioPlayer.play(UrlSource(prewarmedUrl));
            if (sessionToken != _playSessionToken) return;
            return;
          }
        } catch (_) {
          if (sessionToken != _playSessionToken || !_isVisible || _isClosing) return;
        }
      }

      final yt = YoutubeExplode();
      try {
        final audioStream = await _pickBestM4aStream(yt, resolvedYtVideoId);
        if (sessionToken != _playSessionToken || !_isVisible || _isClosing) return;
        if (audioStream != null) {
          final ytAudioUrl = audioStream.url.toString();
          // 1) Utama: putar langsung via UrlSource (mulai instan tanpa tunggu unduh penuh!)
          if (ytAudioUrl.startsWith('http')) {
            try {
              if (resolvedDur > 60 && (_durationSec - resolvedDur).abs() >= 2) {
                _durationSec = resolvedDur.toDouble();
                notifyListeners();
              }
              await _audioPlayer.setVolume(0.92);
              await _audioPlayer.play(UrlSource(ytAudioUrl));
              if (sessionToken != _playSessionToken) return;
              return;
            } catch (_) {
              if (sessionToken != _playSessionToken || !_isVisible || _isClosing) return;
            }
          }

          // 2) Cadangan: jika UrlSource ditolak (mis. 403 header), unduh ke file temp via YoutubeHttpClient
          // Unduh chunk demi chunk — mulai putar begitu cukup data masuk (>= 256 KB)
          try {
            final dir = await getTemporaryDirectory();
            final nextFile = File('${dir.path}/buddy_track_$sessionToken.m4a');
            final sink = nextFile.openWrite();
            bool startedPlaying = false;
            int bytesWritten = 0;
            try {
              await (() async {
                await for (final chunk in yt.videos.streamsClient.get(audioStream)) {
                  if (sessionToken != _playSessionToken || !_isVisible || _isClosing) {
                    break;
                  }
                  sink.add(chunk);
                  bytesWritten += chunk.length;
                  // Mulai putar begitu ada >256 KB — tidak perlu tunggu unduh penuh
                  if (!startedPlaying && bytesWritten >= 262144) {
                    startedPlaying = true;
                    await sink.flush();
                    if (sessionToken == _playSessionToken && _isVisible && !_isClosing) {
                      if (resolvedDur > 60 && (_durationSec - resolvedDur).abs() >= 2) {
                        _durationSec = resolvedDur.toDouble();
                        notifyListeners();
                      }
                      await _audioPlayer.setVolume(0.92);
                      await _audioPlayer.play(DeviceFileSource(nextFile.path));
                    }
                  }
                }
              })().timeout(const Duration(seconds: 60));
              await sink.flush();
            } finally {
              await sink.close();
            }

            if (sessionToken != _playSessionToken || !_isVisible || _isClosing) {
              unawaited(nextFile.delete().catchError((_) => nextFile));
              return;
            }

            if (!startedPlaying && nextFile.existsSync() && nextFile.lengthSync() > 16384) {
              final prevFile = _activeMusicFile;
              _activeMusicFile = nextFile;
              if (prevFile != null && prevFile.path != nextFile.path) {
                unawaited(prevFile.delete().catchError((_) => prevFile));
              }
              if (resolvedDur > 60 && (_durationSec - resolvedDur).abs() >= 2) {
                _durationSec = resolvedDur.toDouble();
                notifyListeners();
              }
              await _audioPlayer.setVolume(0.92);
              await _audioPlayer.play(DeviceFileSource(nextFile.path));
              return;
            } else if (startedPlaying) {
              final prevFile = _activeMusicFile;
              _activeMusicFile = nextFile;
              if (prevFile != null && prevFile.path != nextFile.path) {
                unawaited(prevFile.delete().catchError((_) => prevFile));
              }
              return;
            } else {
              unawaited(nextFile.delete().catchError((_) => nextFile));
            }
          } catch (_) {
            if (sessionToken != _playSessionToken || !_isVisible || _isClosing) return;
          }
        }
      } catch (_) {
        // YoutubeExplode gagal/timeout → lanjut ke fallback berikutnya
        if (sessionToken != _playSessionToken || !_isVisible || _isClosing) return;
      } finally {
        yt.close();
      }
    }

    // ── LANGKAH 2A: Putar dari URL progresif langsung (MP3/M4A)
    // Backend mengirim mode='direct_url' (bukan 'direct')
    if (resolvedUrl != null && (resolvedMode == 'direct_url' || resolvedMode == 'direct') && resolvedUrl.startsWith('http')) {
      try {
        await _audioPlayer.setVolume(0.92);
        await _audioPlayer.play(UrlSource(resolvedUrl));
        if (sessionToken != _playSessionToken) return;
        return;
      } catch (_) {
        if (sessionToken != _playSessionToken || !_isVisible || _isClosing) return;
      }
    }

    // ── LANGKAH 2B: Unduh file audio penuh ke cache lokal lalu putar lewat DeviceFileSource (0:00 -> selesai!)
    if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
      final fullDownloadUrl = resolvedUrl.startsWith('http')
          ? resolvedUrl
          : '$baseUrl$resolvedUrl';
      try {
        final fileResp = await _http
            .get(Uri.parse(fullDownloadUrl))
            .timeout(const Duration(seconds: 18));
        if (sessionToken != _playSessionToken || !_isVisible || _isClosing) return;
        if (fileResp.statusCode == 200 && fileResp.bodyBytes.length > 8192) {
          final dir = await getTemporaryDirectory();
          final ext = (resolvedMime ?? '').contains('mpeg') ? 'mp3' : 'mp4';
          final nextFile = File('${dir.path}/buddy_track_$sessionToken.$ext');
          await nextFile.writeAsBytes(fileResp.bodyBytes, flush: true);
          if (sessionToken != _playSessionToken || !_isVisible || _isClosing) {
            unawaited(nextFile.delete().catchError((_) => nextFile));
            return;
          }
          final prevFile = _activeMusicFile;
          _activeMusicFile = nextFile;
          if (prevFile != null && prevFile.path != nextFile.path) {
            unawaited(prevFile.delete().catchError((_) => prevFile));
          }
          await _audioPlayer.setVolume(0.92);
          await _audioPlayer.play(DeviceFileSource(nextFile.path));
          return;
        }
      } catch (_) {
        if (sessionToken != _playSessionToken || !_isVisible || _isClosing) return;
      }
    }

    // ── LANGKAH 3: Fallback ke preview 30 detik resmi HANYA bila tidak ada yt_video_id.
    // Jika yt_video_id tersedia berarti backend sudah menemukan video resmi — JANGAN putar preview 30s.
    final hasYtVideoId = resolvedYtVideoId != null && resolvedYtVideoId.isNotEmpty;
    if (!hasYtVideoId && track.previewUrl.isNotEmpty) {
      try {
        _durationSec = 30.0;
        notifyListeners();
        await _audioPlayer.setVolume(0.92);
        await _audioPlayer.play(UrlSource(track.previewUrl));
        return;
      } catch (_) {}
    }

    if (sessionToken == _playSessionToken) {
      _isBuffering = false;
      _isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> pausePlayback() async {
    if (!_isVisible) return;
    _isBuffering = false;
    if (_nativeSpotifyMode) {
      await DeviceControlService.instance.sendMediaCommand('pause');
      _isPlaying = false;
      notifyListeners();
      return;
    }
    await _audioPlayer.pause();
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> resumePlayback() async {
    if (!_isVisible) return;
    if (_nativeSpotifyMode) {
      await DeviceControlService.instance.sendMediaCommand('play');
      _isPlaying = true;
      notifyListeners();
      unawaited(Future<void>.delayed(
        const Duration(milliseconds: 250),
        syncFromNativeSpotifyNow,
      ));
      return;
    }
    if (_currentTimeSec <= 0.05 && !_isPlaying) {
      await _startInAppTrackStream(_track, sessionToken: ++_playSessionToken);
      return;
    }
    await _audioPlayer.resume();
  }

  Future<void> togglePlayPause() async {
    if (!_isVisible || _isClosing) return;
    if (_isPlaying) {
      await pausePlayback();
    } else {
      await resumePlayback();
    }
  }

  Future<SpotifyTrackInfo> skipNext() async {
    if (_nativeSpotifyMode) {
      await DeviceControlService.instance.sendMediaCommand('next');
      await Future<void>.delayed(const Duration(milliseconds: 650));
      await syncFromNativeSpotifyNow();
      return _track;
    }
    if (_playlist.length > 1) {
      _playlistIndex = (_playlistIndex + 1) % _playlist.length;
      final nextTrack = _playlist[_playlistIndex];
      await playSongOnIsland(nextTrack);
      return nextTrack;
    }
    // Jika hanya 1 lagu di daftar, cari variasi lagu berikutnya dari artis yang sama
    final moreQuery = '${_track.artist} popular songs';
    await fetchTrackMetadata(moreQuery);
    if (_playlist.isNotEmpty) {
      final diffIdx = _playlist.indexWhere(
        (t) => t.title.toLowerCase() != _track.title.toLowerCase(),
      );
      _playlistIndex = diffIdx >= 0 ? diffIdx : 0;
      final chosen = _playlist[_playlistIndex];
      await playSongOnIsland(chosen);
      return chosen;
    }
    seekTo(0.0);
    await resumePlayback();
    return _track;
  }

  Future<SpotifyTrackInfo> skipPrevious() async {
    if (_nativeSpotifyMode) {
      await DeviceControlService.instance.sendMediaCommand('previous');
      await Future<void>.delayed(const Duration(milliseconds: 650));
      await syncFromNativeSpotifyNow();
      return _track;
    }
    if (_currentTimeSec > 4.0 || _playlist.length <= 1) {
      seekTo(0.0);
      if (!_isPlaying) {
        await resumePlayback();
      }
      return _track;
    }
    _playlistIndex = (_playlistIndex - 1 + _playlist.length) % _playlist.length;
    final prevTrack = _playlist[_playlistIndex];
    await playSongOnIsland(prevTrack);
    return prevTrack;
  }

  void seekTo(double seconds) {
    final target = seconds.clamp(0.0, _durationSec);
    _currentTimeSec = target;
    if (_nativeSpotifyMode) {
      unawaited(DeviceControlService.instance.seekSpotify((target * 1000).round()));
      notifyListeners();
      return;
    }
    unawaited(
      _audioPlayer.seek(
        Duration(milliseconds: (target * 1000).round()),
      ),
    );
    notifyListeners();
  }

  /// Dipanggil saat drag slider DIMULAI — freeze onPlayerComplete agar tidak trigger auto-next
  void onSeekStart() {
    _isSeeking = true;
  }

  /// Dipanggil saat drag slider SELESAI — seek final sekali saja, lalu buka guard
  void onSeekEnd(double seconds) {
    seekTo(seconds);
    // Tunda sedikit agar AudioPlayer selesai seek sebelum guard dibuka
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      _isSeeking = false;
    });
  }

  /// Di-pause paksa saat Sirine Darurat Microsleep berbunyi demi keselamatan pengemudi!
  Future<void> pauseForEmergencyAlarm() async {
    if (_isPlaying || _isBuffering) {
      _playSessionToken++;
      _isBuffering = false;
      if (_nativeSpotifyMode) {
        await DeviceControlService.instance.sendMediaCommand('pause');
      } else {
        await _audioPlayer.pause();
      }
      _isPlaying = false;
      notifyListeners();
    }
    await DeviceControlService.instance.setAudioDucking(
      enable: true,
      exclusive: true,
    );
  }

  /// Menutup Dynamic Island sepenuhnya (mengecil dan naik ke atas lalu hilang, serta menghentikan audio).
  Future<void> closeIsland() async {
    if (!_isVisible || _isClosing) return;
    _nativePollTimer?.cancel();
    _nativePollTimer = null;
    _playSessionToken++;
    _isClosing = true;
    _isExpanded = false;
    _isBuffering = false;
    final wasPlayingNative = _nativeSpotifyMode && _isPlaying;
    _isPlaying = false;
    notifyListeners();

    if (wasPlayingNative) {
      await DeviceControlService.instance.sendMediaCommand('pause');
    }
    await DeviceControlService.instance.setDynamicIslandSessionActive(false);
    await _audioPlayer.stop();
    _currentTimeSec = 0.0;
    final oldFile = _activeMusicFile;
    _activeMusicFile = null;
    if (oldFile != null) {
      unawaited(oldFile.delete().catchError((_) => oldFile));
    }

    await Future<void>.delayed(const Duration(milliseconds: 280));
    _nativeSpotifyMode = false;
    _isVisible = false;
    _isClosing = false;
    notifyListeners();
  }
}
