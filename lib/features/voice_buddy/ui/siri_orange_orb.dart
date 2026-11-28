import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../voice_buddy_controller.dart';

/// Marble Volumetric Studio Glass Orb (GLSL FragmentShader `shaders/marble_orb.frag`)
/// + Irregular Voice-Reactive Aura Ribbons Strictly BEHIND the Orb Rotating Clockwise.
///
/// Dioptimalkan khusus agar berjalan mulus 60/120fps di perangkat mobile kelas menengah:
/// - Zero per-frame `setState()` (seluruh animasi digerakkan lewat `ChangeNotifier` repaint + `RepaintBoundary`).
/// - Zero per-frame `Path.combine` & `MaskFilter.blur` di kanvas CustomPainter.
/// - Menerima `energyListenable` / `frequencyListenable` langsung tanpa memicu rebuild tree overlay.
class SiriOrangeOrb extends StatefulWidget {
  const SiriOrangeOrb({
    super.key,
    required this.phase,
    this.energy = 0.0,
    this.frequency = 0.45,
    this.energyListenable,
    this.frequencyListenable,
    this.size = 285.0,
    this.pressKick = 0.0,
    this.pointerOffset = Offset.zero,
  });

  final SiriOrbPhase phase;
  final double energy;
  final double frequency;
  final ValueListenable<double>? energyListenable;
  final ValueListenable<double>? frequencyListenable;
  final double size;
  final double pressKick;
  final Offset pointerOffset;

  @override
  State<SiriOrangeOrb> createState() => _SiriOrangeOrbState();
}

class _Vec3 {
  const _Vec3(this.r, this.g, this.b);
  final double r;
  final double g;
  final double b;

  static _Vec3 lerp(_Vec3 a, _Vec3 b, double t) {
    return _Vec3(
      a.r + (b.r - a.r) * t,
      a.g + (b.g - a.g) * t,
      a.b + (b.b - a.b) * t,
    );
  }

  Color toDisplayColor({double alpha = 1.0}) {
    return Color.fromRGBO(
      (r.clamp(0.0, 1.0) * 255).round(),
      (g.clamp(0.0, 1.0) * 255).round(),
      (b.clamp(0.0, 1.0) * 255).round(),
      alpha.clamp(0.0, 1.0),
    );
  }
}

class _MarbleStateTone {
  const _MarbleStateTone({
    required this.deep,
    required this.bright,
    required this.rim,
  });

  final _Vec3 deep;
  final _Vec3 bright;
  final _Vec3 rim;

  static _MarbleStateTone lerp(
    _MarbleStateTone a,
    _MarbleStateTone b,
    double t,
  ) {
    return _MarbleStateTone(
      deep: _Vec3.lerp(a.deep, b.deep, t),
      bright: _Vec3.lerp(a.bright, b.bright, t),
      rim: _Vec3.lerp(a.rim, b.rim, t),
    );
  }
}

class _OrbPaintState extends ChangeNotifier {
  double fogPhase = 0.0;
  double clockwiseAuraAngle = 0.0;
  double auraMorphPhase = 0.0;
  double liveVoice = 0.0;
  double frequency = 0.45;
  double easedEnergy = 0.24;
  double flareKick = 0.0;
  double breathScale = 1.0;
  bool isVoiceInteractive = false;
  bool isThinking = false;
  Offset easedPointer = Offset.zero;
  _MarbleStateTone tone = _SiriOrangeOrbState._toneSummonAmber;

  void notifyFrame() => notifyListeners();
}

class _SiriOrangeOrbState extends State<SiriOrangeOrb>
    with SingleTickerProviderStateMixin {
  static ui.FragmentProgram? _cachedProgram;
  static bool _loadingProgram = false;

  // Palet cuaca kaca volumetrik Marble:
  // - Asking / Listening / Summon: Golden-Amber
  // - Thinking: MERAH menyala (sesuai permintaan user, tidak lagi ungu!)
  // - Speaking: Hangat Amber-Emas bercahaya hidup mengikuti suara
  // - Idle / Ready: Studio Copper-Amber dengan kilau tepi lembut
  static const _MarbleStateTone _toneSummonAmber = _MarbleStateTone(
    deep: _Vec3(1.00, 0.40, 0.06),
    bright: _Vec3(1.00, 0.88, 0.45),
    rim: _Vec3(1.00, 0.70, 0.30),
  );

  static const _MarbleStateTone _toneListeningAmber = _MarbleStateTone(
    deep: _Vec3(1.00, 0.38, 0.05),
    bright: _Vec3(1.00, 0.90, 0.48),
    rim: _Vec3(1.00, 0.72, 0.32),
  );

  static const _MarbleStateTone _toneThinkingRed = _MarbleStateTone(
    deep: _Vec3(0.95, 0.06, 0.05),
    bright: _Vec3(1.00, 0.44, 0.20),
    rim: _Vec3(1.00, 0.20, 0.14),
  );

  static const _MarbleStateTone _toneSpeakingWarmEmerald = _MarbleStateTone(
    deep: _Vec3(0.94, 0.44, 0.08),
    bright: _Vec3(0.96, 0.98, 0.62),
    rim: _Vec3(0.98, 0.78, 0.34),
  );

  static const _MarbleStateTone _toneReadyWarmBlue = _MarbleStateTone(
    deep: _Vec3(0.88, 0.36, 0.08),
    bright: _Vec3(0.96, 0.86, 0.64),
    rim: _Vec3(0.62, 0.78, 1.00),
  );

  final _OrbPaintState _paintState = _OrbPaintState();
  ui.FragmentShader? _shader;
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _clockSec = 0.0;
  double _lastExternalKick = 0.0;

  @override
  void initState() {
    super.initState();
    _ensureShaderLoaded();
    if (widget.phase == SiriOrbPhase.summon) {
      _paintState.flareKick = 0.85;
    }
    _ticker = createTicker(_onTick)..start();
  }

  Future<void> _ensureShaderLoaded() async {
    if (_cachedProgram != null) {
      _shader = _cachedProgram!.fragmentShader();
      _paintState.notifyFrame();
      if (mounted) setState(() {});
      return;
    }
    if (_loadingProgram) return;
    _loadingProgram = true;
    try {
      final prog = await ui.FragmentProgram.fromAsset('shaders/marble_orb.frag');
      _cachedProgram = prog;
      if (mounted) {
        _shader = prog.fragmentShader();
        _paintState.notifyFrame();
        setState(() {});
      }
    } catch (_) {
      // Pada unit test headless tanpa GPU shader bundle, fallback radial painter dipakai otomatis.
    } finally {
      _loadingProgram = false;
    }
  }

  @override
  void didUpdateWidget(covariant SiriOrangeOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phase == SiriOrbPhase.summon &&
        oldWidget.phase != SiriOrbPhase.summon) {
      _paintState.flareKick = 0.90;
    }
    if (widget.pressKick > _lastExternalKick) {
      _paintState.flareKick = 1.0;
    }
    _lastExternalKick = widget.pressKick;
  }

  _MarbleStateTone _targetToneFor(SiriOrbPhase p) {
    return switch (p) {
      SiriOrbPhase.thinking => _toneThinkingRed,
      SiriOrbPhase.listening => _MarbleStateTone.lerp(
        _toneListeningAmber,
        const _MarbleStateTone(
          deep: _Vec3(1.00, 0.30, 0.12),
          bright: _Vec3(1.00, 0.92, 0.56),
          rim: _Vec3(1.00, 0.64, 0.36),
        ),
        0.5 + 0.5 * math.sin(_clockSec * 1.6),
      ),
      SiriOrbPhase.speaking => _MarbleStateTone.lerp(
        _toneSummonAmber,
        _toneSpeakingWarmEmerald,
        0.45 + 0.45 * math.sin(_clockSec * 1.35),
      ),
      SiriOrbPhase.summon => _toneSummonAmber,
      _ => _toneReadyWarmBlue,
    };
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.016
        : ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = elapsed;
    _clockSec += dt;

    final reducedMotion =
        mounted && (MediaQuery.maybeDisableAnimationsOf(context) ?? false);

    if (_paintState.flareKick > 0.002) {
      _paintState.flareKick *= math.exp(-2.2 * dt);
    } else {
      _paintState.flareKick = 0.0;
    }

    final targetTone = _targetToneFor(widget.phase);
    final toneAlpha = (1.0 - math.exp(-3.4 * dt)).clamp(0.0, 1.0);
    _paintState.tone = _MarbleStateTone.lerp(_paintState.tone, targetTone, toneAlpha);

    final ptrAlpha = (1.0 - math.exp(-4.0 * dt)).clamp(0.0, 1.0);
    _paintState.easedPointer =
        Offset.lerp(_paintState.easedPointer, widget.pointerOffset, ptrAlpha)!;

    final rawEnergy = widget.energyListenable?.value ?? widget.energy;
    final rawFreq = widget.frequencyListenable?.value ?? widget.frequency;
    final liveVoice = rawEnergy.clamp(0.0, 1.0);
    _paintState.liveVoice = liveVoice;
    _paintState.frequency = rawFreq.clamp(0.15, 1.0);

    final sinAsk = math.sin(2.4 * _clockSec);
    final double stateTargetEnergy = switch (widget.phase) {
      SiriOrbPhase.thinking => 0.65 + 0.15 * math.sin(3.1 * _clockSec),
      SiriOrbPhase.listening => math.max(
        liveVoice * 1.15,
        0.38 + 0.36 * (sinAsk * sinAsk),
      ),
      SiriOrbPhase.speaking => math.max(liveVoice * 1.22, 0.34),
      SiriOrbPhase.summon => 0.58,
      _ => 0.18,
    };
    final targetEnergy = reducedMotion
        ? 0.30
        : (stateTargetEnergy + _paintState.flareKick * 0.70).clamp(0.0, 1.75);
    final energyAlpha = (1.0 - math.exp(-5.0 * dt)).clamp(0.0, 1.0);
    _paintState.easedEnergy += (targetEnergy - _paintState.easedEnergy) * energyAlpha;

    final double baseSpeed = switch (widget.phase) {
      SiriOrbPhase.thinking => 0.80,
      SiriOrbPhase.listening => 0.22 + liveVoice * 0.32,
      SiriOrbPhase.speaking => 0.24 + liveVoice * 0.38,
      SiriOrbPhase.summon => 0.42,
      _ => 0.12,
    };
    final fogSpeed = baseSpeed + _paintState.flareKick * 1.60;

    if (!reducedMotion) {
      _paintState.fogPhase += dt * fogSpeed;
      final clockwiseSpeed =
          0.34 + 0.22 * liveVoice + _paintState.flareKick * 0.45;
      _paintState.clockwiseAuraAngle =
          (_paintState.clockwiseAuraAngle + dt * clockwiseSpeed) % (2.0 * math.pi);
      _paintState.auraMorphPhase += dt * (1.15 + 1.45 * liveVoice);
    }

    _paintState.isThinking = widget.phase == SiriOrbPhase.thinking;
    _paintState.isVoiceInteractive =
        widget.phase == SiriOrbPhase.listening ||
        widget.phase == SiriOrbPhase.speaking ||
        widget.phase == SiriOrbPhase.summon ||
        widget.phase == SiriOrbPhase.thinking;

    _paintState.breathScale = reducedMotion
        ? 1.0
        : (1.0 +
                  0.018 * _paintState.easedEnergy.clamp(0.0, 1.0) +
                  0.026 * _paintState.flareKick)
              .clamp(0.96, 1.08);

    // Picu repaint GPU kanvas langsung tanpa `setState()` widget tree!
    _paintState.notifyFrame();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _paintState.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeShader = _shader ?? _cachedProgram?.fragmentShader();
    return Semantics(
      label: 'Bola kaca cuaca asisten suara',
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _paintState,
          builder: (context, child) {
            final shiftPx = Offset(
              _paintState.easedPointer.dx * widget.size * 0.014,
              _paintState.easedPointer.dy * widget.size * 0.014,
            );
            return Transform.translate(
              offset: shiftPx,
              child: Transform.scale(
                scale: _paintState.breathScale,
                child: child,
              ),
            );
          },
          child: SizedBox.square(
            dimension: widget.size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    isComplex: true,
                    willChange: true,
                    painter: _ClockwiseIrregularBackAuraPainter(_paintState),
                  ),
                ),
                RepaintBoundary(
                  child: CustomPaint(
                    isComplex: true,
                    willChange: true,
                    painter: _MarbleShaderOrbPainter(
                      state: _paintState,
                      shader: activeShader,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClockwiseIrregularBackAuraPainter extends CustomPainter {
  _ClockwiseIrregularBackAuraPainter(this.state) : super(repaint: state);

  final _OrbPaintState state;
  Size? _cachedCutoutSize;
  Path? _cachedCutoutPath;

  // Stroke paints dipakai ulang agar tidak membuat objek Paint di setiap frame.
  final Paint _softGlowPaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus;

  final Paint _coreLinePaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..blendMode = BlendMode.plus;

  Path _getCutoutPath(Size size, Offset center, double rBall) {
    if (_cachedCutoutSize == size && _cachedCutoutPath != null) {
      return _cachedCutoutPath!;
    }
    // PathFillType.evenOdd memotong area lingkaran tengah seketika tanpa operasi CSG Path.combine tiap frame!
    final p = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: center, radius: rBall * 0.985));
    _cachedCutoutSize = size;
    _cachedCutoutPath = p;
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.46);
    final rBall = math.min(size.width, size.height) * 0.34;

    final activeBoost = state.isVoiceInteractive ? 1.0 : 0.35;
    final e =
        (state.liveVoice * 0.85 + state.easedEnergy * 0.32).clamp(0.0, 1.35) *
        activeBoost;
    if (e < 0.03) return;

    canvas.save();
    canvas.clipPath(_getCutoutPath(size, center, rBall));
    canvas.translate(center.dx, center.dy);
    canvas.rotate(state.clockwiseAuraAngle);

    final List<Color> ribbonColors = state.isThinking
        ? <Color>[
            const Color(0xFFFF2424),
            const Color(0xFFFF6A45),
            state.tone.rim.toDisplayColor(),
          ]
        : <Color>[
            const Color(0xFFFF7A26),
            const Color(0xFFFFCA62),
            state.tone.rim.toDisplayColor(),
          ];

    // 3 pita kontur tak beraturan organik (40 titik kurva -> 0 MaskFilter blur, mulus 60/120fps)
    for (int layer = 0; layer < 3; layer++) {
      final double l = layer.toDouble();
      final double phaseOffset = l * 1.48;
      final Path irregularLoop = _buildIrregularContourPath(
        baseRadius: rBall * (0.995 + 0.036 * l + 0.048 * e),
        wobbleAmp: rBall * (0.042 + 0.130 * e) * (1.0 - 0.12 * l),
        morph: state.auraMorphPhase + phaseOffset,
        freqBoost: state.frequency,
        seed: layer,
      );

      final Color col = ribbonColors[layer];
      final double baseAlpha =
          ((0.30 + 0.44 * e) * (1.0 - 0.15 * l)).clamp(0.0, 0.82);

      // Pendaran aura lebar ringan (pengganti MaskFilter.blur yang berat di GPU mobile)
      _softGlowPaint
        ..strokeWidth = 6.2 - l * 0.8
        ..color = col.withValues(alpha: baseAlpha * 0.24);
      canvas.drawPath(irregularLoop, _softGlowPaint);

      _coreLinePaint
        ..strokeWidth = (2.1 - l * 0.25).clamp(1.1, 2.3)
        ..color = Color.lerp(col, Colors.white, 0.34)!
            .withValues(alpha: baseAlpha);
      canvas.drawPath(irregularLoop, _coreLinePaint);
    }

    canvas.restore();
  }

  Path _buildIrregularContourPath({
    required double baseRadius,
    required double wobbleAmp,
    required double morph,
    required double freqBoost,
    required int seed,
  }) {
    const int steps = 40;
    final List<Offset> pts = List<Offset>.generate(steps, (i) {
      final double theta = (i / steps) * 2.0 * math.pi;
      final double n1 = math.sin(3.0 * theta + morph * 0.85 + seed * 1.9);
      final double n2 =
          0.62 * math.cos(5.0 * theta - morph * 1.15 + seed * 2.7);
      final double n3 =
          (0.32 + 0.22 * freqBoost) *
          math.sin(7.0 * theta + morph * 1.45 - seed * 1.1);
      final double r = baseRadius + wobbleAmp * ((n1 + n2 + n3) / 1.94);
      return Offset(r * math.cos(theta), r * math.sin(theta));
    });

    final Path path = Path();
    final Offset firstMid = Offset(
      (pts.last.dx + pts.first.dx) * 0.5,
      (pts.last.dy + pts.first.dy) * 0.5,
    );
    path.moveTo(firstMid.dx, firstMid.dy);
    for (int i = 0; i < steps; i++) {
      final Offset curr = pts[i];
      final Offset next = pts[(i + 1) % steps];
      path.quadraticBezierTo(
        curr.dx,
        curr.dy,
        (curr.dx + next.dx) * 0.5,
        (curr.dy + next.dy) * 0.5,
      );
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _ClockwiseIrregularBackAuraPainter old) {
    return old.state != state;
  }
}

class _MarbleShaderOrbPainter extends CustomPainter {
  _MarbleShaderOrbPainter({
    required this.state,
    required this.shader,
  }) : super(repaint: state);

  final _OrbPaintState state;
  final ui.FragmentShader? shader;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.46);
    final rBall = math.min(size.width, size.height) * 0.34;
    final tone = state.tone;

    final frag = shader;
    if (frag != null) {
      frag.setFloat(0, size.width);
      frag.setFloat(1, size.height);
      frag.setFloat(2, center.dx);
      frag.setFloat(3, center.dy);
      frag.setFloat(4, rBall);
      frag.setFloat(5, state.fogPhase);
      frag.setFloat(6, state.easedEnergy);
      frag.setFloat(7, state.easedPointer.dx);
      frag.setFloat(8, state.easedPointer.dy);
      frag.setFloat(9, tone.deep.r);
      frag.setFloat(10, tone.deep.g);
      frag.setFloat(11, tone.deep.b);
      frag.setFloat(12, tone.bright.r);
      frag.setFloat(13, tone.bright.g);
      frag.setFloat(14, tone.bright.b);
      frag.setFloat(15, tone.rim.r);
      frag.setFloat(16, tone.rim.g);
      frag.setFloat(17, tone.rim.b);

      canvas.drawRect(
        Offset.zero & size,
        Paint()..shader = frag,
      );
      return;
    }

    canvas.drawCircle(
      center,
      rBall,
      Paint()
        ..shader = ui.Gradient.radial(
          center + Offset(-rBall * 0.22, -rBall * 0.24),
          rBall * 1.15,
          [
            tone.bright.toDisplayColor(),
            tone.deep.toDisplayColor(),
            const Color(0xFF1A0904),
          ],
          const [0.0, 0.68, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _MarbleShaderOrbPainter old) {
    return old.state != state || old.shader != shader;
  }
}
