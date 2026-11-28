import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../voice_buddy_controller.dart';

/// Marble Volumetric Studio Glass Orb (GLSL FragmentShader `shaders/marble_orb.frag`)
/// + Irregular Voice-Reactive Aura Ribbons Strictly BEHIND the Orb Rotating Clockwise:
///
/// 1. **Lapisan Belakang (`_ClockwiseIrregularBackAuraPainter`)**:
///    - Garis aura organik tak beraturan yang mekar mengikuti amplitudo suara saat diajak mengobrol.
///    - Diposisikan **100% di belakang bola kaca** (area dalam bola `r < rBall` dipotong bersih sehingga
///      tidak pernah ada garis atau pita aneh yang memotong tengah bola!).
///    - Berputar pelan secara kontinu **searah jarum jam dinding (`+clockwiseAngle`)**.
/// 2. **Lapisan Utama (`shaders/marble_orb.frag` per-pixel raymarched 3D glass orb)**:
///    - Pembiasan kaca studio 3D (`refract` rasio `1/1.4`), 10 sampel chord volumetrik, puntiran vertikal
///      `phase * 0.7 + y * (0.6 + energy)`, *domain-warped* 3-octave value noise yang melipat hidup
///      di seluruh isi bola (tidak hitam kosong dan tanpa garis kotak horizontal!).
///    - Filamen cahaya tipis `(1 - |2n - 1|)^10`, pembiasan tepi R/G/B `(1 - z)^{2.1, 2.6, 3.3}`,
///      pantulan jendela studio miring 20° di kiri-atas, pantulan kanan-bawah, serta elips cahaya meja `1.26r`.
///    - Bertransisi warna halus (~600ms, `3.2/s`) antar status sehingga cuaca di dalam bola tampak hidup
///      bergerak dan berganti nuansa warna dengan identitas utama Hangat Amber-Oranye.
class SiriOrangeOrb extends StatefulWidget {
  const SiriOrangeOrb({
    super.key,
    required this.phase,
    required this.energy,
    this.frequency = 0.45,
    this.size = 285.0,
    this.pressKick = 0.0,
    this.pointerOffset = Offset.zero,
  });

  final SiriOrbPhase phase;
  final double energy;
  final double frequency;
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

class _SiriOrangeOrbState extends State<SiriOrangeOrb>
    with SingleTickerProviderStateMixin {
  static ui.FragmentProgram? _cachedProgram;
  static bool _loadingProgram = false;

  // Palet cuaca kaca volumetrik Marble:
  // - Asking / Listening / Summon: Golden-Amber ikonik persis referensi Marble ("May I go ahead?")
  // - Thinking: Berputar cepat dengan gradasi Violet-Amber menyala
  // - Speaking: Berpendar hangat Molten Amber <-> Emerald-Gold yang bernapas mengikuti suara
  // - Idle / Ready: Warm Studio Copper-Amber dengan kilau biru lembut di bibir kaca
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

  static const _MarbleStateTone _toneThinkingViolet = _MarbleStateTone(
    deep: _Vec3(0.58, 0.20, 0.98),
    bright: _Vec3(0.96, 0.78, 1.00),
    rim: _Vec3(0.84, 0.56, 1.00),
  );

  static const _MarbleStateTone _toneSpeakingWarmEmerald = _MarbleStateTone(
    deep: _Vec3(0.94, 0.44, 0.08),
    bright: _Vec3(0.92, 1.00, 0.68),
    rim: _Vec3(0.52, 0.96, 0.72),
  );

  static const _MarbleStateTone _toneReadyWarmBlue = _MarbleStateTone(
    deep: _Vec3(0.88, 0.36, 0.08),
    bright: _Vec3(0.96, 0.86, 0.64),
    rim: _Vec3(0.62, 0.78, 1.00),
  );

  ui.FragmentShader? _shader;
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  double _clockSec = 0.0;
  double _fogPhase = 0.0;
  double _clockwiseAuraAngle = 0.0;
  double _auraMorphPhase = 0.0;
  double _easedEnergy = 0.24;
  double _flareKick = 0.0;
  double _lastExternalKick = 0.0;
  Offset _easedPointer = Offset.zero;

  _MarbleStateTone _currentTone = _toneSummonAmber;

  @override
  void initState() {
    super.initState();
    _ensureShaderLoaded();
    if (widget.phase == SiriOrbPhase.summon) {
      _flareKick = 0.85;
    }
    _ticker = createTicker(_onTick)..start();
  }

  Future<void> _ensureShaderLoaded() async {
    if (_cachedProgram != null) {
      _shader = _cachedProgram!.fragmentShader();
      if (mounted) setState(() {});
      return;
    }
    if (_loadingProgram) return;
    _loadingProgram = true;
    try {
      final prog = await ui.FragmentProgram.fromAsset('shaders/marble_orb.frag');
      _cachedProgram = prog;
      if (mounted) {
        setState(() {
          _shader = prog.fragmentShader();
        });
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
      _flareKick = 0.90;
    }
    if (widget.pressKick > _lastExternalKick) {
      _flareKick = 1.0;
    }
    _lastExternalKick = widget.pressKick;
  }

  _MarbleStateTone _targetToneFor(SiriOrbPhase p) {
    return switch (p) {
      SiriOrbPhase.thinking => _toneThinkingViolet,
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

    // Flare press decay: exp(-2.2 * dt)
    if (_flareKick > 0.002) {
      _flareKick *= math.exp(-2.2 * dt);
    } else {
      _flareKick = 0.0;
    }

    // Smooth color state blend at 3.2 per second (~600ms transition, never instant)
    final targetTone = _targetToneFor(widget.phase);
    final toneAlpha = (1.0 - math.exp(-3.2 * dt)).clamp(0.0, 1.0);
    _currentTone = _MarbleStateTone.lerp(_currentTone, targetTone, toneAlpha);

    // Pointer eased at 4 per second
    final ptrAlpha = (1.0 - math.exp(-4.0 * dt)).clamp(0.0, 1.0);
    _easedPointer = Offset.lerp(_easedPointer, widget.pointerOffset, ptrAlpha)!;

    // Energy eased at 5 per second (Marble spec + live voice amplitude + press flare +0.7)
    final liveVoice = widget.energy.clamp(0.0, 1.0);
    final sinAsk = math.sin(2.4 * _clockSec);
    final double stateTargetEnergy = switch (widget.phase) {
      SiriOrbPhase.thinking => 0.62 + 0.16 * math.sin(3.1 * _clockSec),
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
        : (stateTargetEnergy + _flareKick * 0.70).clamp(0.0, 1.75);
    final energyAlpha = (1.0 - math.exp(-5.0 * dt)).clamp(0.0, 1.0);
    _easedEnergy += (targetEnergy - _easedEnergy) * energyAlpha;

    // Fog speed integrated in Dart (phase += dt * speed) so changing speed never jumps
    final double baseSpeed = switch (widget.phase) {
      SiriOrbPhase.thinking => 0.75,
      SiriOrbPhase.listening => 0.22 + liveVoice * 0.32,
      SiriOrbPhase.speaking => 0.24 + liveVoice * 0.38,
      SiriOrbPhase.summon => 0.42,
      _ => 0.12,
    };
    final fogSpeed = baseSpeed + _flareKick * 1.60;

    if (!reducedMotion) {
      _fogPhase += dt * fogSpeed;
      // Putaran pelan searah jarum jam dinding (+dt * rad/s, positif = searah jarum jam di layar Flutter!)
      final clockwiseSpeed =
          0.34 + 0.22 * (liveVoice.clamp(0.0, 1.0)) + _flareKick * 0.45;
      _clockwiseAuraAngle =
          (_clockwiseAuraAngle + dt * clockwiseSpeed) % (2.0 * math.pi);
      _auraMorphPhase += dt * (1.15 + 1.45 * liveVoice);
    }

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final liveVoice = widget.energy.clamp(0.0, 1.0);
    final isVoiceInteractive =
        widget.phase == SiriOrbPhase.listening ||
        widget.phase == SiriOrbPhase.speaking ||
        widget.phase == SiriOrbPhase.summon ||
        widget.phase == SiriOrbPhase.thinking;

    final breathScale = reducedMotion
        ? 1.0
        : (1.0 + 0.018 * _easedEnergy.clamp(0.0, 1.0) + 0.026 * _flareKick)
              .clamp(0.96, 1.08);

    // Pergeseran halus 1.2% mengikuti sentuhan / pointer sesuai spesifikasi Marble
    final shiftPx = Offset(
      _easedPointer.dx * widget.size * 0.014,
      _easedPointer.dy * widget.size * 0.014,
    );

    return Semantics(
      label: 'Bola kaca cuaca asisten suara',
      child: RepaintBoundary(
        child: Transform.translate(
          offset: shiftPx,
          child: Transform.scale(
            scale: breathScale,
            child: SizedBox.square(
              dimension: widget.size,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // LAPISAN 1 (MURNI DI BELAKANG BOLA):
                  // Garis gelombang tak beraturan yang berputar searah jarum jam dinding saat diajak bicara
                  CustomPaint(
                    painter: _ClockwiseIrregularBackAuraPainter(
                      clockwiseAngle: _clockwiseAuraAngle,
                      morphPhase: _auraMorphPhase,
                      voiceEnergy: liveVoice,
                      stateEnergy: _easedEnergy,
                      frequency: widget.frequency.clamp(0.15, 1.0),
                      isActive: isVoiceInteractive,
                      tone: _currentTone,
                    ),
                  ),

                  // LAPISAN 2 (DI DEPAN):
                  // Bola Kaca Volumetrik Marble Per-Pixel (menutup area r <= rBall dengan mulus 2px AA)
                  CustomPaint(
                    painter: _MarbleShaderOrbPainter(
                      shader: _shader ?? _cachedProgram?.fragmentShader(),
                      fogPhase: _fogPhase,
                      energy: _easedEnergy,
                      pointer: _easedPointer,
                      tone: _currentTone,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClockwiseIrregularBackAuraPainter extends CustomPainter {
  const _ClockwiseIrregularBackAuraPainter({
    required this.clockwiseAngle,
    required this.morphPhase,
    required this.voiceEnergy,
    required this.stateEnergy,
    required this.frequency,
    required this.isActive,
    required this.tone,
  });

  final double clockwiseAngle;
  final double morphPhase;
  final double voiceEnergy;
  final double stateEnergy;
  final double frequency;
  final bool isActive;
  final _MarbleStateTone tone;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.46);
    final rBall = math.min(size.width, size.height) * 0.34;

    final activeBoost = isActive ? 1.0 : 0.35;
    final e = (voiceEnergy * 0.85 + stateEnergy * 0.32).clamp(0.0, 1.35) *
        activeBoost;
    if (e < 0.03) return;

    // Potong area dalam lingkaran bola kaca (PathOperation.difference) sehingga 100% garis tak beraturan
    // HANYA terlihat muncul dari BELAKANG bola kaca, tidak pernah melintasi bagian depan bola!
    final outerBounds = Path()..addRect(Offset.zero & size);
    final innerBallCutout = Path()
      ..addOval(Rect.fromCircle(center: center, radius: rBall * 0.985));
    final strictlyBehindOrbClip = Path.combine(
      PathOperation.difference,
      outerBounds,
      innerBallCutout,
    );

    canvas.save();
    canvas.clipPath(strictlyBehindOrbClip);

    // Putar kanvas searah jarum jam dinding (+clockwiseAngle di koordinat layar Flutter = searah jarum jam!)
    canvas.translate(center.dx, center.dy);
    canvas.rotate(clockwiseAngle);

    final warmMain = const Color(0xFFFF7A26);
    final goldCrest = const Color(0xFFFFCA62);
    final stateAccent = tone.rim.toDisplayColor();
    final rubyFringe = const Color(0xFFFF3D57);

    final ribbonColors = <Color>[
      warmMain,
      goldCrest,
      stateAccent,
      rubyFringe,
    ];

    // 4 pita kontur tak beraturan organik yang mekar halus di belakang tepi bola saat berbicara
    for (int layer = 0; layer < 4; layer++) {
      final double l = layer.toDouble();
      final double phaseOffset = l * 1.42;
      final Path irregularLoop = _buildIrregularContourPath(
        baseRadius: rBall * (0.995 + 0.032 * l + 0.048 * e),
        wobbleAmp: rBall * (0.042 + 0.135 * e) * (1.0 - 0.10 * l),
        morph: morphPhase + phaseOffset,
        freqBoost: frequency,
        seed: layer,
      );

      final Color col = ribbonColors[layer];
      final double baseAlpha = ((0.30 + 0.44 * e) * (1.0 - 0.14 * l))
          .clamp(0.0, 0.82);

      // Pendaran aura lembut di belakang pita
      canvas.drawPath(
        irregularLoop,
        Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5.5 - l * 0.7
          ..blendMode = BlendMode.plus
          ..color = col.withValues(alpha: baseAlpha * 0.34)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5),
      );

      // Garis kontur tak beraturan tajam berkilau
      canvas.drawPath(
        irregularLoop,
        Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = (2.1 - l * 0.25).clamp(1.1, 2.4)
          ..blendMode = BlendMode.plus
          ..color = Color.lerp(col, Colors.white, 0.34)!
              .withValues(alpha: baseAlpha),
      );
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
    const int steps = 84;
    final List<Offset> pts = List<Offset>.generate(steps, (i) {
      final double theta = (i / steps) * 2.0 * math.pi;
      // Harmonik asimetris tak beraturan (3, 5, 7 gelombang) agar kontur organik, tidak bundar kaku
      final double n1 = math.sin(3.0 * theta + morph * 0.85 + seed * 1.9);
      final double n2 =
          0.62 * math.cos(5.0 * theta - morph * 1.15 + seed * 2.7);
      final double n3 =
          (0.32 + 0.22 * freqBoost) *
          math.sin(7.0 * theta + morph * 1.45 - seed * 1.1);
      final double r =
          baseRadius + wobbleAmp * ((n1 + n2 + n3) / 1.94);
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
    return old.clockwiseAngle != clockwiseAngle ||
        old.morphPhase != morphPhase ||
        old.voiceEnergy != voiceEnergy ||
        old.stateEnergy != stateEnergy ||
        old.isActive != isActive;
  }
}

class _MarbleShaderOrbPainter extends CustomPainter {
  const _MarbleShaderOrbPainter({
    required this.shader,
    required this.fogPhase,
    required this.energy,
    required this.pointer,
    required this.tone,
  });

  final ui.FragmentShader? shader;
  final double fogPhase;
  final double energy;
  final Offset pointer;
  final _MarbleStateTone tone;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.46);
    final rBall = math.min(size.width, size.height) * 0.34;

    final frag = shader;
    if (frag != null) {
      // Set uniforms in exact GLSL order (0..17)
      frag.setFloat(0, size.width);
      frag.setFloat(1, size.height);
      frag.setFloat(2, center.dx);
      frag.setFloat(3, center.dy);
      frag.setFloat(4, rBall);
      frag.setFloat(5, fogPhase);
      frag.setFloat(6, energy);
      frag.setFloat(7, pointer.dx);
      frag.setFloat(8, pointer.dy);
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

    // Fallback tanpa WebGL/Impeller (mis. saat unit test headless): gradien radial warna status sesuai spesifikasi Marble
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
    return old.fogPhase != fogPhase ||
        old.energy != energy ||
        old.pointer != pointer ||
        old.tone.deep.r != tone.deep.r ||
        old.tone.bright.g != tone.bright.g ||
        old.shader != shader;
  }
}
