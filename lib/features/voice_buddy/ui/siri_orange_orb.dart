import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../voice_buddy_controller.dart';

/// Bola asisten bergaya iOS Siri (`SUICOrbView` × `SiriWave`) dengan:
/// - Pegas fisik orde-2 (Apple Fluid Interfaces: `response` & `dampingRatio`) yang interruptible.
/// - Garis gelombang sinus multi-harmonik teredam (`SiriWave`) yang naik-turun mengikuti volume (`energy`)
///   dan merapat/merenggang mengikuti frekuensi vokal (`frequency`), menembus keluar batas bola.
/// - Membran cairan polar dengan profil optik *Beer-Lambert* (gelap pekat di dalam, berpendar cair
///   di punggung gelombang) sehingga tidak keruh dan menyatu seperti cairan cahaya.
/// - Dispersi *Chromatic Aberration* presisi (`1.5–3.2px` pergeseran spektral Merah-Magenta,
///   Copper-Gold, dan Cyan-Prism pada `BlendMode.plus`) yang memijar putih di titik temu gelombang.
class SiriOrangeOrb extends StatefulWidget {
  const SiriOrangeOrb({
    super.key,
    required this.phase,
    required this.energy,
    this.frequency = 0.45,
    this.size = 80.0,
  });

  final SiriOrbPhase phase;
  final double energy;
  final double frequency;
  final double size;

  @override
  State<SiriOrangeOrb> createState() => _SiriOrangeOrbState();
}

class _FluidSpring1D {
  _FluidSpring1D({
    required this.response,
    required this.dampingRatio,
    double initialValue = 0.0,
  }) : value = initialValue;

  final double response;
  final double dampingRatio;
  double value;
  double velocity = 0.0;

  void step(double target, double dt) {
    if (dt <= 0.0) return;
    final int steps = (dt / 0.016).ceil().clamp(1, 4);
    final double h = dt / steps;
    final double omega = (2.0 * math.pi) / math.max(0.04, response);
    final double stiffness = omega * omega;
    final double damping = 2.0 * dampingRatio * omega;

    for (int i = 0; i < steps; i++) {
      final double force = -stiffness * (value - target) - damping * velocity;
      velocity += force * h;
      value += velocity * h;
    }
  }
}

class _SiriOrangeOrbState extends State<SiriOrangeOrb>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _phaseTime = 0.0;
  double _summonFlash = 0.0;

  final _FluidSpring1D _energySpring = _FluidSpring1D(
    response: 0.14,
    dampingRatio: 0.76,
  );
  final _FluidSpring1D _freqSpring = _FluidSpring1D(
    response: 0.22,
    dampingRatio: 0.90,
    initialValue: 0.45,
  );
  final _FluidSpring1D _eruptionSpring = _FluidSpring1D(
    response: 0.18,
    dampingRatio: 0.68,
  );

  @override
  void initState() {
    super.initState();
    if (widget.phase == SiriOrbPhase.summon) {
      _summonFlash = 1.0;
      _eruptionSpring.velocity = 2.4;
    }
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant SiriOrangeOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phase == SiriOrbPhase.summon &&
        oldWidget.phase != SiriOrbPhase.summon) {
      _summonFlash = 1.0;
      _eruptionSpring.velocity += 2.0;
    }
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.016
        : ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = elapsed;

    final reducedMotion =
        mounted && (MediaQuery.maybeDisableAnimationsOf(context) ?? false);

    final rawE = widget.energy.clamp(0.0, 1.0);
    final rawF = widget.frequency.clamp(0.15, 1.0);

    final ambientE = switch (widget.phase) {
      SiriOrbPhase.thinking => 0.32 + 0.12 * math.sin(_phaseTime * 2.2),
      SiriOrbPhase.summon => 0.58,
      SiriOrbPhase.listening => math.max(rawE, 0.12),
      SiriOrbPhase.speaking => math.max(rawE, 0.15),
      _ => 0.06,
    };

    _energySpring.step(ambientE, dt);
    _freqSpring.step(
      widget.phase == SiriOrbPhase.thinking ? 0.70 : rawF,
      dt,
    );

    final activeBurst =
        (widget.phase == SiriOrbPhase.listening ||
            widget.phase == SiriOrbPhase.speaking ||
            widget.phase == SiriOrbPhase.summon)
        ? (ambientE * 1.04 + _summonFlash * 0.35).clamp(0.0, 1.05)
        : (widget.phase == SiriOrbPhase.thinking ? 0.24 : 0.04);
    _eruptionSpring.step(reducedMotion ? activeBurst * 0.25 : activeBurst, dt);

    final eNow = _energySpring.value.clamp(0.0, 1.1);
    final fNow = _freqSpring.value.clamp(0.15, 1.0);

    final baseSpeed = switch (widget.phase) {
      SiriOrbPhase.summon => 2.5,
      SiriOrbPhase.thinking => 2.9,
      SiriOrbPhase.listening => 1.30 + eNow * 1.10 + fNow * 0.50,
      SiriOrbPhase.speaking => 1.40 + eNow * 1.20 + fNow * 0.60,
      SiriOrbPhase.dismissing => 1.5,
      _ => 0.80,
    };
    _phaseTime += dt * (reducedMotion ? 0.22 : baseSpeed);

    if (_summonFlash > 0.0) {
      _summonFlash = (_summonFlash - dt / 0.28).clamp(0.0, 1.0);
    }

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final eVal = _energySpring.value.clamp(0.0, 1.08);
    final fVal = _freqSpring.value.clamp(0.15, 1.0);
    final eruptVal = _eruptionSpring.value.clamp(0.0, 1.08);
    final velVal = (_energySpring.velocity.abs() / 5.5).clamp(0.0, 1.0);

    final breathScale = reducedMotion
        ? 1.0
        : (1.0 + 0.035 * eVal + 0.045 * _summonFlash).clamp(0.95, 1.12);

    return Semantics(
      label: 'Indikator gelombang suara asisten',
      child: RepaintBoundary(
        child: Transform.scale(
          scale: breathScale,
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _SiriFluidWaveOrbPainter(
              t: _phaseTime,
              energy: eVal,
              frequency: fVal,
              eruption: eruptVal,
              velocityBoost: velVal,
              summonFlash: _summonFlash,
              phase: widget.phase,
            ),
          ),
        ),
      ),
    );
  }
}

class _SiriFluidWaveOrbPainter extends CustomPainter {
  const _SiriFluidWaveOrbPainter({
    required this.t,
    required this.energy,
    required this.frequency,
    required this.eruption,
    required this.velocityBoost,
    required this.summonFlash,
    required this.phase,
  });

  final double t;
  final double energy;
  final double frequency;
  final double eruption;
  final double velocityBoost;
  final double summonFlash;
  final SiriOrbPhase phase;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.5);
    // Radius bola kaca 0.285 dari kanvas -> menyisakan margin aman di segala sisi
    // agar puncak gelombang yang keluar dari bola tidak pernah terpotong batas kotak!
    final rBall = math.min(size.width, size.height) * 0.285;

    // Dispersi Chromatic Aberration optik yang rapat & tajam (tidak terpecah jadi garis terpisah)
    final aberrationPx =
        (rBall * (0.028 + 0.042 * energy + 0.032 * velocityBoost))
            .clamp(0.7, rBall * 0.095);

    // 1. Pendaran Atmosfer Luar (Prismatic Halation)
    _drawAtmosphericAura(canvas, center, rBall, aberrationPx);

    // 2. Bola Kaca Gelap Pekat (Deep Obsidian Glass) agar kontras bagian dalam tetap mewah
    final membranePath = _buildBreathingMembranePath(center, rBall);
    _drawObsidianGlassSphere(canvas, center, rBall, membranePath);

    // Titik pusaran kaustik Lissajous
    final orbit = phase == SiriOrbPhase.thinking ? 0.09 : (0.04 + 0.07 * energy);
    final nexus = Offset(
      center.dx + rBall * orbit * math.sin(1.13 * t),
      center.dy + rBall * (orbit * 0.85) * math.cos(0.87 * t),
    );

    // 3. Dua Selubung Cairan Polar Halus (Dominan Copper Orange #F26B1D & Amber #FF7A2E)
    _drawFluidPolarAurora(
      canvas: canvas,
      center: center,
      rBall: rBall,
      lobes: 2,
      phaseShift: t * 1.15,
      eruptionReach: 0.08 + 0.28 * eruption,
      aberrationPx: aberrationPx,
      coreColor: const Color(0xFFF26B1D),
      redFringe: const Color(0xFFFF5722),
      cyanFringe: const Color(0xFFFFB300),
      intensity: 0.55 + 0.28 * energy,
    );

    _drawFluidPolarAurora(
      canvas: canvas,
      center: center,
      rBall: rBall,
      lobes: 3,
      phaseShift: -t * 1.42 + 1.2,
      eruptionReach: 0.06 + 0.32 * eruption,
      aberrationPx: aberrationPx * 1.1,
      coreColor: const Color(0xFFFF9800),
      redFringe: const Color(0xFFE65100),
      cyanFringe: const Color(0xFFFFD54F),
      intensity: 0.45 + 0.26 * energy,
    );

    // 4. Tiga Pita Gelombang Sinus Koheren (SiriWave × SUICOrbView)
    // Dominan Orange hangat berpadu Amber & Sunlit Gold
    final chordSpan = 1.04 + (0.28 * eruption).clamp(0.0, 0.30);
    final baseTilt = 0.14 * math.sin(0.45 * t);
    final spatialFreq = 2.8 + 3.4 * frequency;

    // Pita Sinus Utama: Deep Copper-Orange -> Putih Panas
    _drawSiriWaveRibbon(
      canvas: canvas,
      center: nexus,
      rBall: rBall,
      axisAngle: baseTilt - 0.16,
      chordSpan: chordSpan,
      amplitude: rBall * (0.24 + 0.62 * energy + 0.15 * summonFlash),
      spatialFreq: spatialFreq,
      temporalPhase: t * 3.2,
      foldPhase: 1.05,
      aberrationPx: aberrationPx,
      primaryColor: const Color(0xFFF26B1D),
      warmShiftColor: const Color(0xFFFF3D00),
      coolShiftColor: const Color(0xFFFFB74D),
      opacity: 0.80 + 0.20 * energy,
    );

    // Pita Sinus Kedua: Vibrant Tangerine-Orange
    _drawSiriWaveRibbon(
      canvas: canvas,
      center: nexus,
      rBall: rBall,
      axisAngle: baseTilt + 0.22,
      chordSpan: chordSpan * 0.98,
      amplitude: rBall * (0.20 + 0.54 * energy + 0.12 * summonFlash),
      spatialFreq: spatialFreq * 1.22,
      temporalPhase: -t * 3.5 + 1.4,
      foldPhase: -1.15,
      aberrationPx: aberrationPx * 1.08,
      primaryColor: const Color(0xFFFF7A2E),
      warmShiftColor: const Color(0xFFDD2C00),
      coolShiftColor: const Color(0xFFFFE082),
      opacity: 0.70 + 0.20 * energy,
    );

    // Pita Sinus Ketiga: Sunlit Golden Amber
    _drawSiriWaveRibbon(
      canvas: canvas,
      center: nexus,
      rBall: rBall,
      axisAngle: baseTilt - 0.42,
      chordSpan: chordSpan * 0.94,
      amplitude: rBall * (0.15 + 0.48 * energy * (0.60 + 0.60 * frequency)),
      spatialFreq: spatialFreq * 1.48,
      temporalPhase: t * 4.2 + 2.5,
      foldPhase: 0.85,
      aberrationPx: aberrationPx * 1.12,
      primaryColor: const Color(0xFFFFAB40),
      warmShiftColor: const Color(0xFFFF6D00),
      coolShiftColor: const Color(0xFFFFF3E0),
      opacity: 0.60 + 0.24 * energy,
    );

    // 5. Inti Singularitas Putih-Emas Pijar di Pusat Pertemuan Gelombang
    final coreR = rBall * (0.34 + 0.18 * energy + 0.18 * summonFlash);
    final corePaint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.radial(
        nexus,
        coreR,
        [
          Colors.white.withValues(alpha: (0.94 + 0.06 * summonFlash).clamp(0.0, 1.0)),
          const Color(0xFFFFFBEB).withValues(alpha: 0.68),
          const Color(0xFFFF7A2E).withValues(alpha: 0.24),
          const Color(0x00F26B1D),
        ],
        const [0.0, 0.22, 0.56, 1.0],
      );
    canvas.drawCircle(nexus, coreR, corePaint);

    // 6. Cincin Refraksi Kaca Halus yang Melunak Saat Gelombang Menyembur Keluar
    _drawYieldingGlassRim(canvas, center, rBall, membranePath);
  }

  void _drawAtmosphericAura(
    Canvas canvas,
    Offset center,
    double rBall,
    double aberrationPx,
  ) {
    final baseAlpha = (0.20 + 0.22 * energy + 0.24 * summonFlash).clamp(0.0, 0.68);
    final blurSigma = (rBall * (0.32 + 0.24 * energy)).clamp(4.0, 18.0);

    canvas.drawCircle(
      center + Offset(-aberrationPx * 1.4, -aberrationPx * 0.8),
      rBall * (1.02 + 0.18 * eruption),
      Paint()
        ..color = const Color(0xFFFF2A6D).withValues(alpha: baseAlpha * 0.36)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma),
    );
    canvas.drawCircle(
      center + Offset(aberrationPx * 1.4, aberrationPx * 0.8),
      rBall * (1.00 + 0.16 * eruption),
      Paint()
        ..color = const Color(0xFF22D3EE).withValues(alpha: baseAlpha * 0.28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma),
    );
    canvas.drawCircle(
      center,
      rBall * (1.06 + 0.20 * eruption),
      Paint()
        ..color = const Color(0xFFF26B1D).withValues(alpha: baseAlpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma * 1.1),
    );
  }

  Path _buildBreathingMembranePath(Offset center, double rBall) {
    const int n = 64;
    final pts = List<Offset>.generate(n, (i) {
      final theta = (i / n) * 2.0 * math.pi;
      final deform =
          (0.012 + 0.042 * eruption) * math.sin(2.0 * theta + 1.5 * t) +
          (0.010 + 0.032 * eruption) * math.cos(3.0 * theta - 2.1 * t);
      final r = rBall * (1.0 + deform);
      return Offset(center.dx + r * math.cos(theta), center.dy + r * math.sin(theta));
    });
    return _closedSmoothSpline(pts);
  }

  void _drawObsidianGlassSphere(
    Canvas canvas,
    Offset center,
    double rBall,
    Path membranePath,
  ) {
    canvas.save();
    canvas.clipPath(membranePath);

    final basePaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        rBall * 1.05,
        const [
          Color(0xFF070304),
          Color(0xFF130706),
          Color(0xFF2B0E07),
        ],
        const [0.0, 0.70, 1.0],
      );
    canvas.drawCircle(center, rBall * 1.12, basePaint);

    // Fresnel multi-spektrum tipis di tepi dalam kaca
    canvas.saveLayer(
      Rect.fromCircle(center: center, radius: rBall * 1.12),
      Paint()..blendMode = BlendMode.screen,
    );
    canvas.drawCircle(
      center,
      rBall * 1.10,
      Paint()
        ..shader = ui.Gradient.sweep(
          center,
          [
            const Color(0xFFF26B1D).withValues(alpha: 0.45),
            const Color(0xFF22D3EE).withValues(alpha: 0.34 + 0.14 * energy),
            const Color(0xFFFF9F43).withValues(alpha: 0.42),
            const Color(0xFFFF2A6D).withValues(alpha: 0.42 + 0.16 * energy),
            const Color(0xFFF26B1D).withValues(alpha: 0.45),
          ],
          const [0.0, 0.26, 0.52, 0.78, 1.0],
        ),
    );
    canvas.drawCircle(
      center,
      rBall * 1.10,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.radial(
          center,
          rBall * 1.02,
          const [
            Color(0x00000000),
            Color(0x00000000),
            Color(0x99FFFFFF),
            Color(0xFFFFFFFF),
          ],
          const [0.0, 0.72, 0.90, 1.0],
        ),
    );
    canvas.restore();
    canvas.restore();
  }

  /// Selubung cairan polar mulus yang menyembur keluar dari bola dengan gradien tepi-terang
  /// (Beer-Lambert optical shell: transparan di tengah sehingga bagian dalam bola tetap hitam pekat).
  void _drawFluidPolarAurora({
    required Canvas canvas,
    required Offset center,
    required double rBall,
    required int lobes,
    required double phaseShift,
    required double eruptionReach,
    required double aberrationPx,
    required Color coreColor,
    required Color redFringe,
    required Color cyanFringe,
    required double intensity,
  }) {
    const int n = 64;

    List<Offset> sampleAurora(double radialShiftPx, double phaseDelta) {
      return List<Offset>.generate(n, (i) {
        final theta = (i / n) * 2.0 * math.pi;
        final w1 = math.sin(lobes * theta + phaseShift + phaseDelta);
        final w2 = 0.42 * math.cos((lobes + 1) * theta - 1.3 * phaseShift + phaseDelta);
        final raw = (w1 + w2) / 1.42;

        final double radialFactor = raw >= 0.0
            ? 0.90 + (0.10 + eruptionReach) * math.pow(raw, 1.18).toDouble()
            : 0.90 + 0.16 * raw;
        final r = rBall * radialFactor + radialShiftPx;
        return Offset(center.dx + r * math.cos(theta), center.dy + r * math.sin(theta));
      });
    }

    final pathCore = _closedSmoothSpline(sampleAurora(0.0, 0.0));
    final pathRed = _closedSmoothSpline(sampleAurora(aberrationPx, -0.05));
    final pathCyan = _closedSmoothSpline(sampleAurora(-aberrationPx * 0.9, 0.05));

    final maxR = rBall * (1.02 + eruptionReach);
    final op = intensity.clamp(0.0, 0.85);

    // Profil optik Beer-Lambert: bening di pusat (0..0.64), bercahaya lembut menjelang tepi gelombang!
    final shellFill = Paint()
      ..isAntiAlias = true
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.radial(
        center,
        maxR,
        [
          coreColor.withValues(alpha: 0.0),
          coreColor.withValues(alpha: op * 0.08),
          coreColor.withValues(alpha: op * 0.34),
          Color.lerp(coreColor, Colors.white, 0.35)!.withValues(alpha: op * 0.42),
        ],
        const [0.0, 0.58, 0.86, 1.0],
      );
    canvas.drawPath(pathCore, shellFill);

    // Dispersi kromatik halus melekat rapat pada punggung gelombang cairan
    canvas.drawPath(
      pathRed,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..blendMode = BlendMode.plus
        ..color = redFringe.withValues(alpha: op * 0.58)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
    );
    canvas.drawPath(
      pathCyan,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..blendMode = BlendMode.plus
        ..color = cyanFringe.withValues(alpha: op * 0.52)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8),
    );
    canvas.drawPath(
      pathCore,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..blendMode = BlendMode.plus
        ..color = Color.lerp(coreColor, Colors.white, 0.55)!.withValues(alpha: op * 0.78),
    );
  }

  /// Pita gelombang sinus SiriWave yang melengkung mulus naik-turun mengikuti frekuensi & volume,
  /// menembus keluar batas bola dengan tepi kaustik tajam dan dispersi kromatik rapat.
  void _drawSiriWaveRibbon({
    required Canvas canvas,
    required Offset center,
    required double rBall,
    required double axisAngle,
    required double chordSpan,
    required double amplitude,
    required double spatialFreq,
    required double temporalPhase,
    required double foldPhase,
    required double aberrationPx,
    required Color primaryColor,
    required Color warmShiftColor,
    required Color coolShiftColor,
    required double opacity,
  }) {
    const int steps = 48;
    final tangent = Offset(math.cos(axisAngle), math.sin(axisAngle));
    final normal = Offset(-tangent.dy, tangent.dx);
    final halfLen = rBall * chordSpan;

    List<Offset> sampleCurve({
      required double ampScale,
      required double freqMul,
      required double phaseAdd,
      required double shiftPx,
    }) {
      return List<Offset>.generate(steps + 1, (i) {
        final u = (i / steps) * 2.0 - 1.0;
        // Persamaan atenuasi klasik SiriWave iOS: (1 + (u/K)^2)^(-2.1) -> meruncing mulus di ujung!
        final att = math.pow(1.0 + (u / 0.68) * (u / 0.68), -2.05).toDouble();
        final edgeZero = math.cos(u * math.pi * 0.5).clamp(0.0, 1.0);
        final env = att * math.pow(edgeZero, 0.5).toDouble();

        final wave =
            math.sin(u * spatialFreq * freqMul - temporalPhase + phaseAdd) +
            0.28 * math.sin(u * spatialFreq * 2.0 * freqMul + 1.25 * temporalPhase);
        final disp = amplitude * ampScale * env * (wave / 1.28) + shiftPx * env;
        return center + tangent * (u * halfLen) + normal * disp;
      });
    }

    final upperPts = sampleCurve(ampScale: 1.0, freqMul: 1.0, phaseAdd: 0.0, shiftPx: 0.0);
    final lowerPts = sampleCurve(ampScale: 0.42, freqMul: 0.88, phaseAdd: foldPhase, shiftPx: 0.0);
    final warmPts = sampleCurve(ampScale: 1.02, freqMul: 1.0, phaseAdd: -0.06, shiftPx: aberrationPx);
    final coolPts = sampleCurve(ampScale: 0.98, freqMul: 1.0, phaseAdd: 0.06, shiftPx: -aberrationPx);

    final ribbonPath = _openSmoothSpline(upperPts);
    final rev = lowerPts.reversed.toList();
    for (int i = 0; i < rev.length; i++) {
      final p = rev[i];
      if (i == 0) {
        ribbonPath.lineTo(p.dx, p.dy);
      } else {
        final prev = rev[i - 1];
        ribbonPath.quadraticBezierTo(
          prev.dx,
          prev.dy,
          (prev.dx + p.dx) * 0.5,
          (prev.dy + p.dy) * 0.5,
        );
      }
    }
    ribbonPath.close();

    final alpha = opacity.clamp(0.0, 0.92);

    // Selaput cairan sutera translusen di antara dua kurva sinus (membentuk efek lipatan Siri)
    canvas.drawPath(
      ribbonPath,
      Paint()
        ..isAntiAlias = true
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(
          center,
          halfLen,
          [
            Colors.white.withValues(alpha: alpha * 0.30),
            primaryColor.withValues(alpha: alpha * 0.34),
            warmShiftColor.withValues(alpha: alpha * 0.14),
            primaryColor.withValues(alpha: 0.0),
          ],
          const [0.0, 0.40, 0.82, 1.0],
        ),
    );

    final mainPath = _openSmoothSpline(upperPts);
    final warmPath = _openSmoothSpline(warmPts);
    final coolPath = _openSmoothSpline(coolPts);

    // Pendaran cairan penyatu (fluid bloom)
    canvas.drawPath(
      mainPath,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3.6
        ..blendMode = BlendMode.plus
        ..color = primaryColor.withValues(alpha: alpha * 0.38)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.8),
    );

    // Dispersi Chromatic Aberration Merah-Magenta & Cyan-Prismatik tepat di bibir gelombang
    canvas.drawPath(
      warmPath,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.7
        ..blendMode = BlendMode.plus
        ..color = warmShiftColor.withValues(alpha: alpha * 0.68)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.3),
    );
    canvas.drawPath(
      coolPath,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.6
        ..blendMode = BlendMode.plus
        ..color = coolShiftColor.withValues(alpha: alpha * 0.62)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );

    // Garis Punggung Gelombang Sinus Tajam Berkilau (Caustic Crest)
    canvas.drawPath(
      mainPath,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.3
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(
          center - tangent * halfLen,
          center + tangent * halfLen,
          [
            primaryColor.withValues(alpha: 0.0),
            Color.lerp(primaryColor, Colors.white, 0.65)!.withValues(alpha: alpha * 0.90),
            Colors.white.withValues(alpha: (alpha * 1.05).clamp(0.0, 0.98)),
            Color.lerp(primaryColor, Colors.white, 0.65)!.withValues(alpha: alpha * 0.90),
            primaryColor.withValues(alpha: 0.0),
          ],
          const [0.0, 0.22, 0.50, 0.78, 1.0],
        ),
    );
  }

  void _drawYieldingGlassRim(
    Canvas canvas,
    Offset center,
    double rBall,
    Path membranePath,
  ) {
    final rimOpacity = (0.58 - 0.30 * eruption).clamp(0.18, 0.62);
    canvas.drawPath(
      membranePath,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.05
        ..shader = ui.Gradient.sweep(
          center,
          [
            const Color(0xFFFFF7ED).withValues(alpha: rimOpacity),
            const Color(0xFFFF9F43).withValues(alpha: rimOpacity * 0.72),
            const Color(0xFF38BDF8).withValues(alpha: rimOpacity * 0.48),
            const Color(0xFFFF2A6D).withValues(alpha: rimOpacity * 0.55),
            const Color(0xFFFFF7ED).withValues(alpha: rimOpacity),
          ],
          const [0.0, 0.26, 0.52, 0.78, 1.0],
        ),
    );

    final specRect = Rect.fromCircle(center: center, radius: rBall * 0.91);
    canvas.drawArc(
      specRect,
      -2.55,
      1.0,
      false,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(
          center + Offset(-rBall * 0.8, -rBall * 0.8),
          center,
          [
            Colors.white.withValues(alpha: (0.44 - 0.18 * eruption).clamp(0.12, 0.46)),
            Colors.white.withValues(alpha: 0.0),
          ],
        ),
    );
  }

  static Path _closedSmoothSpline(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    final n = pts.length;
    final firstMid = Offset(
      (pts[n - 1].dx + pts[0].dx) * 0.5,
      (pts[n - 1].dy + pts[0].dy) * 0.5,
    );
    path.moveTo(firstMid.dx, firstMid.dy);
    for (int i = 0; i < n; i++) {
      final curr = pts[i];
      final next = pts[(i + 1) % n];
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

  static Path _openSmoothSpline(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length - 1; i++) {
      final curr = pts[i];
      final next = pts[i + 1];
      path.quadraticBezierTo(
        curr.dx,
        curr.dy,
        (curr.dx + next.dx) * 0.5,
        (curr.dy + next.dy) * 0.5,
      );
    }
    if (pts.length > 1) {
      path.lineTo(pts.last.dx, pts.last.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _SiriFluidWaveOrbPainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.energy != energy ||
        oldDelegate.frequency != frequency ||
        oldDelegate.eruption != eruption ||
        oldDelegate.summonFlash != summonFlash ||
        oldDelegate.phase != phase;
  }
}
