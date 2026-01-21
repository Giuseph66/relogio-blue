import 'package:flutter/material.dart';
import '../routes/app_routes.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.black,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(
              color: Colors.black,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Relógio BLE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Controle via Bluetooth',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          _buildDrawerItem(
            context,
            icon: Icons.dashboard,
            title: 'Dashboard',
            route: AppRoutes.dashboard,
          ),
          _buildDrawerItem(
            context,
            icon: Icons.bluetooth_searching,
            title: 'Conectar Dispositivo',
            route: AppRoutes.connect,
          ),
          _buildDrawerItem(
            context,
            icon: Icons.message,
            title: 'Mensagens',
            route: AppRoutes.messages,
          ),
          _buildDrawerItem(
            context,
            icon: Icons.settings,
            title: 'Configurações',
            route: AppRoutes.settings,
          ),
          _buildDrawerItem(
            context,
            icon: Icons.map,
            title: 'Mapa',
            route: AppRoutes.map,
          ),
          const Divider(color: Colors.white24),
          ExpansionTile(
            title: const Text(
              'Demos',
              style: TextStyle(color: Colors.white),
            ),
            leading: const Icon(Icons.science, color: Colors.white),
            iconColor: Colors.white,
            collapsedIconColor: Colors.white,
            children: [
              _buildDrawerItem(
                context,
                icon: Icons.animation,
                title: 'Tela 1 - Animações',
                route: AppRoutes.tela1,
                indent: true,
              ),
              _buildDrawerItem(
                context,
                icon: Icons.touch_app,
                title: 'Tela 2 - Interatividade',
                route: AppRoutes.tela2,
                indent: true,
              ),
              _buildDrawerItem(
                context,
                icon: Icons.speed,
                title: 'Tela 3 - Performance',
                route: AppRoutes.tela3,
                indent: true,
              ),
            ],
          ),
          _buildDrawerItem(
            context,
            icon: Icons.info,
            title: 'Sobre',
            route: AppRoutes.about,
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String route,
    bool indent = false,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white),
      ),
      onTap: () {
        _navigateTo(context, route);
      },
      contentPadding: indent
          ? const EdgeInsets.only(left: 56, right: 16, top: 4, bottom: 4)
          : null,
    );
  }

  void _navigateTo(BuildContext context, String route) {
    final navigator = Navigator.of(context, rootNavigator: true);
    Navigator.pop(context);
    Future.microtask(() {
      navigator.pushReplacementNamed(route);
    });
  }
}
