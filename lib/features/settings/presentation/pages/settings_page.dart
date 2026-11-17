import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/background/ble_foreground_service.dart';
import '../../../../core/ble/ble_constants.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/permissions/permission_helper.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../core/ui_mode/ui_mode_manager.dart';
import '../../../../core/widgets/settings_tiles.dart';
import '../../../../core/widgets/web_app_shell.dart';
import '../../../auth/presentation/widgets/auth_guard.dart';
import '../../../ble_old/data/models/ble_settings_model.dart';
import '../../../ble_old/domain/entities/ble_settings.dart';
import 'notification_filters_page.dart';
import '../../../../core/theme/app_palette.dart';

/// Ajustes: every change is saved immediately (no "save" button), like a
/// system settings screen. Technical BLE fields live under "Avançado".
class ModernSettingsPage extends StatefulWidget {
  const ModernSettingsPage({super.key});

  @override
  State<ModernSettingsPage> createState() => _ModernSettingsPageState();
}

class _ModernSettingsPageState extends State<ModernSettingsPage> {
  final _di = DependencyInjection();
  final _foregroundService = BleForegroundServiceManager();

  bool _loaded = false;
  bool _advancedOpen = false;

  // Relógio
  String _deviceName = '';
  String? _deviceId;
  bool _autoReconnect = false;

  // Segundo plano
  bool _keepBleAliveInBackground = true;
  bool _keepServiceWhenAppClosed = true;
  String? _serviceTitle;
  String? _serviceText;

  // Notificações
  bool _notifyOnRx = true;
  bool _filterEnabled = false;
  List<String> _allowedPatterns = const [];

  // Avançado
  String _serviceUuid = BleConstants.defaultServiceUuid;
  String _writeUuid = BleConstants.defaultWriteCharacteristicUuid;
  String _notifyUuid = BleConstants.defaultNotifyCharacteristicUuid;
  bool _mockMode = false;
  ConnectionMode _connectionMode = ConnectionMode.ble;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final result = await _di.loadSettings();
    final s = result.valueOrNull ?? BleSettingsModel.defaults();
    if (!mounted) return;
    setState(() {
      _deviceName = s.preferredDeviceName;
      _deviceId = s.preferredDeviceId;
      _autoReconnect = s.autoReconnect;
      _keepBleAliveInBackground = s.keepBleAliveInBackground;
      _keepServiceWhenAppClosed = s.keepServiceWhenAppClosed;
      _serviceTitle = s.backgroundServiceTitle;
      _serviceText = s.backgroundServiceText;
      _notifyOnRx = s.backgroundNotifyOnRx;
      _filterEnabled = s.backgroundNotifyFilterEnabled;
      _allowedPatterns = List<String>.from(s.backgroundNotifyAllowedPatterns);
      _serviceUuid = s.serviceUuid;
      _writeUuid = s.writeCharacteristicUuid;
      _notifyUuid = s.notifyCharacteristicUuid;
      _mockMode = s.enableMockMode;
      _connectionMode = s.connectionMode;
      _loaded = true;
    });
  }

  BleSettings _buildSettings() {
    return BleSettingsModel(
      connectionMode: _connectionMode,
      serviceUuid: _serviceUuid,
      writeCharacteristicUuid: _writeUuid,
      notifyCharacteristicUuid: _notifyUuid,
      preferredDeviceName: _deviceName,
      preferredDeviceId: _deviceId,
      autoReconnect: _autoReconnect,
      enableMockMode: _mockMode,
      keepServiceWhenAppClosed: _keepServiceWhenAppClosed,
      keepBleAliveInBackground: _keepBleAliveInBackground,
      backgroundNotifyOnRx: _notifyOnRx,
      backgroundNotifyFilterEnabled: _filterEnabled,
      backgroundNotifyAllowedPatterns: _allowedPatterns,
      backgroundServiceTitle: _serviceTitle,
      backgroundServiceText: _serviceText,
      serverApiUrl: AppConfig.serverApiUrl,
    );
  }

  /// Applies [change] and persists right away.
  Future<void> _update(VoidCallback change) async {
    setState(change);
    final settings = _buildSettings();
    final result = await _di.saveSettings(settings);
    if (!mounted) return;
    if (!result.isSuccess) {
      _toast('Não foi possível salvar o ajuste', error: true);
      return;
    }
    await _pushForegroundConfigIfRunning(settings);
    if (!_keepServiceWhenAppClosed && _foregroundService.isRunning()) {
      await _foregroundService.stopBleKeepAliveService();
    }
  }

  Future<void> _pushForegroundConfigIfRunning(BleSettings settings) async {
    if (!_foregroundService.isRunning()) return;
    final currentDeviceId = _foregroundService.getCurrentDeviceId();
    if (currentDeviceId == null || currentDeviceId.isEmpty) return;

    await _foregroundService.startBleKeepAliveService(
      deviceId: currentDeviceId,
      deviceName: _foregroundService.getCurrentDeviceName(),
      serviceUuid: settings.serviceUuid,
      notifyCharacteristicUuid: settings.notifyCharacteristicUuid,
      serverApiUrl: settings.serverApiUrl,
      keepServiceWhenAppClosed: settings.keepServiceWhenAppClosed,
      backgroundNotifyOnRx: settings.backgroundNotifyOnRx,
      backgroundNotifyFilterEnabled: settings.backgroundNotifyFilterEnabled,
      backgroundNotifyAllowedPatterns: settings.backgroundNotifyAllowedPatterns,
    );
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red[700] : null,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  // ─── Edit dialogs ────────────────────────────────────────────────────────

  /// Generic form dialog. Returns the new values or null when cancelled.
  Future<List<String>?> _editDialog({
    required String title,
    required List<_FieldSpec> fields,
  }) {
    final controllers =
        fields.map((f) => TextEditingController(text: f.initial)).toList();
    final formKey = GlobalKey<FormState>();

    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.palette.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: TextStyle(color: context.palette.textPrimary)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < fields.length; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i < fields.length - 1 ? 12 : 0),
                  child: TextFormField(
                    controller: controllers[i],
                    autofocus: i == 0,
                    style: TextStyle(color: context.palette.textPrimary),
                    decoration: InputDecoration(
                      labelText: fields[i].label,
                      hintText: fields[i].hint,
                      helperText: fields[i].helper,
                      helperMaxLines: 2,
                      filled: true,
                      fillColor: context.palette.textPrimary.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: fields[i].required
                        ? (v) => (v == null || v.trim().isEmpty)
                            ? 'Campo obrigatório'
                            : null
                        : null,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.accent,
              foregroundColor: context.palette.onAccent,
            ),
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx, controllers.map((c) => c.text.trim()).toList());
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> _editDevice() async {
    final values = await _editDialog(
      title: 'Relógio preferido',
      fields: [
        _FieldSpec('Nome do dispositivo', _deviceName,
            hint: BleConstants.genericDeviceLabel),
        _FieldSpec('Endereço (opcional)', _deviceId ?? '',
            hint: 'AA:BB:CC:DD:EE:FF',
            helper: 'Use para conectar sempre ao mesmo relógio.'),
      ],
    );
    if (values == null) return;
    await _update(() {
      _deviceName = values[0];
      _deviceId = values[1].isEmpty ? null : values[1];
    });
    if (mounted) _toast('Relógio preferido atualizado');
  }

  Future<void> _editServiceNotification() async {
    final values = await _editDialog(
      title: 'Notificação fixa',
      fields: [
        _FieldSpec('Título', _serviceTitle ?? '', hint: 'GeoNexo'),
        _FieldSpec('Texto', _serviceText ?? '',
            hint: 'Conectado e recebendo mensagens'),
      ],
    );
    if (values == null) return;
    await _update(() {
      _serviceTitle = values[0].isEmpty ? null : values[0];
      _serviceText = values[1].isEmpty ? null : values[1];
    });
  }

  Future<void> _editUuid(String label, String current, ValueSetter<String> apply) async {
    final values = await _editDialog(
      title: label,
      fields: [_FieldSpec('UUID', current, required: true)],
    );
    if (values == null) return;
    await _update(() => apply(values[0]));
  }

  Future<void> _resetBleDefaults() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.palette.card,
        title: const Text('Restaurar padrões BLE?'),
        content: const Text(
          'Os UUIDs de serviço e características voltam aos valores de fábrica.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Restaurar', style: TextStyle(color: context.palette.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _update(() {
      _serviceUuid = BleConstants.defaultServiceUuid;
      _writeUuid = BleConstants.defaultWriteCharacteristicUuid;
      _notifyUuid = BleConstants.defaultNotifyCharacteristicUuid;
    });
    if (mounted) _toast('Padrões BLE restaurados');
  }

  Future<void> _openFilters() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationFiltersPage()),
    );
    // The filters page saves on its own — reload to reflect its changes.
    await _loadSettings();
  }

  Future<void> _pickTheme(ThemeMode current) async {
    final picked = await showModalBottomSheet<ThemeMode>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final p = ctx.palette;
        Widget option(ThemeMode mode, IconData icon, String description) {
          final selected = mode == current;
          return ListTile(
            leading: SettingsIcon(icon, color: selected ? p.accent : p.textMuted),
            title: Text(
              ThemeController.label(mode),
              style: TextStyle(
                color: p.textPrimary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            subtitle: Text(description, style: TextStyle(color: p.textSecondary)),
            trailing: selected ? Icon(Icons.check_rounded, color: p.accent) : null,
            onTap: () => Navigator.pop(ctx, mode),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                option(ThemeMode.system, Icons.brightness_auto_rounded,
                    'Segue o modo claro/escuro do celular'),
                option(ThemeMode.light, Icons.light_mode_rounded,
                    'Fundo claro, alto contraste'),
                option(ThemeMode.dark, Icons.dark_mode_rounded,
                    'Fundo escuro, menos brilho'),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) await ThemeController().setMode(picked);
  }

  Future<void> _switchToLegacyUi() async {
    await UiModeManager().toggleUiMode();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    }
  }

  // ─── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: !_loaded
          ? Center(child: CircularProgressIndicator(color: context.palette.accent))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (kIsWeb) WebAppShell.preferences(context),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: ThemeController().mode,
                  builder: (context, mode, _) => SettingsSection(
                    title: 'Aparência',
                    children: [
                      SettingsTile(
                        icon: switch (mode) {
                          ThemeMode.light => Icons.light_mode_rounded,
                          ThemeMode.dark => Icons.dark_mode_rounded,
                          ThemeMode.system => Icons.brightness_auto_rounded,
                        },
                        title: 'Tema',
                        subtitle: 'Claro melhora a leitura sob luz forte',
                        value: ThemeController.label(mode),
                        onTap: () => _pickTheme(mode),
                      ),
                    ],
                  ),
                ),
                SettingsSection(
                  title: 'Relógio',
                  children: [
                    SettingsTile(
                      icon: Icons.watch_rounded,
                      title: 'Relógio preferido',
                      subtitle: _deviceId ?? 'Qualquer dispositivo com este nome',
                      value: _deviceName.isEmpty ? 'Qualquer' : _deviceName,
                      onTap: _editDevice,
                    ),
                    SettingsSwitchTile(
                      icon: Icons.autorenew_rounded,
                      title: 'Reconectar automaticamente',
                      subtitle: 'Volta a conectar quando o relógio estiver por perto',
                      value: _autoReconnect,
                      onChanged: (v) => _update(() => _autoReconnect = v),
                    ),
                  ],
                ),
                if (!kIsWeb) SettingsSection(
                  title: 'Segundo plano',
                  footer:
                      'Necessário para receber perguntas no relógio com a tela desligada.',
                  children: [
                    SettingsSwitchTile(
                      icon: Icons.sync_rounded,
                      iconColor: context.palette.success,
                      title: 'Manter conexão ativa',
                      subtitle: 'Continua conectado com o app minimizado',
                      value: _keepBleAliveInBackground,
                      onChanged: (v) => _update(() => _keepBleAliveInBackground = v),
                    ),
                    SettingsSwitchTile(
                      icon: Icons.power_settings_new_rounded,
                      iconColor: context.palette.success,
                      title: 'Funcionar com o app fechado',
                      subtitle: 'Mantém o serviço rodando após fechar o app',
                      value: _keepServiceWhenAppClosed,
                      onChanged: (v) => _update(() => _keepServiceWhenAppClosed = v),
                    ),
                    SettingsTile(
                      icon: Icons.edit_notifications_outlined,
                      iconColor: context.palette.success,
                      title: 'Notificação fixa',
                      subtitle: _serviceTitle == null && _serviceText == null
                          ? 'Texto padrão'
                          : [_serviceTitle, _serviceText].whereType<String>().join(' · '),
                      onTap: _editServiceNotification,
                    ),
                  ],
                ),
                SettingsSection(
                  title: 'Notificações',
                  children: [
                    SettingsSwitchTile(
                      icon: Icons.notifications_active_outlined,
                      iconColor: context.palette.caution,
                      title: 'Mensagens do relógio',
                      subtitle: 'Avisar no celular quando o relógio enviar algo',
                      value: _notifyOnRx,
                      onChanged: (v) => _update(() => _notifyOnRx = v),
                    ),
                    SettingsTile(
                      icon: Icons.filter_list_rounded,
                      iconColor: context.palette.caution,
                      title: 'Filtros de mensagens',
                      value: !_filterEnabled
                          ? 'Desligado'
                          : '${_allowedPatterns.length} filtro(s)',
                      onTap: _openFilters,
                    ),
                    SettingsTile(
                      icon: Icons.admin_panel_settings_outlined,
                      iconColor: context.palette.caution,
                      title: 'Permissões do sistema',
                      subtitle: kIsWeb
                          ? 'Gerencie nas configurações deste site no navegador'
                          : 'Localização, Bluetooth e notificações',
                      onTap: kIsWeb ? null : PermissionHelper.openAppSettings,
                    ),
                  ],
                ),
                AuthGuard(
                  child: SettingsSection(
                    title: 'Dados',
                    children: [
                      SettingsTile(
                        icon: Icons.bookmarks_outlined,
                        iconColor: context.palette.warning,
                        title: 'Catálogo de locais',
                        subtitle: 'Locais salvos e visitas',
                        onTap: () => Navigator.pushNamed(context, AppRoutes.catalog),
                      ),
                      SettingsTile(
                        icon: Icons.history_rounded,
                        iconColor: context.palette.warning,
                        title: 'Histórico de respostas',
                        onTap: () => Navigator.pushNamed(context, AppRoutes.history),
                      ),
                      SettingsTile(
                        icon: Icons.dns_outlined,
                        iconColor: context.palette.warning,
                        title: 'Servidor',
                        subtitle: AppConfig.serverApiUrl,
                        trailing: Icon(Icons.copy_rounded,
                            size: 18, color: context.palette.textPrimary.withValues(alpha: 0.3)),
                        onTap: () async {
                          await Clipboard.setData(
                            ClipboardData(text: AppConfig.serverApiUrl),
                          );
                          if (mounted) _toast('Endereço copiado');
                        },
                      ),
                    ],
                  ),
                ),
                _buildAdvancedSection(),
                SettingsSection(
                  title: 'Sobre',
                  children: [
                    SettingsTile(
                      icon: Icons.info_outline_rounded,
                      iconColor: context.palette.textPrimary.withValues(alpha: 0.7),
                      title: 'GeoNexo',
                      value: 'Versão ${AppConfig.appVersion}',
                    ),
                    SettingsTile(
                      icon: Icons.description_outlined,
                      iconColor: context.palette.textPrimary.withValues(alpha: 0.7),
                      title: 'Licenças de código aberto',
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: 'GeoNexo',
                        applicationVersion: AppConfig.appVersion,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildAdvancedSection() {
    return SettingsSection(
      title: 'Avançado',
      footer: _advancedOpen
          ? 'Só altere se o firmware do relógio usar outros UUIDs.'
          : null,
      children: [
        SettingsTile(
          icon: Icons.developer_mode_rounded,
          iconColor: context.palette.info,
          title: 'Opções de desenvolvedor',
          subtitle: 'UUIDs BLE, modo simulado e interface antiga',
          trailing: AnimatedRotation(
            turns: _advancedOpen ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: Icon(Icons.expand_more_rounded,
                color: context.palette.textPrimary.withValues(alpha: 0.4)),
          ),
          onTap: () => setState(() => _advancedOpen = !_advancedOpen),
        ),
        if (_advancedOpen) ...[
          SettingsTile(
            icon: Icons.settings_bluetooth_rounded,
            iconColor: context.palette.info,
            title: 'Service UUID',
            subtitle: _serviceUuid,
            onTap: () => _editUuid('Service UUID', _serviceUuid, (v) => _serviceUuid = v),
          ),
          SettingsTile(
            icon: Icons.upload_rounded,
            iconColor: context.palette.info,
            title: 'Write UUID',
            subtitle: _writeUuid,
            onTap: () => _editUuid('Write UUID', _writeUuid, (v) => _writeUuid = v),
          ),
          SettingsTile(
            icon: Icons.download_rounded,
            iconColor: context.palette.info,
            title: 'Notify UUID',
            subtitle: _notifyUuid,
            onTap: () => _editUuid('Notify UUID', _notifyUuid, (v) => _notifyUuid = v),
          ),
          SettingsSwitchTile(
            icon: Icons.science_outlined,
            iconColor: context.palette.info,
            title: 'Modo simulado',
            subtitle: 'Testar o app sem um relógio real',
            value: _mockMode,
            onChanged: (v) => _update(() => _mockMode = v),
          ),
          SettingsTile(
            icon: Icons.restart_alt_rounded,
            title: 'Restaurar padrões BLE',
            destructive: true,
            showChevron: false,
            onTap: _resetBleDefaults,
          ),
          SettingsTile(
            icon: Icons.history_toggle_off_rounded,
            iconColor: context.palette.textPrimary.withValues(alpha: 0.54),
            title: 'Usar interface antiga',
            subtitle: 'Reabre o app no layout anterior',
            onTap: _switchToLegacyUi,
          ),
        ],
      ],
    );
  }
}

class _FieldSpec {
  final String label;
  final String initial;
  final String? hint;
  final String? helper;
  final bool required;

  const _FieldSpec(
    this.label,
    this.initial, {
    this.hint,
    this.helper,
    this.required = false,
  });
}
