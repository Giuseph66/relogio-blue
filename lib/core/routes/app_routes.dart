import 'package:flutter/material.dart';
import '../../features/tela1_old/presentation/pages/tela1_page.dart';
import '../../features/tela2_old/presentation/pages/tela2_page.dart';
import '../../features/tela3_old/presentation/pages/tela3_page.dart';
import '../../features/ble_old/presentation/pages/dashboard_page.dart';
import '../../features/ble_old/presentation/pages/connect_device_page.dart';
import '../../features/ble_old/presentation/pages/messages_page.dart';
import '../../features/ble_old/presentation/pages/settings_page.dart';
import '../../features/ble_old/presentation/pages/about_page.dart';
import '../../features/maps_old/presentation/pages/map_page.dart';

// Novos caminhos da Interface Moderna
import '../../features/main/presentation/pages/main_screen.dart';
import '../../features/ble/presentation/pages/connect_device_page.dart';
import '../../features/ble/presentation/pages/messages_page.dart';
import '../../features/maps/presentation/pages/map_page.dart';
import '../../features/location_tracker/presentation/pages/location_catalog_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../ui_mode/ui_mode_manager.dart';

class AppRoutes {
  static const String home = '/';
  static const String dashboard = '/dashboard';
  static const String catalog = '/catalog';
  static const String connect = '/connect';
  static const String messages = '/messages';
  static const String settings = '/settings';
  static const String about = '/about';
  static const String map = '/map';
  static const String tela1 = '/tela1';
  static const String tela2 = '/tela2';
  static const String tela3 = '/tela3';

  static Route<dynamic> generateRoute(RouteSettings routeSettings) {
    final isModernUi = UiModeManager().isModernUi;
    final routeName = routeSettings.name ?? home;
    
    if (routeName == home || routeName == dashboard) {
      if (isModernUi) {
        return MaterialPageRoute(
          builder: (_) => const MainScreen(),
          settings: routeSettings,
        );
      }
      return MaterialPageRoute(
        builder: (_) => const DashboardPage(),
        settings: routeSettings,
      );
    }
    
    if (routeName == connect) {
      if (isModernUi) {
        return MaterialPageRoute(
          builder: (_) => const ModernConnectDevicePage(),
          settings: routeSettings,
        );
      }
      return MaterialPageRoute(
        builder: (_) => const ConnectDevicePage(),
        settings: routeSettings,
      );
    }
    
    if (routeName == messages) {
      if (isModernUi) {
        return MaterialPageRoute(
          builder: (_) => const ModernMessagesPage(),
          settings: routeSettings,
        );
      }
      return MaterialPageRoute(
        builder: (_) => const MessagesPage(),
        settings: routeSettings,
      );
    }
    
    if (routeName == AppRoutes.settings) {
      if (isModernUi) {
        return MaterialPageRoute(
          builder: (_) => const ModernSettingsPage(),
          settings: routeSettings,
        );
      }
      return MaterialPageRoute(
        builder: (_) => const SettingsPage(),
        settings: routeSettings,
      );
    }
    
    if (routeName == about) {
      return MaterialPageRoute(
        builder: (_) => const AboutPage(),
        settings: routeSettings,
      );
    }
    
    if (routeName == map) {
      if (isModernUi) {
        return MaterialPageRoute(
          builder: (_) => const ModernMapPage(),
          settings: routeSettings,
        );
      }
      return MaterialPageRoute(
        builder: (_) => const MapPage(),
        settings: routeSettings,
      );
    }

    if (routeName == catalog) {
      return MaterialPageRoute(
        builder: (_) => const LocationCatalogPage(),
        settings: routeSettings,
      );
    }
    
    if (routeName == tela1) {
      return MaterialPageRoute(
        builder: (_) => const Tela1Page(),
        settings: routeSettings,
      );
    }
    
    if (routeName == tela2) {
      return MaterialPageRoute(
        builder: (_) => const Tela2Page(),
        settings: routeSettings,
      );
    }
    
    if (routeName == tela3) {
      return MaterialPageRoute(
        builder: (_) => const Tela3Page(),
        settings: routeSettings,
      );
    }
    
    return MaterialPageRoute(
      builder: (_) => Scaffold(
        body: Center(
          child: Text('Rota não encontrada: ${routeSettings.name}'),
        ),
      ),
    );
  }
}
