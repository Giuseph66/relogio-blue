import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/routes/app_routes.dart';
import 'core/di/dependency_injection.dart';
import 'core/background/ble_foreground_service.dart';
import 'core/notifications/notification_service.dart';

import 'core/ui_mode/ui_mode_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize background services
  await NotificationService().init();
  await BleForegroundServiceManager().init();
  
  // Initialize UI Mode State
  await UiModeManager().init();
  
  // Initialize dependency injection
  await DependencyInjection().initialize(mockMode: false);
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: UiModeManager().useModernUiNotifier,
      builder: (context, isModernUi, child) {
        return MaterialApp(
          title: 'Relógio App',
          theme: AppTheme.darkTheme,
          initialRoute: AppRoutes.dashboard,
          onGenerateRoute: AppRoutes.generateRoute,
        );
      },
    );
  }
}
