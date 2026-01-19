import 'package:flutter/material.dart';
import '../../features/tela1/presentation/pages/tela1_page.dart';
import '../../features/tela2/presentation/pages/tela2_page.dart';
import '../../features/tela3/presentation/pages/tela3_page.dart';
import '../../features/ble/presentation/pages/dashboard_page.dart';
import '../../features/ble/presentation/pages/connect_device_page.dart';
import '../../features/ble/presentation/pages/messages_page.dart';
import '../../features/ble/presentation/pages/settings_page.dart';
import '../../features/ble/presentation/pages/about_page.dart';

class AppRoutes {
  static const String home = '/';
  static const String dashboard = '/dashboard';
  static const String connect = '/connect';
  static const String messages = '/messages';
  static const String settings = '/settings';
  static const String about = '/about';
  static const String tela1 = '/tela1';
  static const String tela2 = '/tela2';
  static const String tela3 = '/tela3';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    final routeName = settings.name ?? home;
    
    if (routeName == home || routeName == dashboard) {
      return MaterialPageRoute(
        builder: (_) => const DashboardPage(),
        settings: settings,
      );
    }
    
    if (routeName == connect) {
      return MaterialPageRoute(
        builder: (_) => const ConnectDevicePage(),
        settings: settings,
      );
    }
    
    if (routeName == messages) {
      return MaterialPageRoute(
        builder: (_) => const MessagesPage(),
        settings: settings,
      );
    }
    
    if (routeName == settings) {
      return MaterialPageRoute(
        builder: (_) => const SettingsPage(),
        settings: settings,
      );
    }
    
    if (routeName == about) {
      return MaterialPageRoute(
        builder: (_) => const AboutPage(),
        settings: settings,
      );
    }
    
    if (routeName == tela1) {
      return MaterialPageRoute(
        builder: (_) => const Tela1Page(),
        settings: settings,
      );
    }
    
    if (routeName == tela2) {
      return MaterialPageRoute(
        builder: (_) => const Tela2Page(),
        settings: settings,
      );
    }
    
    if (routeName == tela3) {
      return MaterialPageRoute(
        builder: (_) => const Tela3Page(),
        settings: settings,
      );
    }
    
    return MaterialPageRoute(
      builder: (_) => Scaffold(
        body: Center(
          child: Text('Rota não encontrada: ${settings.name}'),
        ),
      ),
    );
  }
}
