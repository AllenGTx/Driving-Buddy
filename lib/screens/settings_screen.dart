import 'package:flutter/services.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_colors.dart';
import '../models/account_config.dart';
import '../services/alert_config.dart';
import '../services/firebase_service.dart';
import '../services/sos_service.dart';
import '../routes/app_routes.dart';

// ============================================================================
// SETTINGS SCREEN (Akun, Audio Alarm & Pengaturan — Luxury GT)
// ============================================================================

typedef SettingsScreen = AccountSettingsScreen;

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _sosController1 = TextEditingController();
  final _sosController2 = TextEditingController();
  final _sosController3 = TextEditingController();
  bool _isSavingSos = false;
  bool _isSaving = false;
  bool _isLoggedIn = false;

  // --- Alert Settings State ---
  AlertAudioType _selectedAudioType = AlertAudioType.defaultSiren;
  String _audioDisplayName = 'Sirene Darurat (Bawaan)';
  String? _customAudioPath;
  final AudioPlayer _previewPlayer = AudioPlayer();
  bool _isPlayingPreview = false;

  AlertImageMode _selectedImageMode = AlertImageMode.none;
  String? _customImagePath;

  // --- Toggle Fitur Postur Kepala ---
  bool _enableHeadTilt = true;
  bool _enableHeadBob = true;

  // Foto Profil (Firebase Storage & Local Cached)
  String? _userPhotoUrl;
  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadAlertSettings();
  }

  Future<void> _loadAlertSettings() async {
    final audioType = await AlertConfig.getAudioType();
    final audioName = await AlertConfig.getAudioDisplayName();
    final customAudio = await AlertConfig.getCustomAudioPath();
    final imageMode = await AlertConfig.getImageMode();
    final customImage = await AlertConfig.getCustomImagePath();
    final headTilt = await AlertConfig.isHeadTiltEnabled();
    final headBob = await AlertConfig.isHeadBobEnabled();
    if (mounted) {
      setState(() {
        _selectedAudioType = audioType;
        _audioDisplayName = audioName;
        _customAudioPath = customAudio;
        _selectedImageMode = imageMode;
        _customImagePath = customImage;
        _enableHeadTilt = headTilt;
        _enableHeadBob = headBob;
      });
    }
  }

  Future<void> _togglePreviewAudio() async {
    if (_isPlayingPreview) {
      await _previewPlayer.stop();
      if (mounted) setState(() => _isPlayingPreview = false);
      return;
    }

    setState(() => _isPlayingPreview = true);
    try {
      if (_selectedAudioType == AlertAudioType.customFile &&
          _customAudioPath != null &&
          File(_customAudioPath!).existsSync()) {
        await _previewPlayer.play(DeviceFileSource(_customAudioPath!));
      } else if (_selectedAudioType == AlertAudioType.loudBeep) {
        await _previewPlayer.play(AssetSource('sounds/beep.wav'));
      } else if (_selectedAudioType == AlertAudioType.buzzer) {
        await _previewPlayer.play(AssetSource('sounds/buzzer.wav'));
      } else {
        try {
          await _previewPlayer.play(AssetSource('audio/alarm.mp3'));
        } catch (_) {
          await _previewPlayer.play(AssetSource('sounds/alarm.mp3'));
        }
      }

      // Otomatis stop setelah 4 detik
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && _isPlayingPreview) {
          _previewPlayer.stop();
          setState(() => _isPlayingPreview = false);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _isPlayingPreview = false);
    }
  }

  Future<void> _selectAudioPreset(AlertAudioType type) async {
    if (_isPlayingPreview) await _previewPlayer.stop();
    await AlertConfig.setAudioPreset(type);
    await _loadAlertSettings();
  }

  Future<void> _pickCustomAudio() async {
    const platform = MethodChannel('com.drivingbuddy/audio_picker');
    try {
      final result = await platform.invokeMethod<Map<dynamic, dynamic>>('pickAudio');
      if (result != null && result['path'] != null) {
        final filePath = result['path'] as String;
        final fileName = (result['name'] as String?) ?? 'Audio Kustom';

        if (_isPlayingPreview) await _previewPlayer.stop();
        await AlertConfig.setCustomAudio(filePath, fileName);
        await _loadAlertSettings();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Suara alarm berhasil diganti: $fileName'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memilih audio: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _pickCustomImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        await AlertConfig.setImageMode(AlertImageMode.custom,
            customPath: picked.path);
        await _loadAlertSettings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Gambar alert berhasil diperbarui'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memilih gambar: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _removeAlertImage() async {
    await AlertConfig.removeCustomImage();
    await _loadAlertSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gambar kustom dihapus (Kembali ke Ikon Standar)'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _loadProfile() async {
    if (AuthService.isLoggedIn) {
      final user = AuthService.currentUser;
      final name = await AuthService.getUserName();
      final email = user?.email ?? '';
      final profile = await AuthService.getUserProfile();
      final firestorePhoto = profile?['photoUrl'] as String?;
      final cachedPhoto = await AccountConfig.getPhotoUrl(userEmail: email);
      final photo = (firestorePhoto != null && firestorePhoto.isNotEmpty)
          ? firestorePhoto
          : ((user?.photoURL != null && user!.photoURL!.isNotEmpty)
              ? user.photoURL
              : cachedPhoto);

      if (photo != null && photo.isNotEmpty) {
        await AccountConfig.setPhotoUrl(photo, userEmail: email);
      } else {
        AccountConfig.photoNotifier.value = null;
      }

      if (mounted) {
        final sosPhones = await SosService.getSosPhoneList(userEmail: email);
        setState(() {
          _nameController.text = name;
          _emailController.text = email;
          _sosController1.text = sosPhones[0];
          _sosController2.text = sosPhones[1];
          _sosController3.text = sosPhones[2];
          _userPhotoUrl = photo;
          _isLoggedIn = true;
        });
      }
    } else {
      final profile = await AccountConfig.getProfile();
      if (mounted) {
        final offEmail = profile['email'] ?? '';
        final sosPhones = await SosService.getSosPhoneList(userEmail: offEmail);
        setState(() {
          _nameController.text = profile['name'] ?? '';
          _emailController.text = offEmail;
          _sosController1.text = sosPhones[0];
          _sosController2.text = sosPhones[1];
          _sosController3.text = sosPhones[2];
          _userPhotoUrl = profile['photoUrl']?.isNotEmpty == true ? profile['photoUrl'] : null;
          _isLoggedIn =
              _nameController.text.isNotEmpty || _emailController.text.isNotEmpty;
        });
      }
    }
  }

  @override
  void dispose() {
    _previewPlayer.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _sosController1.dispose();
    _sosController2.dispose();
    _sosController3.dispose();
    super.dispose();
  }


  Future<void> _pickAndUploadPhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;

      setState(() => _isUploadingPhoto = true);
      final file = File(picked.path);

      // Upload ke Firebase Storage & update Firestore
      final downloadUrl = await AuthService.uploadProfileImage(file);
      final finalUrl = downloadUrl ?? picked.path;

      // Simpan juga ke local SharedPreferences agar persisten saat restart/offline untuk user ini
      final currentUserEmail = AuthService.currentUser?.email;
      await AccountConfig.setPhotoUrl(finalUrl, userEmail: currentUserEmail);

      if (mounted) {
        setState(() {
          _userPhotoUrl = finalUrl;
          _isUploadingPhoto = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Foto profil berhasil diperbarui & disimpan di Firebase!'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengunggah foto: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    setState(() => _isSaving = true);
    await AccountConfig.saveProfile(name, email);
    if (AuthService.isLoggedIn && name.isNotEmpty) {
      try {
        await AuthService.updateDisplayName(name);
      } catch (e) {
        debugPrint('AuthService updateDisplayName error: ');
      }
    }
    await SosService.saveSosPhoneList([
      _sosController1.text,
      _sosController2.text,
      _sosController3.text,
    ]);
    setState(() {
      _isSaving = false;
      _isLoggedIn = name.isNotEmpty || email.isNotEmpty;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Profil & Kontak SOS tersimpan'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _signOut() async {
    if (AuthService.isLoggedIn) {
      await AccountConfig.clearProfile();
      await AuthService.logout();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.login,
          (route) => false,
        );
      }
    } else {
      await AccountConfig.clearProfile();
      _nameController.clear();
      _emailController.clear();
      setState(() => _isLoggedIn = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Berhasil keluar'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          // 1. HERO COVER ROAD BANNER DARI ATAS HINGGA TEPAT DI ATAS NAMA PENGEMUDI
          _buildHeroProfileHeader(),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                      const Text(
                        'Nama Pengemudi',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildTextField(
                        controller: _nameController,
                        hint: 'Masukkan nama kamu',
                        icon: Icons.person_rounded,
                      ),
                      const SizedBox(height: 16),

                      // Email (Read-Only agar tidak menimbulkan bug akun)
                      const Text(
                        'Email Terdaftar',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.email_rounded, color: Color(0xFF64748B), size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _emailController.text.isNotEmpty
                                    ? _emailController.text
                                    : 'email@contoh.com',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF334155),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock_rounded, size: 11, color: Color(0xFF64748B)),
                                  SizedBox(width: 3),
                                  Text(
                                    'Terkunci',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // FITUR DARURAT SOS (WHATSAPP)
                      _buildSosEmergencyCard(),
                      const SizedBox(height: 18),

                      // Simpan Profil Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveProfile,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_rounded, size: 18),
                          label: Text(_isSaving ? 'Menyimpan...' : 'Simpan Profil & Kontak SOS'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE57A38),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Divider(color: Color(0xFFFED7AA)),
                const SizedBox(height: 20),

                // Pengaturan Deteksi Postur Kepala (Head Tilt & Head Bob)
                _buildPostureSettingsSection(),
                const SizedBox(height: 28),
                const Divider(color: Color(0xFFFED7AA)),
                const SizedBox(height: 20),

                // Kustomisasi Alert & Alarm
                _buildAlertSettingsSection(),
                const SizedBox(height: 28),
                const Divider(color: Color(0xFFFED7AA)),
                const SizedBox(height: 20),

                const Text(
                  'Informasi Sistem',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 12),
                _buildInfoRow(Icons.security_rounded, 'Privasi',
                    'Kamera diproses lokal 100%, frame video tidak dikirim'),
                const SizedBox(height: 8),
                _buildInfoRow(Icons.info_outline_rounded, 'Versi',
                    'v1.0.0'),
                const SizedBox(height: 24),
                if (_isLoggedIn) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout_rounded,
                          size: 18, color: Color(0xFFD94126)),
                      label: const Text(
                        'Keluar dari Akun',
                        style: TextStyle(color: Color(0xFFD94126), fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFD94126)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7AA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Color(0xFF0F172A),
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: Colors.grey.shade400,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Icon(icon, color: const Color(0xFFE57A38)),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFEDD5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFFE57A38)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Kustomisasi Peringatan (Alert & Alarm)',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Atur nada suara alarm bawaan dan gambar yang ditampilkan saat bahaya',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 14),

        // ── 1. SUARA ALARM CARD ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFFFFF), Color(0xFFFFFBF8)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFED7AA)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE57A38).withOpacity(0.04),
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
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                    ),
                    child: const Icon(Icons.volume_up_rounded,
                        color: Color(0xFFE57A38), size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Suara Alarm Keselamatan',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'Bawaan: Sirene Darurat (bisa diubah sesuai selera)',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildAudioOptionTile(
                title: 'Sirene Darurat (Bawaan)',
                subtitle: 'Suara sirene alarm standar darurat',
                isSelected: _selectedAudioType == AlertAudioType.defaultSiren,
                onTap: () => _selectAudioPreset(AlertAudioType.defaultSiren),
              ),
              const SizedBox(height: 6),
              _buildAudioOptionTile(
                title: 'Beep Peringatan Cepat',
                subtitle: 'Nada beep berulang frekuensi tinggi (1050 Hz)',
                isSelected: _selectedAudioType == AlertAudioType.loudBeep,
                onTap: () => _selectAudioPreset(AlertAudioType.loudBeep),
              ),
              const SizedBox(height: 6),
              _buildAudioOptionTile(
                title: 'Klakson / Buzzer Peringatan',
                subtitle: 'Suara buzzer ganda kendaraan darurat',
                isSelected: _selectedAudioType == AlertAudioType.buzzer,
                onTap: () => _selectAudioPreset(AlertAudioType.buzzer),
              ),
              const SizedBox(height: 6),
              _buildAudioOptionTile(
                title: _selectedAudioType == AlertAudioType.customFile
                    ? 'File Kustom: $_audioDisplayName'
                    : 'Pilih Audio dari File HP...',
                subtitle: _selectedAudioType == AlertAudioType.customFile
                    ? 'Audio kustom tersimpan dari memori HP'
                    : 'Cari atau masukkan path file audio MP3/WAV',
                isSelected: _selectedAudioType == AlertAudioType.customFile,
                onTap: _pickCustomAudio,
                trailingIcon: Icons.folder_open_rounded,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _togglePreviewAudio,
                      icon: Icon(
                        _isPlayingPreview
                            ? Icons.stop_circle_rounded
                            : Icons.play_circle_fill_rounded,
                        size: 18,
                        color: _isPlayingPreview
                            ? const Color(0xFFD94126)
                            : const Color(0xFFE57A38),
                      ),
                      label: Text(
                        _isPlayingPreview ? 'Hentikan Contoh' : 'Tes Bunyi Alarm',
                        style: TextStyle(
                          color: _isPlayingPreview
                              ? const Color(0xFFD94126)
                              : const Color(0xFFE57A38),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: _isPlayingPreview
                              ? const Color(0xFFD94126)
                              : const Color(0xFFE57A38),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  if (_selectedAudioType != AlertAudioType.defaultSiren) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Kembalikan ke sirene bawaan',
                      onPressed: () =>
                          _selectAudioPreset(AlertAudioType.defaultSiren),
                      icon: const Icon(Icons.refresh_rounded,
                          color: Color(0xFFE57A38)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

       
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFFFFF), Color(0xFFFFFBF8)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFED7AA)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE57A38).withOpacity(0.04),
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
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                    ),
                    child: const Icon(Icons.image_rounded,
                        color: Color(0xFFE57A38), size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gambar Peringatan Visual',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'Bawaan: Ikon Bahaya Standar',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Image Preview Area
              Center(
                child: Container(
                  height: 130,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFFEDD5)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildImagePreviewWidget(),
                ),
              ),

              const SizedBox(height: 14),

              // Action buttons for Image
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _pickCustomImage,
                      icon: const Icon(Icons.photo_library_rounded, size: 16),
                      label: const Text(
                        'Pilih Gambar Kustom',
                        style:
                            TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        backgroundColor: const Color(0xFFE57A38),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  if (_selectedImageMode == AlertImageMode.custom) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _removeAlertImage,
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 16, color: Color(0xFFD94126)),
                      label: const Text('Hapus',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFFD94126))),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFD94126)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 11),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImagePreviewWidget() {
    if (_selectedImageMode == AlertImageMode.custom &&
        _customImagePath != null &&
        File(_customImagePath!).existsSync()) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(_customImagePath!), fit: BoxFit.cover),
          Positioned(
            bottom: 6,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Gambar Kustom Aktif',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      );
    }

    // Default: Clean Safety Icon (No meme)
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.shield_outlined, size: 40, color: Color(0xFFE57A38)),
        SizedBox(height: 6),
        Text(
          'Ikon Peringatan Standar Aktif',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        Text(
          'Menampilkan animasi bahaya darurat',
          style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _buildAudioOptionTile({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
    IconData? trailingIcon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF7ED) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFFFED7AA) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 18,
              color: isSelected ? const Color(0xFFE57A38) : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                      color:
                          isSelected ? const Color(0xFF0F172A) : const Color(0xFF475569),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isSelected
                          ? const Color(0xFFC25E21)
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
            if (trailingIcon != null)
              Icon(trailingIcon, size: 18, color: const Color(0xFFE57A38)),
          ],
        ),
      ),
    );
  }

  Widget _buildPostureSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Deteksi Postur Kepala (AI Advanced)',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Fitur pelengkap mata: pantau kemiringan dan sentakan kepala saat tertidur',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 14),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFFFFF), Color(0xFFFFFBF8)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFED7AA)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE57A38).withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // 1. Head Tilt Switch
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                    ),
                    child: const Icon(
                      Icons.screen_rotation_rounded,
                      color: Color(0xFFE57A38),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Deteksi Head Tilt (Kemiringan Kepala)',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Memicu alarm darurat saat kepala miring > 18° selama lebih dari 1.8 detik (indikasi tertidur ke samping).',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: _enableHeadTilt,
                    activeColor: const Color(0xFFE57A38),
                    onChanged: (val) async {
                      setState(() => _enableHeadTilt = val);
                      await AlertConfig.setHeadTiltEnabled(val);
                    },
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: Color(0xFFFFEDD5), height: 1),
              ),

              // 2. Head Bob Switch
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                    ),
                    child: const Icon(
                      Icons.airline_seat_recline_extra_rounded,
                      color: Color(0xFFE57A38),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Deteksi Head Bob (Sentakan Menunduk)',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Memicu alarm saat terdeteksi 3x sentakan kepala jatuh mendadak dalam 5 menit (gejala microsleep berat).',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: _enableHeadBob,
                    activeColor: const Color(0xFFE57A38),
                    onChanged: (val) async {
                      setState(() => _enableHeadBob = val);
                      await AlertConfig.setHeadBobEnabled(val);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

    Widget _buildAvatarFallback() {
    return Center(
      child: Text(
        _nameController.text.isNotEmpty ? _nameController.text[0].toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }

  /// Cover Road Banner memanjang dari paling atas (termasuk transparent AppBar)
  /// hingga tepat di atas 'Nama Pengemudi', diakhiri garis oranye pembatas.
  Widget _buildHeroProfileHeader() {
    final topPadding = MediaQuery.paddingOf(context).top;

    return Column(
      children: [
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/profile_road_bg.jpg'),
              fit: BoxFit.cover,
            ),
          ),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(16, topPadding + 6, 16, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.40),
                  Colors.black.withValues(alpha: 0.80),
                ],
              ),
            ),
            child: Column(
              children: [
                // Top Transparent Custom Navigation Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                    const Text(
                      'Pengaturan',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.5,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 2)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 36), // Balance the back button
                  ],
                ),
                const SizedBox(height: 16),

                // Avatar Photo
                GestureDetector(
                  onTap: _isUploadingPhoto ? null : _pickAndUploadPhoto,
                  child: Stack(
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE57A38), Color(0xFFC25E21)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: _isUploadingPhoto
                              ? const Center(
                                  child: SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              : (_userPhotoUrl != null && _userPhotoUrl!.isNotEmpty)
                                  ? (_userPhotoUrl!.startsWith('http')
                                      ? Image.network(
                                          _userPhotoUrl!,
                                          fit: BoxFit.cover,
                                          width: 88,
                                          height: 88,
                                          errorBuilder: (_, __, ___) => _buildAvatarFallback(),
                                        )
                                      : Image.file(
                                          File(_userPhotoUrl!),
                                          fit: BoxFit.cover,
                                          width: 88,
                                          height: 88,
                                          errorBuilder: (_, __, ___) => _buildAvatarFallback(),
                                        ))
                                  : _buildAvatarFallback(),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE57A38),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Driver Name in Hero Banner
                Text(
                  _isLoggedIn
                      ? (_nameController.text.isNotEmpty ? _nameController.text : 'Pengemudi')
                      : 'Tamu / Offline',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.3,
                    shadows: [
                      Shadow(color: Colors.black87, blurRadius: 8, offset: Offset(0, 2)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // Connected Account Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isLoggedIn
                        ? const Color(0xFF064E3B).withValues(alpha: 0.85)
                        : Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isLoggedIn ? const Color(0xFF34D399) : Colors.white24,
                    ),
                  ),
                  child: Text(
                    _isLoggedIn ? '● Akun Terhubung' : '○ Mode Tamu (Offline)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _isLoggedIn ? const Color(0xFFA7F3D0) : Colors.white70,
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // AI Info Card diletakkan di dalam background hero pemandangan jalan
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14100E).withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF564339)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.psychology_rounded,
                          color: Color(0xFFE57A38), size: 22),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Sensor AI Face Mesh aktif real-time. '
                          'Koneksi internet digunakan untuk telemetri GPS, sinkronisasi riwayat sesi, dan darurat SOS.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFFEAE0DD),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // GARIS OREN PEMBATAS TEGAS TEPAT DI ATAS NAMA PENGEMUDI
        Container(
          height: 3.5,
          width: double.infinity,
          color: const Color(0xFFE57A38),
        ),
      ],
    );
  }

  Widget _buildSosEmergencyCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFED7AA)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE57A38).withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: const Icon(Icons.emergency_rounded, color: Color(0xFFD94126), size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kontak Darurat SOS (WhatsApp)',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Kirim GPS lokasi & sinyal darurat otomatis',
                      style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: const Text(
                  'MAKS 3 KONTAK',
                  style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: Color(0xFF059669)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Jika alarm kantuk berbunyi selama 1 menit penuh tanpa respon tombol "Saya Sudah Bangun", sistem otomatis mengirimkan pesan darurat beserta tautan titik peta GPS ke seluruh kontak darurat di bawah ini.',
            style: TextStyle(fontSize: 11, color: Color(0xFF475569), height: 1.4),
          ),
          const SizedBox(height: 14),

          // Kontak 1 (Utama)
          _buildPhoneInputRow('Kontak 1 (Utama)', _sosController1, hint: 'Contoh: 0895321647135'),
          const SizedBox(height: 10),

          // Kontak 2 (Cadangan)
          _buildPhoneInputRow('Kontak 2 (Cadangan Opsional)', _sosController2, hint: 'Contoh: 081234567890'),
          const SizedBox(height: 10),

          // Kontak 3 (Cadangan)
          _buildPhoneInputRow('Kontak 3 (Cadangan Opsional)', _sosController3, hint: 'Contoh: 089876543210'),
          const SizedBox(height: 14),

          // Single Clean Full-Width Button (Tidak Nabrak Box)
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _isSavingSos ? null : _saveSosContacts,
              icon: _isSavingSos
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: const Text(
                'Simpan Kontak Darurat SOS',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE57A38),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneInputRow(String label, TextEditingController controller, {required String hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.phone_rounded, color: Color(0xFF25D366), size: 18),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE57A38), width: 1.6),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveSosContacts() async {
    setState(() => _isSavingSos = true);
    await SosService.saveSosPhoneList([
      _sosController1.text,
      _sosController2.text,
      _sosController3.text,
    ]);
    setState(() => _isSavingSos = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Kontak darurat SOS WhatsApp berhasil disimpan!'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
