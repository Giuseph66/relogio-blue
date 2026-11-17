import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'core/widgets/web_app_shell.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/routes/app_routes.dart';
import 'core/di/dependency_injection.dart';
import 'core/background/ble_foreground_service.dart';
import 'core/notifications/notification_service.dart';

import 'core/ui_mode/ui_mode_manager.dart';
import 'core/auth/auth_service.dart';
import 'core/offline/offline_question_cache.dart';
import 'features/permissions/presentation/pages/permission_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize background services
  await NotificationService().init();
  await BleForegroundServiceManager().init();

  // Initialize UI Mode State
  await UiModeManager().init();
  await ThemeController().init();

  // Restore authentication session
  await AuthService().init();

  // Initialize dependency injection
  final di = DependencyInjection();
  await di.initialize(mockMode: false);

  // Start connectivity-aware sync service
  di.syncService.start();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController().mode,
      builder: (context, themeMode, _) => ValueListenableBuilder<bool>(
        valueListenable: UiModeManager().useModernUiNotifier,
        builder: (context, isModernUi, child) {
          return MaterialApp(
            title: 'GeoNexo',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            // Legacy UI screens are dark-only (hard-coded colors).
            themeMode: isModernUi ? themeMode : ThemeMode.dark,
            initialRoute: kIsWeb ? null : AppRoutes.dashboard,
            onGenerateInitialRoutes: kIsWeb ? (route) => [
              AppRoutes.generateRoute(RouteSettings(name: AuthService().hasAppSession
                  ? (route == '/' ? AppRoutes.dashboard : route)
                  : AppRoutes.login)),
            ] : null,
            onGenerateRoute: AppRoutes.generateRoute,
            // Blocks every route until all required permissions are granted.
            builder: (context, child) => kIsWeb
                ? Overlay.wrap(child: WebAppShell(child: child ?? const SizedBox.shrink()))
                : PermissionGate(
              onAllGranted: _startBackgroundWork,
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
      ),
    );
  }
}

/// Runs once permissions are complete: background monitoring (works with the
/// app closed, with or without a watch) and the offline questions bundle.
void _startBackgroundWork() {
  BleForegroundServiceManager().ensureRunning();
  OfflineQuestionCache().refresh();
}
