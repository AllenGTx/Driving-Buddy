import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// LANGUAGE SERVICE (Bilingual Engine: Bahasa Indonesia & English)
// ============================================================================

enum AppLanguage { id, en }

class LanguageService extends ChangeNotifier {
  LanguageService._internal();
  static final LanguageService instance = LanguageService._internal();

  static const String _prefKey = 'app_language';
  AppLanguage _currentLanguage = AppLanguage.id;

  AppLanguage get currentLanguage => _currentLanguage;
  bool get isIndonesian => _currentLanguage == AppLanguage.id;
  bool get isEnglish => _currentLanguage == AppLanguage.en;

  AppStrings get s => isIndonesian ? _idStrings : _enStrings;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null) {
        _currentLanguage = AppLanguage.values.firstWhere(
          (e) => e.name == saved,
          orElse: () => AppLanguage.id,
        );
      }
    } catch (e) {
      debugPrint('LanguageService init error: $e');
    }
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (_currentLanguage == language) return;
    _currentLanguage = language;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, language.name);
    } catch (e) {
      debugPrint('LanguageService save error: $e');
    }
  }

  /// Format durasi dengan satuan bahasa yang aktif:
  /// ID: 1j 20m 30d (atau 45d, 12m)
  /// EN: 1h 20m 30s (atau 45s, 12m)
  String formatDuration(int totalSeconds) {
    if (totalSeconds < 60) {
      return '$totalSeconds${s.secShort}';
    }
    final minutes = totalSeconds ~/ 60;
    final remainingSecs = totalSeconds % 60;
    if (minutes < 60) {
      return remainingSecs > 0
          ? '$minutes${s.minShort} $remainingSecs${s.secShort}'
          : '$minutes${s.minShort}';
    }
    final hours = minutes ~/ 60;
    final remainingMins = minutes % 60;
    return remainingMins > 0
        ? '$hours${s.hourShort} $remainingMins${s.minShort}'
        : '$hours${s.hourShort}';
  }
}

// ============================================================================
// ABSTRACT STRINGS CONTRACT
// ============================================================================

abstract class AppStrings {
  // Navigation
  String get navHome;
  String get navHistory;
  String get navDriveMode;

  // Units & Time
  String get secShort;
  String get minShort;
  String get hourShort;
  String get speedUnit;
  String get distUnit;

  // Common Actions
  String get close;
  String get back;
  String get save;
  String get cancel;
  String get delete;
  String get today;
  String get offline;
  String get online;
  String get preview;

  // Welcome Screen
  String get welcomeTitle;
  String get welcomeDesc;
  String get continueBtn;

  // Auth Screen
  String get signIn;
  String get signUp;
  String get tabSignIn;
  String get tabSignUp;
  String get emailLabel;
  String get passwordLabel;
  String get confirmPasswordLabel;
  String get fullNameLabel;
  String get fullNameHint;
  String get forgotPassword;
  String get resetPasswordTitle;
  String get resetPasswordDesc;
  String get sendLink;
  String get btnSignIn;
  String get btnSignUp;
  String get orContinueWith;
  String get googleSignIn;
  String get dontHaveAccount;
  String get registerNow;
  String get alreadyHaveAccount;
  String get signInNow;
  String get passwordReqText;
  String get emailEmptyErr;
  String get passwordEmptyErr;
  String get nameEmptyErr;
  String get passConfirmMismatchErr;

  // Telemetry & Metrics
  String get avgSpeed;
  String get topSpeed;
  String get duration;
  String get distance;
  String get travelRoute;
  String get driverAchievement;
  String get alertDriverTag;
  String get zeroFatigueTag;
  String get stayAlertTag;
  String get needRestTag;
  String get statusVerySafe;
  String get statusSafe;
  String get statusCaution;
  String get statusRest;
  String get microsleep;
  String get drowsy;
  String get yawn;
  String get detected;
  String get times;
  String get shareDrivingCard;
  String get drivingCardTitle;
  String get viewAchievementCard;

  // History Screen
  String get historyTitle;
  String get cumulativeTelemetry;
  String get driverTrip;
  String get totalTime;
  String get avgScore;
  String get totalSessions;
  String get tripSessionsList;
  String get sessionsCount;
  String get score;
  String get emptyHistoryTitle;
  String get emptyHistoryDesc;
  String get deleteAllConfirm;

  // Home / Cockpit Screen
  String get goodMorning;
  String get goodAfternoon;
  String get goodEvening;
  String get goodNight;
  String get cabinSensor;
  String get sensorReady;
  String get sensorActive;
  String get startTrip;
  String get telemetryRealtime;
  String get avgAlertnessScore;
  String get recentHistory;
  String get viewAll;
  String get historicalAverages;
  String get cameraStandby;

  // Monitor / Active Drive
  String get drivingTitle;
  String get nightGlowTitle;
  String get nightGlowDesc;
  String get faceDetected;
  String get faceNotDetected;
  String get earLabel;
  String get earLow;
  String get earNormal;
  String get blinkRate;
  String get yawnDetect;
  String get headTilt;
  String get headBob;
  String get snoozeAlert;
  String get finishTrip;
  String get finishTripConfirm;
  String get perMinute;

  // Settings Screen
  String get settingsTitle;
  String get appLanguage;
  String get appLanguageDesc;
  String get languageIndonesian;
  String get languageEnglish;
  String get themeAndDisplay;
  String get themeDesc;
  String get themeSystem;
  String get themeSystemDesc;
  String get themeAutoTime;
  String get themeAutoTimeDesc;
  String get themeLight;
  String get themeLightDesc;
  String get themeDark;
  String get themeDarkDesc;
  String get headPostureDetection;
  String get headPostureDesc;
  String get headTiltSetting;
  String get headBobSetting;
  String get alertSound;
  String get alertSoundDesc;
  String get systemInfo;
  String get privacy;
  String get privacyDesc;
  String get version;
  String get logout;
  String get guestMode;
  String get tapToChangePhoto;
  String get photoUpdatedSuccess;
  String get lightBadge;
  String get darkBadge;
}

// ============================================================================
// INDONESIAN STRINGS
// ============================================================================

class _IndonesianStrings implements AppStrings {
  const _IndonesianStrings();

  @override String get navHome => 'Beranda';
  @override String get navHistory => 'Riwayat';
  @override String get navDriveMode => 'Mode Berkendara';

  @override String get secShort => 'd';
  @override String get minShort => 'm';
  @override String get hourShort => 'j';
  @override String get speedUnit => 'km/j';
  @override String get distUnit => 'km';

  @override String get close => 'Tutup';
  @override String get back => 'Kembali';
  @override String get save => 'Simpan';
  @override String get cancel => 'Batal';
  @override String get delete => 'Hapus';
  @override String get today => 'Hari ini';
  @override String get offline => 'OFFLINE';
  @override String get online => 'ONLINE';
  @override String get preview => 'PREVIEW';

  @override String get welcomeTitle => 'Selamat Datang';
  @override String get welcomeDesc =>
      'Asisten AI cerdas untuk memantau keselamatan & kewaspadaan berkendara Anda di setiap perjalanan.';
  @override String get continueBtn => 'Lanjutkan';

  @override String get signIn => 'Masuk';
  @override String get signUp => 'Daftar Akun';
  @override String get tabSignIn => 'Masuk';
  @override String get tabSignUp => 'Daftar Baru';
  @override String get emailLabel => 'Email Pengemudi';
  @override String get passwordLabel => 'Kata Sandi';
  @override String get confirmPasswordLabel => 'Konfirmasi Kata Sandi';
  @override String get fullNameLabel => 'Nama Lengkap';
  @override String get fullNameHint => 'Contoh: Adrian Hartono';
  @override String get forgotPassword => 'Lupa Kata Sandi?';
  @override String get resetPasswordTitle => 'Reset Kata Sandi';
  @override String get resetPasswordDesc =>
      'Masukkan email terdaftar Anda untuk menerima tautan pemulihan kata sandi.';
  @override String get sendLink => 'Kirim Link';
  @override String get btnSignIn => 'Masuk ke Cockpit';
  @override String get btnSignUp => 'Buat Akun Pengemudi';
  @override String get orContinueWith => 'atau masuk dengan';
  @override String get googleSignIn => 'Lanjutkan dengan Google';
  @override String get dontHaveAccount => 'Belum punya akun? ';
  @override String get registerNow => 'Daftar sekarang';
  @override String get alreadyHaveAccount => 'Sudah punya akun? ';
  @override String get signInNow => 'Masuk';
  @override String get passwordReqText =>
      '* Minimal 8 karakter, wajib kombinasi huruf besar, huruf kecil, angka, dan simbol unik';
  @override String get emailEmptyErr => 'Email tidak boleh kosong.';
  @override String get passwordEmptyErr => 'Kata sandi tidak boleh kosong.';
  @override String get nameEmptyErr => 'Nama lengkap tidak boleh kosong.';
  @override String get passConfirmMismatchErr => 'Konfirmasi kata sandi tidak cocok.';

  // Metrics (Khusus: avg_speed -> Laju Rata², top_speed -> Laju Maks)
  @override String get avgSpeed => 'Laju Rata²';
  @override String get topSpeed => 'Laju Maks';
  @override String get duration => 'Durasi';
  @override String get distance => 'Jarak';
  @override String get travelRoute => 'RUTE PERJALANAN';
  @override String get driverAchievement => 'PENCAPAIAN PENGEMUDI';
  @override String get alertDriverTag => '#PengemudiWaspada';
  @override String get zeroFatigueTag => '#ZeroFatigue';
  @override String get stayAlertTag => '#TerusWaspada';
  @override String get needRestTag => '#ButuhIstirahat';
  @override String get statusVerySafe => 'SANGAT AMAN';
  @override String get statusSafe => 'AMAN';
  @override String get statusCaution => 'WASPADA';
  @override String get statusRest => 'ISTIRAHAT';
  @override String get microsleep => 'Microsleep';
  @override String get drowsy => 'Kantuk';
  @override String get yawn => 'Menguap';
  @override String get detected => 'Terdeteksi';
  @override String get times => 'kali';
  @override String get shareDrivingCard => 'Bagikan Kartu Berkendara';
  @override String get drivingCardTitle => 'Kartu Berkendara';
  @override String get viewAchievementCard => 'Lihat Kartu Pencapaian';

  @override String get historyTitle => 'Riwayat Perjalanan';
  @override String get cumulativeTelemetry => 'TELEMETRI KUMULATIF';
  @override String get driverTrip => 'Perjalanan';
  @override String get totalTime => 'TOTAL WAKTU';
  @override String get avgScore => 'RATA-RATA SKOR';
  @override String get totalSessions => 'TOTAL SESI';
  @override String get tripSessionsList => 'Daftar Sesi Perjalanan';
  @override String get sessionsCount => 'Sesi';
  @override String get score => 'SKOR';
  @override String get emptyHistoryTitle => 'Belum Ada Riwayat Perjalanan';
  @override String get emptyHistoryDesc =>
      'Mulai perjalanan berkendara pertama Anda dari tombol di tengah bawah.';
  @override String get deleteAllConfirm => 'Hapus semua riwayat sesi perjalanan?';

  @override String get goodMorning => 'Selamat Pagi';
  @override String get goodAfternoon => 'Selamat Siang';
  @override String get goodEvening => 'Selamat Sore';
  @override String get goodNight => 'Selamat Malam';
  @override String get cabinSensor => 'Sensor AI Kabin';
  @override String get sensorReady => 'SENSOR SIAGA';
  @override String get sensorActive => 'SENSOR AKTIF';
  @override String get startTrip => 'MULAI PERJALANAN';
  @override String get telemetryRealtime => 'ANALISIS TELEMETRI REALTIME';
  @override String get avgAlertnessScore => 'Skor Kewaspadaan Rata-rata';
  @override String get recentHistory => 'Riwayat Terakhir';
  @override String get viewAll => 'Lihat Semua';
  @override String get historicalAverages => 'RATA-RATA RIWAYAT BERKENDARA';
  @override String get cameraStandby => 'Kamera siaga • Ketuk untuk perbesar';

  @override String get drivingTitle => 'Berkendara';
  @override String get nightGlowTitle => 'Penerangan Wajah Malam / Night Glow';
  @override String get nightGlowDesc =>
      'Bantu deteksi sensor AI di kondisi minim cahaya';
  @override String get faceDetected => 'Wajah Terdeteksi';
  @override String get faceNotDetected => 'Wajah Tidak Terdeteksi';
  @override String get earLabel => 'EYE ASPECT RATIO (EAR)';
  @override String get earLow => 'Rendah';
  @override String get earNormal => 'Normal';
  @override String get blinkRate => 'FREKUENSI KEDIP';
  @override String get yawnDetect => 'DETEKSI MENGUAP';
  @override String get headTilt => 'KEMIRINGAN KEPALA';
  @override String get headBob => 'KANTUK KEPALA';
  @override String get snoozeAlert => 'Tunda Peringatan';
  @override String get finishTrip => 'Selesaikan Perjalanan';
  @override String get finishTripConfirm =>
      'Selesaikan perjalanan dan simpan data telemetri?';
  @override String get perMinute => '/ mnt';

  @override String get settingsTitle => 'Pengaturan Akun';
  @override String get appLanguage => 'Bahasa Aplikasi';
  @override String get appLanguageDesc =>
      'Pilih bahasa tampilan untuk seluruh antarmuka aplikasi';
  @override String get languageIndonesian => 'Bahasa Indonesia';
  @override String get languageEnglish => 'English (Bahasa Inggris)';
  @override String get themeAndDisplay => 'Tampilan & Tema Kabin';
  @override String get themeDesc =>
      'Pilih preferensi tema antarmuka atau biarkan otomatis beralih mengikuti waktu';
  @override String get themeSystem => 'Ikuti Sistem HP';
  @override String get themeSystemDesc =>
      'Otomatis berganti terang atau gelap mengikuti tema perangkat HP Anda.';
  @override String get themeAutoTime => 'Otomatis Berdasarkan Waktu';
  @override String get themeAutoTimeDesc =>
      'Mode gelap aktif otomatis pukul 16:00 – 04:00 untuk kenyamanan berkendara malam.';
  @override String get themeLight => 'Selalu Mode Terang';
  @override String get themeLightDesc =>
      'Tampilan cerah dengan kontras tinggi setiap saat.';
  @override String get themeDark => 'Selalu Abu-abu Gelap (Obsidian)';
  @override String get themeDarkDesc =>
      'Tampilan gelap mewah dan hemat baterai setiap saat.';
  @override String get headPostureDetection => 'Deteksi Postur Kepala';
  @override String get headPostureDesc =>
      'Konfigurasi sensitivitas deteksi kemiringan dan kantuk kepala';
  @override String get headTiltSetting => 'Deteksi Kepala Miring (Head Tilt)';
  @override String get headBobSetting => 'Deteksi Kepala Mengangguk (Head Bob)';
  @override String get alertSound => 'Kustomisasi Alert & Alarm';
  @override String get alertSoundDesc =>
      'Atur suara peringatan dan volume audio kabin';
  @override String get systemInfo => 'Informasi Sistem';
  @override String get privacy => 'Privasi';
  @override String get privacyDesc =>
      'Kamera diproses lokal 100%, frame video tidak dikirim';
  @override String get version => 'Versi';
  @override String get logout => 'Keluar dari Akun';
  @override String get guestMode => 'Pengemudi Tamu';
  @override String get tapToChangePhoto => 'Ketuk untuk mengganti foto profil';
  @override String get photoUpdatedSuccess => 'Foto profil berhasil diperbarui!';
  @override String get lightBadge => 'Terang';
  @override String get darkBadge => 'Gelap';
}

// ============================================================================
// ENGLISH STRINGS
// ============================================================================

class _EnglishStrings implements AppStrings {
  const _EnglishStrings();

  @override String get navHome => 'Home';
  @override String get navHistory => 'History';
  @override String get navDriveMode => 'Drive Mode';

  @override String get secShort => 's';
  @override String get minShort => 'm';
  @override String get hourShort => 'h';
  @override String get speedUnit => 'km/h';
  @override String get distUnit => 'km';

  @override String get close => 'Close';
  @override String get back => 'Back';
  @override String get save => 'Save';
  @override String get cancel => 'Cancel';
  @override String get delete => 'Delete';
  @override String get today => 'Today';
  @override String get offline => 'OFFLINE';
  @override String get online => 'ONLINE';
  @override String get preview => 'PREVIEW';

  @override String get welcomeTitle => 'Welcome';
  @override String get welcomeDesc =>
      'Smart AI assistant to monitor driving alertness and road safety on every journey.';
  @override String get continueBtn => 'Continue';

  @override String get signIn => 'Sign In';
  @override String get signUp => 'Sign Up';
  @override String get tabSignIn => 'Sign In';
  @override String get tabSignUp => 'Sign Up';
  @override String get emailLabel => 'Driver Email';
  @override String get passwordLabel => 'Password';
  @override String get confirmPasswordLabel => 'Confirm Password';
  @override String get fullNameLabel => 'Full Name';
  @override String get fullNameHint => 'e.g. Adrian Hartono';
  @override String get forgotPassword => 'Forgot Password?';
  @override String get resetPasswordTitle => 'Reset Password';
  @override String get resetPasswordDesc =>
      'Enter your registered email to receive a password recovery link.';
  @override String get sendLink => 'Send Link';
  @override String get btnSignIn => 'Enter Cockpit';
  @override String get btnSignUp => 'Create Driver Account';
  @override String get orContinueWith => 'or continue with';
  @override String get googleSignIn => 'Continue with Google';
  @override String get dontHaveAccount => 'Don\'t have an account? ';
  @override String get registerNow => 'Sign up now';
  @override String get alreadyHaveAccount => 'Already have an account? ';
  @override String get signInNow => 'Sign In';
  @override String get passwordReqText =>
      '* Min. 8 characters, combination of uppercase, lowercase, numbers, and unique symbols';
  @override String get emailEmptyErr => 'Email cannot be empty.';
  @override String get passwordEmptyErr => 'Password cannot be empty.';
  @override String get nameEmptyErr => 'Full name cannot be empty.';
  @override String get passConfirmMismatchErr => 'Password confirmation does not match.';

  // Metrics (English)
  @override String get avgSpeed => 'Avg Speed';
  @override String get topSpeed => 'Top Speed';
  @override String get duration => 'Duration';
  @override String get distance => 'Distance';
  @override String get travelRoute => 'TRAVEL ROUTE';
  @override String get driverAchievement => 'DRIVER ACHIEVEMENT';
  @override String get alertDriverTag => '#AlertDriver';
  @override String get zeroFatigueTag => '#ZeroFatigue';
  @override String get stayAlertTag => '#StayAlert';
  @override String get needRestTag => '#NeedRest';
  @override String get statusVerySafe => 'VERY SAFE';
  @override String get statusSafe => 'SAFE';
  @override String get statusCaution => 'CAUTION';
  @override String get statusRest => 'REST';
  @override String get microsleep => 'Microsleep';
  @override String get drowsy => 'Drowsy';
  @override String get yawn => 'Yawn';
  @override String get detected => 'Detected';
  @override String get times => 'times';
  @override String get shareDrivingCard => 'Share Driving Card';
  @override String get drivingCardTitle => 'Driving Card';
  @override String get viewAchievementCard => 'View Achievement Card';

  @override String get historyTitle => 'Trip History';
  @override String get cumulativeTelemetry => 'CUMULATIVE TELEMETRY';
  @override String get driverTrip => 'Trip of';
  @override String get totalTime => 'TOTAL TIME';
  @override String get avgScore => 'AVG SCORE';
  @override String get totalSessions => 'TOTAL SESSIONS';
  @override String get tripSessionsList => 'Trip Sessions List';
  @override String get sessionsCount => 'Sessions';
  @override String get score => 'SCORE';
  @override String get emptyHistoryTitle => 'No Trip History Yet';
  @override String get emptyHistoryDesc =>
      'Start your first driving session using the center bottom button.';
  @override String get deleteAllConfirm => 'Delete all trip history sessions?';

  @override String get goodMorning => 'Good Morning';
  @override String get goodAfternoon => 'Good Afternoon';
  @override String get goodEvening => 'Good Evening';
  @override String get goodNight => 'Good Night';
  @override String get cabinSensor => 'Cabin AI Sensor';
  @override String get sensorReady => 'SENSOR READY';
  @override String get sensorActive => 'SENSOR ACTIVE';
  @override String get startTrip => 'START TRIP';
  @override String get telemetryRealtime => 'REALTIME TELEMETRY ANALYSIS';
  @override String get avgAlertnessScore => 'Average Alertness Score';
  @override String get recentHistory => 'Recent History';
  @override String get viewAll => 'View All';
  @override String get historicalAverages => 'HISTORICAL DRIVING AVERAGES';
  @override String get cameraStandby => 'Camera ready • Tap to expand';

  @override String get drivingTitle => 'Driving Mode';
  @override String get nightGlowTitle => 'Night Face Illumination / Night Glow';
  @override String get nightGlowDesc =>
      'Assist AI sensor detection in low-light conditions';
  @override String get faceDetected => 'Face Detected';
  @override String get faceNotDetected => 'No Face Detected';
  @override String get earLabel => 'EYE ASPECT RATIO (EAR)';
  @override String get earLow => 'Low';
  @override String get earNormal => 'Normal';
  @override String get blinkRate => 'BLINK RATE';
  @override String get yawnDetect => 'YAWN DETECT';
  @override String get headTilt => 'HEAD TILT';
  @override String get headBob => 'HEAD BOB';
  @override String get snoozeAlert => 'Snooze Alert';
  @override String get finishTrip => 'Finish Trip';
  @override String get finishTripConfirm =>
      'Finish journey and save telemetry data?';
  @override String get perMinute => '/ min';

  @override String get settingsTitle => 'Account Settings';
  @override String get appLanguage => 'App Language';
  @override String get appLanguageDesc =>
      'Select the display language for the entire user interface';
  @override String get languageIndonesian => 'Bahasa Indonesia (Indonesian)';
  @override String get languageEnglish => 'English';
  @override String get themeAndDisplay => 'Display & Cabin Theme';
  @override String get themeDesc =>
      'Choose interface theme preferences or auto-switch with time';
  @override String get themeSystem => 'Follow Device System';
  @override String get themeSystemDesc =>
      'Automatically switch light or dark following your device theme.';
  @override String get themeAutoTime => 'Automatic Based on Time';
  @override String get themeAutoTimeDesc =>
      'Dark mode turns on automatically from 16:00 – 04:00 for night driving.';
  @override String get themeLight => 'Always Light Mode';
  @override String get themeLightDesc =>
      'Bright display with high contrast at all times.';
  @override String get themeDark => 'Always Dark Mode (Obsidian)';
  @override String get themeDarkDesc =>
      'Luxury dark display that saves battery at all times.';
  @override String get headPostureDetection => 'Head Posture Detection';
  @override String get headPostureDesc =>
      'Configure head tilt and nod sensitivity parameters';
  @override String get headTiltSetting => 'Head Tilt Detection';
  @override String get headBobSetting => 'Head Nod / Bob Detection';
  @override String get alertSound => 'Alert & Alarm Customization';
  @override String get alertSoundDesc =>
      'Configure alert sounds and cabin audio volume';
  @override String get systemInfo => 'System Information';
  @override String get privacy => 'Privacy';
  @override String get privacyDesc =>
      'Camera processed 100% locally, video frames are never sent';
  @override String get version => 'Version';
  @override String get logout => 'Log Out';
  @override String get guestMode => 'Guest Driver';
  @override String get tapToChangePhoto => 'Tap to change profile picture';
  @override String get photoUpdatedSuccess => 'Profile picture successfully updated!';
  @override String get lightBadge => 'Light';
  @override String get darkBadge => 'Dark';
}

const AppStrings _idStrings = _IndonesianStrings();
const AppStrings _enStrings = _EnglishStrings();
