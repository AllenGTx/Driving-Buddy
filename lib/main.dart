import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models/account_config.dart';

import 'firebase_options.dart';
import 'services/theme_service.dart';
import 'core/app_colors.dart';
import 'core/app_theme.dart';
import 'routes/app_routes.dart';

// Exports for backward compatibility
export 'core/app_colors.dart';
export 'core/app_theme.dart';
export 'services/theme_service.dart';
export 'models/account_config.dart';
export 'models/trip_model.dart';
export 'routes/app_routes.dart';
export 'screens/main_shell.dart';
export 'screens/home_screen.dart';
export 'screens/monitor_screen.dart';
export 'screens/history_screen.dart';
export 'screens/settings_screen.dart';
export 'widgets/driving_buddy_app_bar.dart';

// ============================================================================
// MAIN ENTRY POINT
// ============================================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inisialisasi service tema (otomatis jam 16:00 - 04:00 & cache preferensi)
  await ThemeService.instance.init();

  // Inisialisasi Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ Firebase initialized successfully');
    final curUser = FirebaseAuth.instance.currentUser;
    if (curUser?.email != null) {
      await AccountConfig.getPhotoUrl(userEmail: curUser!.email);
    }
  } catch (e) {
    debugPrint('⚠️ Firebase initialize warning (menunggu auth key asli): $e');
  }

  runApp(const DrivingBuddyApp());
}

// ============================================================================
// APP ROOT
// ============================================================================

class DrivingBuddyApp extends StatelessWidget {
  const DrivingBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final isDark = ThemeService.instance.isDarkMode;

        // Sesuaikan warna status bar & navigation bar sistem
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarColor: isDark ? AppColors.darkSurface : Colors.white,
            systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          ),
        );

        return MaterialApp(
          title: 'DrivingBuddy',
          debugShowCheckedModeBanner: false,
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          initialRoute: AppRoutes.initial,
          routes: AppRoutes.routes,
          onGenerateRoute: AppRoutes.onGenerateRoute,
        );
      },
    );
  }
}
