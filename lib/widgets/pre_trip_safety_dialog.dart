import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../routes/app_routes.dart';
import '../services/language_service.dart';
import '../services/sos_service.dart';

/// Validator dan Dialog Pemeriksaan Pra-Perjalanan (Pre-Trip Safety Verification)
/// Memastikan Layanan Lokasi (GPS) aktif dan minimal 1 Kontak Darurat SOS telah diisi.
class PreTripValidator {
  /// Memeriksa status kesiapan lokasi & kontak SOS.
  /// Jika siap, langsung mengembalikan true.
  /// Jika belum, menampilkan pop-up verifikasi wajib.
  static Future<bool> validateAndPrompt(BuildContext context) async {
    final status = await checkStatus();

    if (status.isLocationReady && status.hasSos) {
      return true;
    }

    if (!context.mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PreTripSafetyDialog(
        initialStatus: status,
      ),
    );

    return result ?? false;
  }

  /// Cek kondisi saat ini secara asinkron
  static Future<PreTripStatus> checkStatus() async {
    bool isLocationServiceOn = false;
    LocationPermission perm = LocationPermission.denied;

    try {
      isLocationServiceOn = await Geolocator.isLocationServiceEnabled();
      perm = await Geolocator.checkPermission();
      if (isLocationServiceOn && perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
    } catch (e) {
      debugPrint('PreTripValidator location check error: $e');
    }

    final isLocationReady = isLocationServiceOn &&
        (perm == LocationPermission.always || perm == LocationPermission.whileInUse);

    bool hasSos = false;
    try {
      hasSos = await SosService.hasValidSosPhone();
    } catch (e) {
      debugPrint('PreTripValidator sos check error: $e');
    }

    return PreTripStatus(
      isLocationReady: isLocationReady,
      hasSos: hasSos,
      isGpsEnabled: isLocationServiceOn,
      permission: perm,
    );
  }
}

class PreTripStatus {
  final bool isLocationReady;
  final bool hasSos;
  final bool isGpsEnabled;
  final LocationPermission permission;

  const PreTripStatus({
    required this.isLocationReady,
    required this.hasSos,
    required this.isGpsEnabled,
    required this.permission,
  });
}

class PreTripSafetyDialog extends StatefulWidget {
  final PreTripStatus initialStatus;

  const PreTripSafetyDialog({
    super.key,
    required this.initialStatus,
  });

  @override
  State<PreTripSafetyDialog> createState() => _PreTripSafetyDialogState();
}

class _PreTripSafetyDialogState extends State<PreTripSafetyDialog>
    with WidgetsBindingObserver {
  late PreTripStatus _status;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Saat user kembali dari pengaturan lokasi atau aplikasi lain, periksa ulang otomatis
    if (state == AppLifecycleState.resumed) {
      _recheckStatus();
    }
  }

  Future<void> _recheckStatus() async {
    if (!mounted) return;
    setState(() => _isChecking = true);
    final s = await PreTripValidator.checkStatus();
    if (mounted) {
      setState(() {
        _status = s;
        _isChecking = false;
      });
      // Jika kedua syarat sudah terpenuhi setelah user menyalakan lokasi / simpan SOS
      if (_status.isLocationReady && _status.hasSos) {
        Navigator.pop(context, true);
      }
    }
  }

  Future<void> _handleEnableLocation() async {
    try {
      if (!_status.isGpsEnabled) {
        await Geolocator.openLocationSettings();
      } else if (_status.permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
      } else {
        await Geolocator.requestPermission();
      }
    } catch (e) {
      debugPrint('Open location settings error: $e');
    }
    await _recheckStatus();
  }

  Future<void> _handleFillSos() async {
    // Arahkan langsung ke Pengaturan akun dengan fokus pada kartu SOS
    await Navigator.pushNamed(
      context,
      AppRoutes.settings,
      arguments: {'focus': 'sos'},
    );
    // Saat kembali dari halaman Pengaturan, cek ulang status SOS
    await _recheckStatus();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = LanguageService.instance.isEnglish;

    final title = (!_status.isLocationReady && !_status.hasSos)
        ? (isEn ? 'Safety Verification Required' : 'Verifikasi Keselamatan Wajib')
        : (!_status.isLocationReady)
            ? (isEn ? 'Location (GPS) Required' : 'Layanan Lokasi (GPS) Wajib Aktif')
            : (isEn ? 'SOS Contact Required' : 'Kontak Darurat SOS Wajib Diisi');

    final subtitle = (!_status.isLocationReady && !_status.hasSos)
        ? (isEn
            ? 'Before starting your trip, Driving Buddy requires active GPS location and at least 1 emergency SOS contact for driver safety.'
            : 'Sebelum memulai sesi berkendara, Driving Buddy mewajibkan Anda untuk menyalakan lokasi dan mengisi minimal 1 kontak darurat SOS.')
        : (!_status.isLocationReady)
            ? (isEn
                ? 'Active GPS is required to record real-time speed, travel route, and pinpoint your coordinates in case of an emergency.'
                : 'Lokasi (GPS) wajib aktif untuk merekam kecepatan aktual, rute perjalanan, dan titik koordinat jika terjadi kondisi darurat.')
            : (isEn
                ? 'For your safety, at least 1 WhatsApp emergency contact is required to automatically receive alerts if severe microsleep is detected.'
                : 'Demi keselamatan Anda, minimal 1 kontak WhatsApp darurat wajib diisi agar sistem dapat mengirim peringatan otomatis saat terjadi microsleep.');

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      elevation: 24,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icon Header
              Center(
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
                    color: Color(0xFFF26B1D),
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Title
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 8),

              // Subtitle
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),

              // ── CARD 1: SYARAT LOKASI (GPS) ──
              _buildRequirementCard(
                icon: Icons.location_on_rounded,
                title: isEn ? '1. Device Location (GPS)' : '1. Layanan Lokasi (GPS)',
                isReady: _status.isLocationReady,
                statusText: _status.isLocationReady
                    ? (isEn ? 'Location Active' : 'Lokasi Aktif & Siaga')
                    : (isEn ? 'Location Disabled' : 'Lokasi Belum Aktif'),
                actionText: isEn ? 'Turn On Location' : 'Nyalakan Lokasi',
                onAction: _handleEnableLocation,
                accentColor: const Color(0xFF3B82F6),
              ),
              const SizedBox(height: 10),

              // ── CARD 2: SYARAT KONTAK SOS ──
              _buildRequirementCard(
                icon: Icons.emergency_rounded,
                title: isEn ? '2. SOS Emergency Contact' : '2. Kontak Darurat SOS',
                isReady: _status.hasSos,
                statusText: _status.hasSos
                    ? (isEn ? 'SOS Contact Ready' : 'Kontak Terdaftar')
                    : (isEn ? 'Not Set (Min. 1 Number)' : 'Belum Ada (Min. 1 Nomor)'),
                actionText: isEn ? 'Fill Now' : 'Isi Sekarang',
                onAction: _handleFillSos,
                accentColor: const Color(0xFFEF4444),
              ),
              const SizedBox(height: 20),

              // ── BUTTON ACTIONS ──
              Row(
                children: [
                  // Tombol Batal
                  Expanded(
                    flex: 1,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF94A3B8),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        isEn ? 'Cancel' : 'Batal',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Tombol Periksa / Mulai
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isChecking
                          ? null
                          : () async {
                              await _recheckStatus();
                              if (_status.isLocationReady && _status.hasSos) {
                                if (context.mounted) Navigator.pop(context, true);
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (_status.isLocationReady && _status.hasSos)
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF26B1D),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 4,
                      ),
                      icon: _isChecking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(
                              (_status.isLocationReady && _status.hasSos)
                                  ? Icons.play_arrow_rounded
                                  : Icons.refresh_rounded,
                              size: 18,
                            ),
                      label: Text(
                        (_status.isLocationReady && _status.hasSos)
                            ? (isEn ? 'Start Trip' : 'Mulai Perjalanan')
                            : (isEn ? 'Recheck Status' : 'Periksa Status'),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRequirementCard({
    required IconData icon,
    required String title,
    required bool isReady,
    required String statusText,
    required String actionText,
    required VoidCallback onAction,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isReady
              ? const Color(0xFF10B981).withValues(alpha: 0.4)
              : const Color(0xFFEF4444).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon Box
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isReady
                  ? const Color(0xFF10B981).withValues(alpha: 0.18)
                  : accentColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isReady ? Icons.check_circle_rounded : icon,
              color: isReady ? const Color(0xFF10B981) : accentColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),

          // Title & Status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isReady ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        statusText,
                        style: TextStyle(
                          color: isReady ? const Color(0xFF10B981) : const Color(0xFFF87171),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),

          // Action Button if not ready
          if (!isReady)
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: Text(
                actionText,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
