import 'package:flutter/material.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../ble_old/domain/repositories/ble_repository.dart' as ble;
import '../../../ble_old/presentation/controllers/ble_controller.dart';
import '../../../dashboard/presentation/pages/dashboard_page.dart';
import '../../../maps/presentation/pages/map_page.dart';
import '../../../profile/presentation/pages/profile_page.dart';
import '../widgets/main_nav_bar.dart';
import '../../../../core/theme/app_palette.dart';

/// Shell of the modern UI.
///
/// Header: Dispositivo (left) · tab title · Ajustes (right) — both open their
/// screens on top of the shell. Bottom bar: Mapa | Início | Perfil.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const int _homeTab = 1;
  static const int _profileTab = 2;
  // Tab order: 0 = Mapa, 1 = Início, 2 = Perfil.
  static const List<String> _titles = ['Mapa', 'Início', 'Perfil'];

  int _currentIndex = _homeTab;
  late final BleController _bleController;
  ble.ConnectionState _connectionState = ble.ConnectionState.disconnected;

  /// Bumped whenever the Perfil tab is opened so it reloads its stats.
  final ValueNotifier<int> _profileRefresh = ValueNotifier<int>(0);

  late final List<Widget> _pages = [
    const ModernMapPage(showAppBar: false),
    ModernDashboardPage(onOpenMap: () => _selectTab(0)),
    ProfilePage(refresh: _profileRefresh),
  ];

  @override
  void initState() {
    super.initState();
    _bleController = BleController();
    _bleController.connectionState.listen((state) {
      if (mounted) setState(() => _connectionState = state);
    });
  }

  @override
  void dispose() {
    _bleController.dispose();
    _profileRefresh.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (index == _profileTab) _profileRefresh.value++;
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final safeIndex = _currentIndex >= _pages.length ? _homeTab : _currentIndex;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (safeIndex != _homeTab) _selectTab(_homeTab);
      },
      child: Scaffold(
        // Content scrolls behind the floating, transparent nav bar.
        extendBody: true,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: true,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          leadingWidth: 72,
          leading: Center(
            child: _HeaderButton(
              icon: _deviceIcon,
              color: _deviceColor,
              statusColor: _deviceColor,
              tooltip: 'Dispositivo',
              onPressed: () => Navigator.pushNamed(context, AppRoutes.connect),
            ),
          ),
          title: Text(_titles[safeIndex]),
          actions: [
            _HeaderButton(
              icon: Icons.settings_outlined,
              color: context.palette.textPrimary.withValues(alpha: 0.7),
              tooltip: 'Ajustes',
              onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: IndexedStack(
          index: safeIndex,
          children: _pages,
        ),
        bottomNavigationBar: MainNavBar(
          currentIndex: safeIndex,
          onTap: _selectTab,
          items: const [
            MainNavItem(
              icon: Icons.map_outlined,
              activeIcon: Icons.map_rounded,
              label: 'Mapa',
            ),
            MainNavItem(
              icon: Icons.dashboard_outlined,
              activeIcon: Icons.dashboard_rounded,
              label: 'Início',
            ),
            MainNavItem(
              icon: Icons.person_outline_rounded,
              activeIcon: Icons.person_rounded,
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }

  IconData get _deviceIcon => switch (_connectionState) {
        ble.ConnectionState.connected => Icons.bluetooth_connected_rounded,
        ble.ConnectionState.connecting => Icons.bluetooth_searching_rounded,
        _ => Icons.bluetooth_rounded,
      };

  Color get _deviceColor => switch (_connectionState) {
        ble.ConnectionState.connected => context.palette.success,
        ble.ConnectionState.connecting => context.palette.caution,
        _ => context.palette.textPrimary.withValues(alpha: 0.38),
      };
}

/// Round header button with an optional status dot.
class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color? statusColor;
  final String tooltip;
  final VoidCallback onPressed;

  const _HeaderButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
    this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: context.palette.textPrimary.withValues(alpha: 0.06),
        shape: CircleBorder(
          side: BorderSide(color: context.palette.textPrimary.withValues(alpha: 0.1)),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, color: color, size: 22),
                if (statusColor != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
