import 'dart:math';
import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../models/trip_model.dart';
import '../auth_screen.dart';
import '../driving_card_screen.dart';
import '../supabase_service.dart';
import '../widgets/driving_buddy_app_bar.dart';

// ============================================================================
// HISTORY SCREEN (Trip Logs & Riwayat Perjalanan)
// ============================================================================

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;
  String? _userName;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final sessions = await SessionService.getUserSessions();
      final name = await AuthService.getUserName();
      if (mounted) {
        setState(() {
          _sessions = sessions;
          _userName = name;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error load history: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDuration(int seconds) {
    if (seconds == 0) return '0 mnt';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}j ${m}m';
    return '${m}m';
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '-';
    final dt = DateTime.tryParse(isoDate)?.toLocal();
    if (dt == null) return '-';
    final now = DateTime.now();
    final diff = now.difference(dt).inDays;
    if (diff == 0) return 'Hari ini';
    if (diff == 1) return 'Kemarin';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Color _scoreColor(int score) {
    if (score >= 80) return AppColors.success;
    if (score >= 50) return AppColors.warning;
    return AppColors.danger;
  }

  // Hitung total waktu semua sesi dalam detik
  int get _totalSeconds =>
      _sessions.fold(0, (sum, s) => sum + ((s['duration_seconds'] as num?)?.toInt() ?? 0));

  // Rata-rata skor semua sesi
  int get _avgScore {
    if (_sessions.isEmpty) return 100;
    final total =
        _sessions.fold(0, (sum, s) => sum + ((s['driving_score'] as num?)?.toInt() ?? 100));
    return (total / _sessions.length).round();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: AppColors.primary,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(
                child: DrivingBuddyAppBar(),
              ),

              // Summary card
              SliverToBoxAdapter(child: _buildSummaryCard()),

              // List header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Riwayat Perjalanan (${_sessions.length})',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded,
                            color: AppColors.primary, size: 20),
                        onPressed: _loadData,
                        tooltip: 'Refresh',
                      ),
                    ],
                  ),
                ),
              ),

              // Loading / empty / list
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              else if (_sessions.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.directions_car_outlined,
                            size: 64, color: AppColors.textSecondary.withOpacity(0.3)),
                        const SizedBox(height: 16),
                        const Text(
                          'Belum ada sesi perjalanan',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Mulai sesi monitoring untuk\nmenyimpan data perjalananmu',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.builder(
                    itemCount: _sessions.length,
                    itemBuilder: (context, index) {
                      final s = _sessions[index];
                      return _buildSessionCard(s);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📊  Ringkasan Semua Sesi',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const Spacer(),
              if (_userName != null)
                Text('👤 $_userName',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _SummaryStatItem(
                value: '${_sessions.length}',
                label: 'Sesi Total',
              ),
              Container(width: 1, height: 40, color: Colors.grey.shade200),
              _SummaryStatItem(
                value: _formatDuration(_totalSeconds),
                label: 'Total Waktu',
              ),
              Container(width: 1, height: 40, color: Colors.grey.shade200),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$_avgScore',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: _scoreColor(_avgScore),
                      ),
                    ),
                    const Text('Rata-rata Skor',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> session) {
    final score = (session['driving_score'] as num?)?.toInt() ?? 100;
    final duration = (session['duration_seconds'] as num?)?.toInt() ?? 0;
    final drowsy = (session['total_drowsy_events'] as num?)?.toInt() ?? 0;
    final yawn = (session['total_yawns'] as num?)?.toInt() ?? 0;
    final micro = (session['total_microsleeps'] as num?)?.toInt() ?? 0;
    final date = _formatDate(session['started_at'] as String?);
    final startedAt = session['started_at'] as String?;
    String timeStr = '-';
    if (startedAt != null) {
      final dt = DateTime.tryParse(startedAt)?.toLocal();
      if (dt != null) {
        timeStr =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    }

    final scoreColor = _scoreColor(score);
    final totalEvents = drowsy + yawn + micro;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scoreColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Skor $score',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scoreColor,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '$date  $timeStr',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MiniStat(
                  icon: Icons.timer_outlined,
                  value: _formatDuration(duration),
                  label: 'Durasi'),
              const SizedBox(width: 16),
              _MiniStat(
                  icon: Icons.warning_amber_rounded,
                  value: '$totalEvents',
                  label: 'Event',
                  color: totalEvents > 0 ? AppColors.warning : AppColors.success),
              const SizedBox(width: 16),
              _MiniStat(
                  icon: Icons.bedtime_outlined,
                  value: '$micro',
                  label: 'Microsleep',
                  color: micro > 0 ? AppColors.danger : AppColors.success),
            ],
          ),
          if (totalEvents > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 14, color: AppColors.danger),
                  const SizedBox(width: 6),
                  Text(
                    '${drowsy}x kantuk · ${yawn}x menguap · ${micro}x microsleep',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.danger),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DrivingCardScreen(
                      durationSeconds: duration,
                      drivingScore: score,
                      totalMicrosleeps: micro,
                      totalDrowsy: drowsy,
                      totalYawns: yawn,
                      startedAt: session['started_at'] != null
                          ? DateTime.tryParse(session['started_at'] as String)
                          : null,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.workspace_premium_rounded,
                  size: 16, color: Color(0xFFFF6D00)),
              label: const Text(
                'Lihat Kartu Berkendara',
                style: TextStyle(
                    color: Color(0xFFFF6D00),
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFFF6D00), width: 1),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Mini Stat Widget ----
class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
    this.color = AppColors.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color)),
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary)),
          ],
        ),
      ],
    );
  }
}

// ---- Summary Stat Item ----
class _SummaryStatItem extends StatelessWidget {
  final String value;
  final String label;

  const _SummaryStatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ---- Trip Card ----
class _TripCard extends StatelessWidget {
  final TripRecord trip;

  const _TripCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.routeName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${trip.dateInfo} · ${trip.timeRange}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trip.duration,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: trip.warningColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: trip.warningColor.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      trip.warningColor == AppColors.success
                          ? Icons.check_circle_rounded
                          : Icons.warning_amber_rounded,
                      size: 12,
                      color: trip.warningColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      trip.warningLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: trip.warningColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  trip.driverStatus,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _EarGraphPlaceholder(data: trip.earGraphData),
          const SizedBox(height: 14),
          Row(
            children: [
              _TripStatChip(
                label: 'Rata-rata EAR',
                value: trip.avgEAR.toStringAsFixed(2),
                icon: Icons.remove_red_eye_outlined,
              ),
              const Spacer(),
              _TripStatChip(
                label: 'Kecepatan',
                value: '${trip.avgSpeed}',
                unit: 'km/j',
                icon: Icons.speed_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {},
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Lihat Detail Sesi',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 12, color: AppColors.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Trip Stat Chip ----
class _TripStatChip extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final IconData icon;

  const _TripStatChip({
    required this.label,
    required this.value,
    this.unit,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary)),
            Row(
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 3),
                  Text(unit!,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ],
        ),
      ],
    );
  }
}

// ---- EAR Graph (CustomPainter) ----
class _EarGraphPlaceholder extends StatelessWidget {
  final List<double> data;

  const _EarGraphPlaceholder({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CustomPaint(painter: _EarLinePainter(data: data)),
      ),
    );
  }
}

class _EarLinePainter extends CustomPainter {
  final List<double> data;

  _EarLinePainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final double minVal = data.reduce(min) - 0.05;
    final double maxVal = data.reduce(max) + 0.05;
    final double range = maxVal - minVal;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.primary.withOpacity(0.20),
          AppColors.primary.withOpacity(0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final linePaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height - ((data[i] - minVal) / range) * size.height;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        final prevX = ((i - 1) / (data.length - 1)) * size.width;
        final prevY =
            size.height - ((data[i - 1] - minVal) / range) * size.height;
        final cpX1 = prevX + (x - prevX) / 2;
        final cpX2 = prevX + (x - prevX) / 2;
        path.cubicTo(cpX1, prevY, cpX2, y, x, y);
        fillPath.cubicTo(cpX1, prevY, cpX2, y, x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // Threshold dashed line (EAR = 0.25)
    final thresholdY =
        size.height - ((0.25 - minVal) / range) * size.height;
    final thresholdPaint = Paint()
      ..color = AppColors.danger.withOpacity(0.25)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const dashWidth = 4.0;
    const dashSpace = 4.0;
    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, thresholdY.clamp(0, size.height)),
        Offset((startX + dashWidth).clamp(0, size.width),
            thresholdY.clamp(0, size.height)),
        thresholdPaint,
      );
      startX += dashWidth + dashSpace;
    }

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    // Dots
    final dotPaint = Paint()..color = AppColors.primary;
    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height - ((data[i] - minVal) / range) * size.height;
      canvas.drawCircle(Offset(x, y), 3, dotPaint);
      canvas.drawCircle(
        Offset(x, y),
        3,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
