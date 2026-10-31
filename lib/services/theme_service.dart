import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opsi pilihan tema aplikasi.
enum AppThemeMode {
  /// Mengikuti pengaturan tema sistem HP user (Default user baru)
  system,

  /// Mengikuti waktu: 16:00 - 04:00 (Dark Gray), 04:00 - 16:00 (Light)
  autoTime,

  /// Selalu mode terang
  light,

  /// Selalu mode abu-abu gelap
  dark,
}

/// Service pengelola tema aplikasi DrivingBuddy.
/// Menyediakan dukungan mengikuti sistem HP secara bawaan,
/// pergantian otomatis jam lokal (16:00 - 04:00),
/// serta dukungan override manual (selalu terang / selalu abu-abu gelap).
class ThemeService extends ChangeNotifier with WidgetsBindingObserver {
  ThemeService._internal();
  static final ThemeService instance = ThemeService._internal();

  static const String _prefKey = 'app_theme_mode';

  AppThemeMode _currentMode = AppThemeMode.system;
  bool _lastIsDark = false;
  Timer? _ticker;
  bool _initialized = false;

  /// Mode tema yang sedang aktif dipilih user.
  AppThemeMode get currentMode => _currentMode;

  /// Evaluasi apakah tampilan saat ini harus mode gelap (abu-abu gelap).
  bool get isDarkMode {
    switch (_currentMode) {
      case AppThemeMode.system:
        final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
        return brightness == Brightness.dark;
      case AppThemeMode.light:
        return false;
      case AppThemeMode.dark:
        return true;
      case AppThemeMode.autoTime:
        return isNightTime();
    }
  }

  /// Label penjelasan status mode tema untuk UI pengaturan.
  String get modeDescription {
    switch (_currentMode) {
      case AppThemeMode.system:
        return 'Mengikuti Sistem HP (${isDarkMode ? "Aktif: Gelap" : "Aktif: Terang"})';
      case AppThemeMode.autoTime:
        return isDarkMode
            ? 'Otomatis Waktu (Aktif: Gelap 16:00–04:00)'
            : 'Otomatis Waktu (Aktif: Terang 04:00–16:00)';
      case AppThemeMode.light:
        return 'Selalu Terang';
      case AppThemeMode.dark:
        return 'Selalu Abu-abu Gelap';
    }
  }

  /// Cek apakah waktu tertentu masuk rentang jam 16:00 (4 sore) hingga 04:00 (4 pagi).
  static bool isNightTime([DateTime? now]) {
    final time = now ?? DateTime.now();
    final hour = time.hour;
    // Jam 16:00 (4 sore) sampai 03:59:59 (menjelang 4 pagi) -> Gelap
    // Jam 04:00 (4 pagi) sampai 15:59:59 (menjelang 4 sore) -> Terang
    return hour >= 16 || hour < 4;
  }

  /// Inisialisasi awal membaca preferensi dari storage dan menyalakan timer.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    WidgetsBinding.instance.addObserver(this);

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null) {
        _currentMode = AppThemeMode.values.firstWhere(
          (e) => e.name == saved,
          orElse: () => AppThemeMode.system,
        );
      } else {
        _currentMode = AppThemeMode.system;
      }
    } catch (e) {
      debugPrint('ThemeService init error: $e');
    }

    _lastIsDark = isDarkMode;

    // Periksa setiap 30 detik untuk mendeteksi pergantian jam secara instan
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkTimeTransition();
    });

    notifyListeners();
  }

  void _checkTimeTransition() {
    if (_currentMode == AppThemeMode.autoTime || _currentMode == AppThemeMode.system) {
      final currentIsDark = isDarkMode;
      if (currentIsDark != _lastIsDark) {
        _lastIsDark = currentIsDark;
        notifyListeners();
      }
    }
  }

  @override
  void didChangePlatformBrightness() {
    if (_currentMode == AppThemeMode.system) {
      final currentIsDark = isDarkMode;
      if (currentIsDark != _lastIsDark) {
        _lastIsDark = currentIsDark;
        notifyListeners();
      }
    }
  }

  /// Mengubah mode tema dan menyimpannya ke SharedPreferences.
  Future<void> setThemeMode(AppThemeMode mode) async {
    if (_currentMode == mode) return;
    _currentMode = mode;
    _lastIsDark = isDarkMode;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, mode.name);
    } catch (e) {
      debugPrint('Failed to save theme mode: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (_currentMode == AppThemeMode.autoTime || _currentMode == AppThemeMode.system)) {
      _checkTimeTransition();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
