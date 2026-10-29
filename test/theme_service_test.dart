import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:driving_buddy/services/theme_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  group('ThemeService Time-based & Mode Switch Tests', () {
    test('isNightTime: Jam 16:00 (4 sore) sampai 03:59 (4 pagi) adalah mode gelap (true)', () {
      // 16:00 tepat (4 sore) -> Dark Mode
      expect(ThemeService.isNightTime(DateTime(2026, 10, 28, 16, 0)), isTrue);

      // 18:30 (petang) -> Dark Mode
      expect(ThemeService.isNightTime(DateTime(2026, 10, 28, 18, 30)), isTrue);

      // 23:59 (tengah malam) -> Dark Mode
      expect(ThemeService.isNightTime(DateTime(2026, 10, 28, 23, 59)), isTrue);

      // 00:00 (dini hari) -> Dark Mode
      expect(ThemeService.isNightTime(DateTime(2026, 10, 28, 0, 0)), isTrue);

      // 03:59 (menjelang 4 pagi) -> Dark Mode
      expect(ThemeService.isNightTime(DateTime(2026, 10, 28, 3, 59)), isTrue);
    });

    test('isNightTime: Jam 04:00 (4 pagi) sampai 15:59 (4 sore) adalah mode terang (false)', () {
      // 04:00 tepat (4 pagi) -> Light Mode
      expect(ThemeService.isNightTime(DateTime(2026, 10, 28, 4, 0)), isFalse);

      // 08:00 (pagi hari) -> Light Mode
      expect(ThemeService.isNightTime(DateTime(2026, 10, 28, 8, 0)), isFalse);

      // 12:00 (siang) -> Light Mode
      expect(ThemeService.isNightTime(DateTime(2026, 10, 28, 12, 0)), isFalse);

      // 15:59 (menjelang 4 sore) -> Light Mode
      expect(ThemeService.isNightTime(DateTime(2026, 10, 28, 15, 59)), isFalse);
    });

    test('Manual Override: light mode and dark mode', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final service = ThemeService.instance;

      await service.setThemeMode(AppThemeMode.light);
      expect(service.isDarkMode, isFalse);

      await service.setThemeMode(AppThemeMode.dark);
      expect(service.isDarkMode, isTrue);

      await service.setThemeMode(AppThemeMode.autoTime);
      expect(service.isDarkMode, ThemeService.isNightTime());
    });
  });
}
