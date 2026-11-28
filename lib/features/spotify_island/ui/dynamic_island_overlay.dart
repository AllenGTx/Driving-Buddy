import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../spotify_island_controller.dart';
import 'spotify_logo_mark.dart';

/// Dynamic Island Music Player (Porting 1:1 dari `DynamicIslandPlayer.tsx` + Driving Buddy Enhancements):
/// - Hanya muncul ketika pengguna meminta putar lagu via Spotify.
/// - Animasi Masuk: turun halus dari atas (`translateY: -64 -> 0`, `scale: 0.84 -> 1.0`).
/// - Animasi Keluar (tombol X): mengecilkan diri (`scale -> 0.72`) lalu naik ke atas (`translateY -> -58`) dan hilang penuh!
/// - Transisi Pil Kecil (`176x38`) <-> Mode Besar (`max 376 x 198`) menggunakan solver pegas fisik
///   `stiffness = 210, damping = 21` persis web portofolio, lengkap dengan piringan hitam vinyl berputar,
///   marquee teks berjalan, equalizer 6 batang, progress bar seekable, dan tombol `×` opacity rendah di mode besar.
class DynamicIslandOverlay extends StatefulWidget {
  const DynamicIslandOverlay({super.key});

  @override
  State<DynamicIslandOverlay> createState() => _DynamicIslandOverlayState();
}

class _DynamicIslandOverlayState extends State<DynamicIslandOverlay>
    with TickerProviderStateMixin {
  final SpotifyIslandController _ctrl = SpotifyIslandController.instance;

  late final Ticker _springTicker;
  late final AnimationController _mountCtrl;
  Duration _lastTick = Duration.zero;
  double _elapsedSec = 0.0;

  // Solver pegas fisik persis DynamicIslandPlayer.tsx (stiffness = 210, damping = 21)
  double _springPos = 0.0;
  double _springVel = 0.0;
  double _vinylAngle = 0.0;
  double _marqueePhase = 0.0;

  bool _wasMountedVisible = false;

  @override
  void initState() {
    super.initState();
    _mountCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 0.0,
    );
    _ctrl.addListener(_onControllerChanged);
    _springTicker = createTicker(_onSpringTick)..start();
    _onControllerChanged();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (_ctrl.isVisible && !_ctrl.isClosing && !_wasMountedVisible) {
      _wasMountedVisible = true;
      _mountCtrl.animateTo(
        1.0,
        duration: const Duration(milliseconds: 340),
        curve: const Cubic(0.22, 1.0, 0.36, 1.0),
      );
    } else if (_ctrl.isClosing && _wasMountedVisible) {
      _wasMountedVisible = false;
      // Keluar: mengecilkan diri lalu naik ke atas hingga hilang!
      _mountCtrl.animateTo(
        0.0,
        duration: const Duration(milliseconds: 260),
        curve: const Cubic(0.32, 0.0, 0.67, 0.0),
      );
    } else if (!_ctrl.isVisible) {
      _wasMountedVisible = false;
      _mountCtrl.value = 0.0;
    }
    setState(() {});
  }

  void _onSpringTick(Duration now) {
    final dt = _lastTick == Duration.zero
        ? 0.016
        : ((now - _lastTick).inMicroseconds / 1e6).clamp(0.001, 0.033);
    _lastTick = now;

    if (!_ctrl.isVisible && _mountCtrl.value <= 0.001) return;

    _elapsedSec += dt;
    final reducedMotion =
        mounted && (MediaQuery.maybeDisableAnimationsOf(context) ?? false);

    final target = _ctrl.isExpanded ? 1.0 : 0.0;
    if (reducedMotion) {
      _springPos = target;
      _springVel = 0.0;
    } else {
      const double stiffness = 210.0;
      const double damping = 21.0;
      final force = (target - _springPos) * stiffness;
      final accel = force - _springVel * damping;
      _springVel += accel * dt;
      _springPos += _springVel * dt;
      if ((target - _springPos).abs() < 0.001 && _springVel.abs() < 0.002) {
        _springPos = target;
        _springVel = 0.0;
      }
    }

    if (_ctrl.isPlaying && !reducedMotion) {
      _vinylAngle = (_vinylAngle + dt * 1.45) % (2.0 * math.pi);
      _marqueePhase = (_marqueePhase + dt * 32.0) % 10000.0;
    }

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerChanged);
    _springTicker.dispose();
    _mountCtrl.dispose();
    super.dispose();
  }

  String _formatTime(double sec) {
    if (!sec.isFinite || sec < 0) return '0:00';
    final total = sec.floor();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_ctrl.isVisible && _mountCtrl.value <= 0.005) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxExpandedWidth = math.min(384.0, screenWidth - 24.0);

    final p = _springPos;
    final pClamped = p.clamp(0.0, 1.0);

    final width = (178.0 + (maxExpandedWidth - 178.0) * p).clamp(160.0, maxExpandedWidth + 14.0);
    final height = (38.0 + 162.0 * p).clamp(36.0, 214.0);
    final radius = math.min(height / 2.0, 19.0 + 19.0 * pClamped);

    final closedOpacity = (1.0 - pClamped * 3.2).clamp(0.0, 1.0);
    final openOpacity = ((pClamped - 0.25) / 0.52).clamp(0.0, 1.0);

    final mountT = _mountCtrl.value.clamp(0.0, 1.0);
    // Masuk turun dari atas (-62px -> 0), keluar mengecil (0.72) lalu naik ke atas (-62px)
    final slideY = (1.0 - mountT) * -62.0;
    final mountScale = 0.74 + 0.26 * mountT;

    final track = _ctrl.currentTrack;
    final fullLabel = '${track.title} - ${track.artist}';
    final duration = math.max(1.0, _ctrl.durationSec);
    final curSec = _ctrl.currentTimeSec.clamp(0.0, duration);
    final remSec = math.max(0.0, duration - curSec);

    return Positioned.fill(
      child: Stack(
        children: [
          // Klik area luar saat mode besar -> lipat kembali ke pil kecil
          if (_ctrl.isExpanded)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _ctrl.collapseExpanded,
                child: const SizedBox.expand(),
              ),
            ),

          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Opacity(
                  opacity: mountT,
                  child: Transform.translate(
                    offset: Offset(0, slideY),
                    child: Transform.scale(
                      scale: mountScale,
                      alignment: Alignment.topCenter,
                      child: Material(
                        type: MaterialType.transparency,
                        child: GestureDetector(
                          onTap: _ctrl.toggleExpanded,
                          child: Container(
                            width: width,
                            height: height,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: const Color(0xFF050508),
                              borderRadius: BorderRadius.circular(radius),
                              border: Border.all(
                                color: const Color(0xFFFF9E44).withValues(
                                  alpha: 0.24 + 0.14 * pClamped,
                                ),
                                width: 1.4,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFF26B1D).withValues(
                                    alpha: 0.14 + 0.22 * pClamped,
                                  ),
                                  blurRadius: 28,
                                  offset: const Offset(0, 10),
                                ),
                                const BoxShadow(
                                  color: Color(0xE6000000),
                                  blurRadius: 18,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Stack(
                              children: [
                                // 1. Mode Pil Kecil (Closed Pill: Mini Spinning Vinyl + Marquee + Dot)
                                if (closedOpacity > 0.01)
                                  IgnorePointer(
                                    ignoring: closedOpacity < 0.2,
                                    child: Opacity(
                                      opacity: closedOpacity,
                                      child: SizedBox(
                                        height: 38,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 11,
                                          ),
                                          child: Row(
                                            children: [
                                              _MiniVinylDisc(
                                                coverUrl: track.coverUrl,
                                                coverBytes: track.coverBytes,
                                                angle: _vinylAngle,
                                                size: 21,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: ClipRect(
                                                  child: _SmoothMarqueeText(
                                                    text: fullLabel,
                                                    offsetPx: _marqueePhase,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Opacity(
                                                opacity: _ctrl.isPlaying
                                                    ? (0.65 +
                                                              0.35 *
                                                                  math.sin(
                                                                    _elapsedSec *
                                                                        4.5,
                                                                  ))
                                                          .clamp(0.3, 1.0)
                                                    : 0.45,
                                                child: Container(
                                                  width: 8.5,
                                                  height: 8.5,
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFF1ED760,
                                                    ),
                                                    shape: BoxShape.circle,
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: const Color(
                                                          0xFF1ED760,
                                                        ).withValues(alpha: 0.5),
                                                        blurRadius: 6,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                // 2. Mode Besar (Expanded Now Playing: Vinyl Sleeve + Equalizer + Progress + Controls + Low-Opacity Close X)
                                if (openOpacity > 0.01)
                                  IgnorePointer(
                                    ignoring: openOpacity < 0.25,
                                    child: Opacity(
                                      opacity: openOpacity,
                                      child: SingleChildScrollView(
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        child: SizedBox(
                                          width: maxExpandedWidth,
                                          height: 200,
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              18,
                                              15,
                                              16,
                                              14,
                                            ),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceBetween,
                                              children: [
                                                // Baris 1: Sampul Album + Piringan Vinyl Berputar | Judul & Artis | Equalizer + Tombol Close X Opacity Rendah
                                                Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    _SleeveWithSpinningVinyl(
                                                      coverUrl: track.coverUrl,
                                                      coverBytes: track.coverBytes,
                                                      angle: _vinylAngle,
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Row(
                                                            children: [
                                                              if (track.isAd) ...[
                                                                Container(
                                                                  margin: const EdgeInsets.only(right: 6),
                                                                  padding: const EdgeInsets.symmetric(
                                                                    horizontal: 5,
                                                                    vertical: 1.5,
                                                                  ),
                                                                  decoration: BoxDecoration(
                                                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.22),
                                                                    borderRadius: BorderRadius.circular(4),
                                                                    border: Border.all(
                                                                      color: const Color(0xFFF59E0B).withValues(alpha: 0.6),
                                                                      width: 0.7,
                                                                    ),
                                                                  ),
                                                                  child: const Text(
                                                                    'IKLAN',
                                                                    style: TextStyle(
                                                                      fontSize: 8.5,
                                                                      fontWeight: FontWeight.w800,
                                                                      color: Color(0xFFFBBF24),
                                                                      letterSpacing: 0.4,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                              Expanded(
                                                                child: Text(
                                                                  track.title,
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style:
                                                                      const TextStyle(
                                                                        fontSize: 15.5,
                                                                        fontWeight:
                                                                            FontWeight
                                                                                .w800,
                                                                        letterSpacing:
                                                                            -0.3,
                                                                        color: Colors
                                                                            .white,
                                                                      ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          const SizedBox(
                                                            height: 2,
                                                          ),
                                                          Text(
                                                            _ctrl.isBuffering
                                                                ? '${track.artist} · Memuat audio...'
                                                                : (_ctrl.nextTrack != null
                                                                    ? '${track.artist} · Berikutnya: ${_ctrl.nextTrack!.title}'
                                                                    : track.artist),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 12.5,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: Color(
                                                                    0xFFFFB47E,
                                                                  ),
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    _EqualizerBars(
                                                      elapsedSec: _elapsedSec,
                                                      isPlaying: _ctrl.isPlaying,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    // Tombol Close / Silang dengan opacity agak rendah khusus di mode besar!
                                                    Semantics(
                                                      button: true,
                                                      label:
                                                          'Tutup pemutar musik',
                                                      child: GestureDetector(
                                                        onTap: _ctrl.closeIsland,
                                                        child: Opacity(
                                                          opacity: 0.42,
                                                          child: Container(
                                                            width: 26,
                                                            height: 26,
                                                            decoration: BoxDecoration(
                                                              color: Colors.white
                                                                  .withValues(
                                                                    alpha: 0.14,
                                                                  ),
                                                              shape:
                                                                  BoxShape.circle,
                                                            ),
                                                            child: const Icon(
                                                              Icons
                                                                  .close_rounded,
                                                              size: 15,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),

                                                // Baris 2: Waktu Jalan + Progress Slider + Sisa Waktu
                                                Row(
                                                  children: [
                                                    SizedBox(
                                                      width: 34,
                                                      child: Text(
                                                        _formatTime(curSec),
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontFeatures: const [
                                                            FontFeature.tabularFigures(),
                                                          ],
                                                          color: Colors.white
                                                              .withValues(
                                                                alpha: 0.72,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      child: SliderTheme(
                                                        data: SliderThemeData(
                                                          trackHeight: 4.5,
                                                          activeTrackColor:
                                                              const Color(
                                                                0xFFF26B1D,
                                                              ),
                                                          inactiveTrackColor:
                                                              Colors.white
                                                                  .withValues(
                                                                    alpha: 0.20,
                                                                  ),
                                                          thumbColor:
                                                              Colors.white,
                                                          thumbShape:
                                                              const RoundSliderThumbShape(
                                                                enabledThumbRadius:
                                                                    5.5,
                                                              ),
                                                          overlayShape:
                                                              const RoundSliderOverlayShape(
                                                                overlayRadius:
                                                                    12,
                                                              ),
                                                        ),
                                                        child: Slider(
                                                          value: curSec,
                                                          min: 0.0,
                                                          max: duration,
                                                          onChanged: (v) =>
                                                              _ctrl.seekTo(v),
                                                        ),
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      width: 38,
                                                      child: Text(
                                                        '-${_formatTime(remSec)}',
                                                        textAlign:
                                                            TextAlign.right,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontFeatures: const [
                                                            FontFeature.tabularFigures(),
                                                          ],
                                                          color: Colors.white
                                                              .withValues(
                                                                alpha: 0.58,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),

                                                // Baris 3: Kontrol Transport Apple (Prev / Play-Pause / Next + Badge Spotify)
                                                Stack(
                                                  alignment: Alignment.center,
                                                  children: [
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        IconButton(
                                                          onPressed:
                                                              _ctrl.skipPrevious,
                                                          visualDensity:
                                                              VisualDensity
                                                                  .compact,
                                                          icon: const Icon(
                                                            Icons
                                                                .skip_previous_rounded,
                                                            color: Colors.white,
                                                            size: 26,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 18,
                                                        ),
                                                        GestureDetector(
                                                          onTap: _ctrl
                                                              .togglePlayPause,
                                                          child: Container(
                                                            width: 40,
                                                            height: 40,
                                                            decoration:
                                                                const BoxDecoration(
                                                                  color: Color(
                                                                    0xFFF26B1D,
                                                                  ),
                                                                  shape: BoxShape
                                                                      .circle,
                                                                ),
                                                            child: _ctrl.isBuffering
                                                                ? const Padding(
                                                                    padding:
                                                                        EdgeInsets.all(
                                                                          10,
                                                                        ),
                                                                    child: CircularProgressIndicator(
                                                                      strokeWidth:
                                                                          2.2,
                                                                      color: Colors
                                                                          .white,
                                                                    ),
                                                                  )
                                                                : Icon(
                                                                    _ctrl.isPlaying
                                                                        ? Icons
                                                                              .pause_rounded
                                                                        : Icons
                                                                              .play_arrow_rounded,
                                                                    color:
                                                                        Colors.white,
                                                                    size: 23,
                                                                  ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 18,
                                                        ),
                                                        IconButton(
                                                          onPressed:
                                                              _ctrl.skipNext,
                                                          visualDensity:
                                                              VisualDensity
                                                                  .compact,
                                                          icon: const Icon(
                                                            Icons
                                                                .skip_next_rounded,
                                                            color: Colors.white,
                                                            size: 26,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const Align(
                                                      alignment:
                                                          Alignment.centerRight,
                                                      child: SpotifyLogoMark(
                                                        size: 18,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildCoverImage({
  required String coverUrl,
  required Uint8List? coverBytes,
  required double size,
  required double fallbackIconSize,
}) {
  if (coverBytes != null && coverBytes.isNotEmpty) {
    return Image.memory(
      coverBytes,
      width: size,
      height: size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => Center(child: SpotifyLogoMark(size: fallbackIconSize)),
    );
  }
  if (coverUrl.isNotEmpty) {
    return Image.network(
      coverUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Center(child: SpotifyLogoMark(size: fallbackIconSize)),
    );
  }
  return Center(child: SpotifyLogoMark(size: fallbackIconSize));
}

class _MiniVinylDisc extends StatelessWidget {
  const _MiniVinylDisc({
    required this.coverUrl,
    this.coverBytes,
    required this.angle,
    required this.size,
  });

  final String coverUrl;
  final Uint8List? coverBytes;
  final double angle;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFFFF9E44).withValues(alpha: 0.55),
          ),
          color: const Color(0xFF14141C),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
            _buildCoverImage(
              coverUrl: coverUrl,
              coverBytes: coverBytes,
              size: size,
              fallbackIconSize: 16,
            ),
            Container(
              width: 5.5,
              height: 5.5,
              decoration: BoxDecoration(
                color: const Color(0xFF050508),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFFB47E), width: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SleeveWithSpinningVinyl extends StatelessWidget {
  const _SleeveWithSpinningVinyl({
    required this.coverUrl,
    this.coverBytes,
    required this.angle,
  });

  final String coverUrl;
  final Uint8List? coverBytes;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 82,
      height: 56,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // Piringan hitam vinyl yang menonjol di kanan dan berputar halus (persis DynamicIslandPlayer.tsx)
          Positioned(
            left: 28,
            top: 2,
            child: Transform.rotate(
              angle: angle,
              child: Container(
                width: 52,
                height: 52,
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0B14),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black87,
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      _buildCoverImage(
                        coverUrl: coverUrl,
                        coverBytes: coverBytes,
                        size: 38,
                        fallbackIconSize: 24,
                      ),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: const Color(0xFF050508),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFFFB47E),
                            width: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Sampul Album Persegi di Depan (56x56)
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF101018),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black87,
                  blurRadius: 10,
                  offset: Offset(2, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: _buildCoverImage(
              coverUrl: coverUrl,
              coverBytes: coverBytes,
              size: 56,
              fallbackIconSize: 30,
            ),
          ),
        ],
      ),
    );
  }
}

class _EqualizerBars extends StatelessWidget {
  const _EqualizerBars({
    required this.elapsedSec,
    required this.isPlaying,
  });

  final double elapsedSec;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (j) {
          final h = isPlaying
              ? 5.0 + 14.0 * (0.5 + 0.5 * math.sin(elapsedSec * 6.2 + 1.15 * j))
              : 5.0;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.4),
            child: Container(
              width: 3.2,
              height: h,
              decoration: BoxDecoration(
                color: j.isEven
                    ? const Color(0xFFF26B1D)
                    : const Color(0xFFFFC078),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _SmoothMarqueeText extends StatelessWidget {
  const _SmoothMarqueeText({
    required this.text,
    required this.offsetPx,
  });

  final String text;
  final double offsetPx;

  @override
  Widget build(BuildContext context) {
    final unitWidth = (text.length * 6.4 + 28.0).clamp(90.0, 600.0);
    final shift = -(offsetPx % unitWidth);
    const style = TextStyle(
      fontSize: 11.2,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      color: Color(0xFFF1F1F1),
    );

    return OverflowBox(
      alignment: Alignment.centerLeft,
      maxWidth: unitWidth * 3,
      child: Transform.translate(
        offset: Offset(shift, 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: unitWidth,
              child: Text(text, maxLines: 1, softWrap: false, style: style),
            ),
            SizedBox(
              width: unitWidth,
              child: Text(text, maxLines: 1, softWrap: false, style: style),
            ),
          ],
        ),
      ),
    );
  }
}
