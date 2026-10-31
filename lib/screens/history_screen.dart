import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/design_tokens.dart';
import '../services/theme_service.dart';
import '../driving_card_screen.dart';
import '../services/firebase_service.dart';
import '../widgets/driving_buddy_app_bar.dart';

// ============================================================================
// HISTORY SCREEN (Riwayat Perjalanan Telemetri — Luxury GT)
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

  Future<void> _deleteSingleSession(String sessionId, int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Color(0xFFD94126)),
            SizedBox(width: 8),
            Text(
              'Hapus Sesi?',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'Data perjalanan ini akan dihapus permanen dari riwayat database Anda.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD94126),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await SessionService.deleteSession(sessionId);
      if (success && mounted) {
        setState(() {
          _sessions.removeAt(index);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sesi perjalanan berhasil dihapus.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _clearAllHistory() async {
    if (_sessions.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: Color(0xFFD94126), size: 28),
            SizedBox(width: 8),
            Text(
              'Bersihkan Semua?',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'Seluruh riwayat telemetri perjalanan Anda akan dikosongkan secara permanen.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD94126),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus Semua', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      final success = await SessionService.clearAllSessions();
      if (success && mounted) {
        setState(() {
          _sessions.clear();
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seluruh riwayat perjalanan berhasil dibersihkan.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
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
    if (score >= 80) return const Color(0xFF059669);
    if (score >= 50) return const Color(0xFFE5A938);
    return const Color(0xFFD94126);
  }

  int get _totalSeconds =>
      _sessions.fold(0, (sum, s) => sum + ((s['duration_seconds'] as num?)?.toInt() ?? 0));

  int get _avgScore {
    if (_sessions.isEmpty) return 0;
    final total =
        _sessions.fold(0, (sum, s) => sum + ((s['driving_score'] as num?)?.toInt() ?? 100));
    return (total / _sessions.length).round();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final isDark = ThemeService.instance.isDarkMode;

        return Scaffold(
          backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
          appBar: const DrivingBuddyAppBar(title: 'Riwayat Perjalanan'),
          body: RefreshIndicator(
            onRefresh: _loadData,
            color: const Color(0xFFF26B1D),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                // 1. Summary Card with Dial
                SliverToBoxAdapter(child: _buildSummaryCard()),

                // 2. Section Header with Clean Action Buttons
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'Daftar Sesi',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: isDark ? AppColors.darkCardBgSoft : const Color(0xFFFFF1E8),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isDark ? AppColors.darkCardBorder : const Color(0xFFECEEF2),
                                  ),
                                ),
                                child: Text(
                                  '${_sessions.length} Sesi',
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFFD9560F),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_sessions.isNotEmpty)
                              Tooltip(
                                message: 'Bersihkan Semua',
                                child: InkWell(
                                  onTap: _clearAllHistory,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isDark ? AppColors.darkDangerBg : const Color(0xFFFEF2F2),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isDark ? const Color(0xFFD94126) : const Color(0xFFFECACA),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.delete_sweep_rounded, size: 14, color: Color(0xFFD94126)),
                                        SizedBox(width: 4),
                                        Text(
                                          'Hapus',
                                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFFD94126)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(width: 4),
                            IconButton(
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(4),
                              icon: const Icon(Icons.refresh_rounded, color: Color(0xFFF26B1D), size: 19),
                              onPressed: _loadData,
                              tooltip: 'Perbarui',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 3. Loading / Empty / List
                if (_isLoading)
                  const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(color: Color(0xFFF26B1D)),
                    ),
                  )
                else if (_sessions.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.directions_car_outlined,
                            size: 56,
                            color: (isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B)).withValues(alpha: 0.35),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Belum Ada Sesi Perjalanan',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Mulai sesi berkendara untuk merekam telemetri Anda.',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B),
                            ),
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
                        return _buildSessionCard(_sessions[index], index);
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryCard() {
    final isDark = ThemeService.instance.isDarkMode;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCardBg : DbColors.pureWhite,
        borderRadius: BorderRadius.circular(DbRadius.r20),
        border: Border.all(
          color: isDark ? AppColors.darkCardBorder : DbColors.hairline,
        ),
        boxShadow: isDark ? DbShadow.cardDark : DbShadow.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TELEMETRI KUMULATIF',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: Color(0xFFD9560F),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _userName != null && _userName!.isNotEmpty
                          ? 'Perjalanan $_userName'
                          : 'Ringkasan Keseluruhan Sesi',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCardBgSoft : const Color(0xFFFFF1E8),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? AppColors.darkCardBorder : const Color(0xFFECEEF2),
                  ),
                ),
                child: const Icon(
                  Icons.auto_graph_rounded,
                  color: Color(0xFFF26B1D),
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Horizontal summary stats
          Row(
            children: [
              Expanded(
                child: _buildMetricItem(
                  icon: Icons.timer_outlined,
                  label: 'TOTAL WAKTU',
                  value: _formatDuration(_totalSeconds),
                  color: isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A),
                ),
              ),
              Container(
                height: 36,
                width: 1,
                color: isDark ? AppColors.darkCardBorder : const Color(0xFFFFF1E8),
              ),
              Expanded(
                child: _buildMetricItem(
                  icon: Icons.shield_outlined,
                  label: 'RATA-RATA SKOR',
                  value: '$_avgScore%',
                  color: _scoreColor(_avgScore),
                ),
              ),
              Container(
                height: 36,
                width: 1,
                color: isDark ? AppColors.darkCardBorder : const Color(0xFFFFF1E8),
              ),
              Expanded(
                child: _buildMetricItem(
                  icon: Icons.alt_route_rounded,
                  label: 'TOTAL SESI',
                  value: '${_sessions.length}',
                  color: const Color(0xFFF26B1D),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF64748B)),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: color,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> session, int index) {
    final isDark = ThemeService.instance.isDarkMode;
    final score = (session['driving_score'] as num?)?.toInt() ?? 100;
    final duration = (session['duration_seconds'] as num?)?.toInt() ?? 0;
    final distKm = (session['distance_km'] as num?)?.toDouble() ?? 0.0;
    final avgSpeed = (session['avg_speed_kmh'] as num?)?.toDouble() ?? 0.0;
    final topSpeed = ((session['maxSpeedKmh'] ?? session['max_speed_kmh'] ?? (avgSpeed > 0 ? avgSpeed * 1.15 : 0.0)) as num).toDouble();
    final drowsy = (session['total_drowsy_events'] as num?)?.toInt() ?? 0;
    final micro = (session['total_microsleeps'] as num?)?.toInt() ?? 0;
    final yawn = (session['total_yawns'] as num?)?.toInt() ?? 0;
    final dateStr = _formatDate(session['started_at'] as String?);
    final sessionId = (session['id'] ?? '').toString();

    final scoreColor = _scoreColor(score);
    final totalEvents = drowsy + micro;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCardBg : DbColors.pureWhite,
        borderRadius: BorderRadius.circular(DbRadius.r16),
        border: Border.all(
          color: isDark ? AppColors.darkCardBorder : DbColors.hairline,
        ),
        boxShadow: isDark ? DbShadow.cardDark : DbShadow.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Tanggal & Skor & Delete Icon Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkCardBgSoft : const Color(0xFFFFF1E8),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? AppColors.darkCardBorder : const Color(0xFFECEEF2),
                        ),
                      ),
                      child: const Icon(
                        Icons.drive_eta_rounded,
                        color: Color(0xFFF26B1D),
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dateStr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            '${distKm.toStringAsFixed(1)} km · ${avgSpeed.toStringAsFixed(0)} km/j avg',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: scoreColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scoreColor.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          score >= 80 ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                          size: 12,
                          color: scoreColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'SKOR $score%',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: scoreColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (sessionId.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF94A3B8), size: 18),
                      hoverColor: const Color(0xFFFEF2F2),
                      splashRadius: 18,
                      tooltip: 'Hapus Sesi Ini',
                      onPressed: () => _deleteSingleSession(sessionId, index),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Mini Alert Tags
          if (micro > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkDangerBg : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark ? const Color(0xFFD94126) : const Color(0xFFFECACA),
                  ),
                ),
                child: Text(
                  '${micro}x Microsleep Terdeteksi',
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFD94126),
                  ),
                ),
              ),
            ),

          // Mini Sparkline Waveform
          Container(
            height: 32,
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCardBgSoft : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? AppColors.darkCardBorder : const Color(0xFFFFF1E8),
              ),
            ),
            child: CustomPaint(
              painter: _HistorySparklinePainter(color: scoreColor),
            ),
          ),
          const SizedBox(height: 10),

          // 4-Stat Metrics Row (Durasi, Jarak, Avg Speed, Top Speed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCardBgSoft.withValues(alpha: 0.5) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? AppColors.darkCardBorder : const Color(0xFFECEEF2),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildHistoryMetricCol('DURASI', _formatDuration(duration), isDark),
                ),
                Container(height: 24, width: 1, color: isDark ? AppColors.darkCardBorder : const Color(0xFFE2E8F0)),
                Expanded(
                  child: _buildHistoryMetricCol('JARAK', '${distKm.toStringAsFixed(1)} km', isDark),
                ),
                Container(height: 24, width: 1, color: isDark ? AppColors.darkCardBorder : const Color(0xFFE2E8F0)),
                Expanded(
                  child: _buildHistoryMetricCol('AVG SPEED', '${avgSpeed.toStringAsFixed(0)} km/j', isDark),
                ),
                Container(height: 24, width: 1, color: isDark ? AppColors.darkCardBorder : const Color(0xFFE2E8F0)),
                Expanded(
                  child: _buildHistoryMetricCol('TOP SPEED', '${topSpeed.toStringAsFixed(0)} km/j', isDark),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Event Badges Bar (Resilient, Anti-Tabrakan)
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _buildEventBadge(
                icon: Icons.visibility_off_outlined,
                label: 'Kantuk',
                count: totalEvents,
                color: totalEvents > 0 ? const Color(0xFFF26B1D) : const Color(0xFF059669),
                isDark: isDark,
              ),
              _buildEventBadge(
                icon: Icons.sentiment_dissatisfied_outlined,
                label: 'Menguap',
                count: yawn,
                color: yawn > 0 ? const Color(0xFFF26B1D) : const Color(0xFF64748B),
                isDark: isDark,
              ),
              if (micro > 0)
                _buildEventBadge(
                  icon: Icons.warning_amber_rounded,
                  label: 'Microsleep',
                  count: micro,
                  color: const Color(0xFFD94126),
                  isDark: isDark,
                  isAlert: true,
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Button Buka Kartu Berkendara
          SizedBox(
            width: double.infinity,
            height: 38,
            child: OutlinedButton(
              onPressed: () async {
                final hasNet = await SessionService.hasInternetConnection();
                if (!hasNet && context.mounted) {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: const Row(
                        children: [
                          Icon(Icons.wifi_off_rounded, color: Color(0xFFF26B1D)),
                          SizedBox(width: 8),
                          Text('Koneksi Diperlukan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        ],
                      ),
                      content: const Text(
                        'Kartu Berkendara membutuhkan koneksi internet untuk memuat ubin peta satelit OpenStreetMap.\n\nSilakan sambungkan WiFi atau Data Seluler untuk melihat kartu.',
                        style: TextStyle(fontSize: 13, height: 1.4),
                      ),
                      actions: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF26B1D),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Mengerti', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                  return;
                }

                if (!context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DrivingCardScreen(
                      durationSeconds: duration,
                      drivingScore: score,
                      totalMicrosleeps: micro,
                      totalDrowsy: drowsy,
                      totalYawns: yawn,
                      distanceKm: distKm,
                      avgSpeedKmh: avgSpeed,
                      maxSpeedKmh: topSpeed,
                      startedAt: session['started_at'] != null
                          ? DateTime.tryParse(session['started_at'] as String)
                          : null,
                      sessionId: session['id'] as String?,
                      startLat: (session['startLat'] ?? session['start_lat']) != null
                          ? ((session['startLat'] ?? session['start_lat']) as num).toDouble()
                          : null,
                      startLng: (session['startLng'] ?? session['start_lng']) != null
                          ? ((session['startLng'] ?? session['start_lng']) as num).toDouble()
                          : null,
                      lastLat: (session['endLat'] ?? session['end_lat'] ?? session['lastLat'] ?? session['last_lat']) != null
                          ? ((session['endLat'] ?? session['end_lat'] ?? session['lastLat'] ?? session['last_lat']) as num).toDouble()
                          : null,
                      lastLng: (session['endLng'] ?? session['end_lng'] ?? session['lastLng'] ?? session['last_lng']) != null
                          ? ((session['endLng'] ?? session['end_lng'] ?? session['lastLng'] ?? session['last_lng']) as num).toDouble()
                          : null,
                      routePoints: (session['routePoints'] is List)
                          ? (session['routePoints'] as List)
                              .map((p) => {
                                    'lat': ((p['lat'] ?? p['latitude']) as num).toDouble(),
                                    'lng': ((p['lng'] ?? p['longitude']) as num).toDouble(),
                                  })
                              .toList()
                          : null,
                    ),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: isDark ? AppColors.darkCardBorder : const Color(0xFFECEEF2)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                backgroundColor: isDark ? AppColors.darkCardBgSoft : const Color(0xFFFFF1E8),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.workspace_premium_rounded, size: 16, color: Color(0xFFF26B1D)),
                  SizedBox(width: 6),
                  Text(
                    'Lihat Kartu Pencapaian',
                    style: TextStyle(
                      color: Color(0xFFF26B1D),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildHistoryMetricCol(String label, String value, bool isDark) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEventBadge({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
    required bool isDark,
    bool isAlert = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: isAlert ? 0.6 : 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label + ': ',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B),
            ),
          ),
          Text(
            count.toString() + 'x',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistorySparklinePainter extends CustomPainter {
  final Color color;

  _HistorySparklinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    path.moveTo(0, size.height * 0.7);
    path.cubicTo(
      size.width * 0.25, size.height * 0.8,
      size.width * 0.45, size.height * 0.2,
      size.width * 0.65, size.height * 0.4,
    );
    path.cubicTo(
      size.width * 0.8, size.height * 0.6,
      size.width * 0.9, size.height * 0.3,
      size.width, size.height * 0.5,
    );

    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HistorySparklinePainter oldDelegate) =>
      oldDelegate.color != color;
}
