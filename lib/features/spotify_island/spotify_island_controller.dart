import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
  });

  final String title;
  final String artist;
  final String coverUrl;
  final String previewUrl;
  final int durationSec;
  final String spotifyQuery;
  final String streamPath;

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
  bool _isVisible = false;
  bool _isClosing = false;
  bool _isExpanded = false;

  /// True HANYA saat stream audio benar-benar sedang mengeluarkan suara (PlayerState.playing),
  /// sehingga timer & piringan vinyl tidak pernah jalan duluan sebelum lagu terdengar!
  bool _isPlaying = false;
  bool _isBuffering = false;
  int _playSessionToken = 0;

  double _currentTimeSec = 0.0;
  double _durationSec = 210.0;

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
  bool get isVisible => _isVisible;
  bool get isClosing => _isClosing;
  bool get isExpanded => _isExpanded;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  double get currentTimeSec => _currentTimeSec;
  double get durationSec => _durationSec;
  SpotifyTrackInfo get currentTrack => _track;

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
      final playedLongEnough = _currentTimeSec >= 3.0;
      _currentTimeSec = 0.0;
      notifyListeners();
      // Otomatis putar lagu berikutnya di antrean hanya jika lagu benar-benar sudah diputar
      if (playedLongEnough && _isVisible && !_isClosing && _playlist.length > 1) {
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
    notifyListeners();
  }

  /// Mengaktifkan integrasi Spotify Dynamic Island langsung di dalam Driving Buddy
  /// tanpa memaksa pengguna berpindah ke layar aplikasi luar.
  Future<bool> connectSpotify({bool openAppToAuthorize = false}) async {
    await refreshInstallStatus();
    _isConnected = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefConnectedKey, _isConnected);
    } catch (_) {}
    notifyListeners();
    return _isConnected;
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

  /// Memutar lagu otomatis 100% di dalam Dynamic Island Driving Buddy tanpa pernah membuka layar Spotify!
  /// Timer (`0:00`) dan piringan vinyl ditahan diam selama buffering dan baru berjalan saat audio berbunyi.
  Future<void> playSongOnIsland(
    SpotifyTrackInfo track, {
    bool isDrivingSession = false,
  }) async {
    await init();
    final myToken = ++_playSessionToken;

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

    // ── LANGKAH 1: Minta URL audio CDN langsung (progressive MP3/M4A atau HLS M3U8)
    // Endpoint mode=url mengembalikan JSON {"url":"https://...","mime":"...","duration_s":N}
    // Ini memungkinkan audioplayers/ExoPlayer memainkan audio seekable tanpa server proxy.
    String? directUrl;
    String? directMime;
    try {
      final metaUri = Uri.parse('$baseUrl/music/stream?q=$encodedQ&dur=$dur&mode=url');
      final metaResp = await _http.get(metaUri).timeout(const Duration(seconds: 10));
      if (metaResp.statusCode == 200) {
        final data = jsonDecode(metaResp.body) as Map<String, dynamic>;
        directUrl = (data['url'] as String?)?.trim();
        directMime = (data['mime'] as String?)?.trim();
        final resolvedDur = (data['duration_s'] as num?)?.toInt() ?? 0;
        if (resolvedDur >= 60 && (resolvedDur - _durationSec).abs() >= 2.0) {
          _durationSec = resolvedDur.toDouble();
          notifyListeners();
        }
      }
    } catch (_) {}

    if (sessionToken != _playSessionToken || !_isVisible || _isClosing) return;

    // ── LANGKAH 2: Putar dari URL CDN langsung (progressive MP3 / HLS M3U8)
    if (directUrl != null && directUrl.startsWith('http')) {
      try {
        await _audioPlayer.setVolume(0.92);
        // audioplayers v5 + ExoPlayer mendukung HLS (m3u8) dan progressive MP3/M4A
        await _audioPlayer.play(UrlSource(directUrl));
        if (sessionToken != _playSessionToken) return;
        return; // Sukses!
      } catch (_) {
        if (sessionToken != _playSessionToken || !_isVisible || _isClosing) return;
      }
    }

    // ── LANGKAH 3: Fallback ke preview 30 detik dari iTunes/Deezer (tetap tanpa keluar app)
    if (track.previewUrl.isNotEmpty) {
      try {
        _durationSec = 30.0;
        notifyListeners();
        await _audioPlayer.setVolume(0.92);
        await _audioPlayer.play(UrlSource(track.previewUrl));
        return;
      } catch (_) {}
    }

    // ── LANGKAH 4: Semua sumber gagal — reset buffering tanpa auto-skip
    if (sessionToken == _playSessionToken) {
      _isBuffering = false;
      _isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> pausePlayback() async {
    if (!_isVisible) return;
    _isBuffering = false;
    await _audioPlayer.pause();
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> resumePlayback() async {
    if (!_isVisible) return;
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
    unawaited(
      _audioPlayer.seek(
        Duration(milliseconds: (target * 1000).round()),
      ),
    );
    notifyListeners();
  }

  /// Di-pause paksa saat Sirine Darurat Microsleep berbunyi demi keselamatan pengemudi!
  Future<void> pauseForEmergencyAlarm() async {
    if (_isPlaying || _isBuffering) {
      _playSessionToken++;
      _isBuffering = false;
      await _audioPlayer.pause();
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
    _playSessionToken++;
    _isClosing = true;
    _isExpanded = false;
    _isBuffering = false;
    _isPlaying = false;
    notifyListeners();

    await _audioPlayer.stop();
    _currentTimeSec = 0.0;

    await Future<void>.delayed(const Duration(milliseconds: 280));
    _isVisible = false;
    _isClosing = false;
    notifyListeners();
  }
}
