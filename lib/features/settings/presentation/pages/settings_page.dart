import 'package:flutter/material.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/config/app_config.dart';
import '../../../auth/presentation/widgets/auth_guard.dart';
import '../../../../core/background/ble_foreground_service.dart';
import '../../../../core/ui_mode/ui_mode_manager.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../ble_old/data/models/ble_settings_model.dart';
import '../../../ble_old/domain/entities/ble_settings.dart';

class ModernSettingsPage extends StatefulWidget {
  const ModernSettingsPage({super.key});

  @override
  State<ModernSettingsPage> createState() => _ModernSettingsPageState();
}

class _ModernSettingsPageState extends State<ModernSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _serviceUuidController = TextEditingController();
  final _writeUuidController = TextEditingController();
  final _notifyUuidController = TextEditingController();
  final _deviceNameController = TextEditingController();
  final _deviceIdController = TextEditingController();
  final _backgroundServiceTitleController = TextEditingController();
  final _backgroundServiceTextController = TextEditingController();
  
  bool _autoReconnect = false;
  bool _enableMockMode = false;
  bool _keepServiceWhenAppClosed = true;
  bool _keepBleAliveInBackground = true;
  bool _backgroundNotifyOnRx = true;
  bool _backgroundNotifyFilterEnabled = false;
  List<String> _backgroundNotifyAllowedPatterns = const [];
  ConnectionMode _connectionMode = ConnectionMode.ble;
  
  final _di = DependencyInjection();
  final _foregroundService = BleForegroundServiceManager();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final result = await _di.loadSettings();
    final settings = result.valueOrNull ?? BleSettingsModel.defaults();
    if (mounted) {
      setState(() {
        _serviceUuidController.text = settings.serviceUuid;
        _writeUuidController.text = settings.writeCharacteristicUuid;
        _notifyUuidController.text = settings.notifyCharacteristicUuid;
        _deviceNameController.text = settings.preferredDeviceName;
        _deviceIdController.text = settings.preferredDeviceId ?? '';
        _autoReconnect = settings.autoReconnect;
        _enableMockMode = settings.enableMockMode;
        _keepServiceWhenAppClosed = settings.keepServiceWhenAppClosed;
        _keepBleAliveInBackground = settings.keepBleAliveInBackground;
        _backgroundNotifyOnRx = settings.backgroundNotifyOnRx;
        _backgroundNotifyFilterEnabled = settings.backgroundNotifyFilterEnabled;
        _backgroundNotifyAllowedPatterns =
            List<String>.from(settings.backgroundNotifyAllowedPatterns);
        _backgroundServiceTitleController.text = settings.backgroundServiceTitle ?? '';
        _backgroundServiceTextController.text = settings.backgroundServiceText ?? '';
        _connectionMode = settings.connectionMode;
      });
    }
  }

  @override
  void dispose() {
    _serviceUuidController.dispose();
    _writeUuidController.dispose();
    _notifyUuidController.dispose();
    _deviceNameController.dispose();
    _deviceIdController.dispose();
    _backgroundServiceTitleController.dispose();
    _backgroundServiceTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              _buildSectionHeader('Bluetooth'),
              const SizedBox(height: 12),
              _buildGlassCard(
                child: Column(
                  children: [
                    _buildModernTextField('Dispositivo Preferido', _deviceNameController, Icons.watch),
                    const Divider(color: Colors.white10),
                    _buildModernTextField('ID do Dispositivo', _deviceIdController, Icons.perm_identity, required: false),
                    const Divider(color: Colors.white10),
                    SwitchListTile(
                      title: const Text('Auto Reconectar', style: TextStyle(color: Colors.white, fontSize: 14)),
                      value: _autoReconnect,
                      activeColor: Colors.cyanAccent,
                      onChanged: (val) => setState(() => _autoReconnect = val),
                    ),
                    const Divider(color: Colors.white10),
                    SwitchListTile(
                      title: const Text('Modo Simulado', style: TextStyle(color: Colors.white, fontSize: 14)),
                      subtitle: const Text(
                        'Ative para testar sem hardware BLE',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                      value: _enableMockMode,
                      activeColor: Colors.cyanAccent,
                      onChanged: (val) => setState(() => _enableMockMode = val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildGlassCard(
                child: Column(
                  children: [
                    _buildModernTextField('Service UUID', _serviceUuidController, Icons.settings_bluetooth),
                    const Divider(color: Colors.white10),
                    _buildModernTextField('Write UUID', _writeUuidController, Icons.upload_file),
                    const Divider(color: Colors.white10),
                    _buildModernTextField('Notify UUID', _notifyUuidController, Icons.notifications_active),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _buildSectionHeader('Serviço & Background'),
              const SizedBox(height: 12),
              _buildGlassCard(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Serviço Persistente', style: TextStyle(color: Colors.white, fontSize: 14)),
                      subtitle: const Text('Manter ativo ao fechar o app', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      value: _keepServiceWhenAppClosed,
                      activeColor: Colors.cyanAccent,
                      onChanged: (val) => setState(() => _keepServiceWhenAppClosed = val),
                    ),
                    const Divider(color: Colors.white10),
                    SwitchListTile(
                      title: const Text('BLE em Background', style: TextStyle(color: Colors.white, fontSize: 14)),
                      value: _keepBleAliveInBackground,
                      activeColor: Colors.cyanAccent,
                      onChanged: (val) => setState(() => _keepBleAliveInBackground = val),
                    ),
                    const Divider(color: Colors.white10),
                    SwitchListTile(
                      title: const Text('Notificações', style: TextStyle(color: Colors.white, fontSize: 14)),
                      subtitle: const Text('Receber notificação ao receber mensagem', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      value: _backgroundNotifyOnRx,
                      activeColor: Colors.cyanAccent,
                      onChanged: (val) => setState(() => _backgroundNotifyOnRx = val),
                    ),
                    const Divider(color: Colors.white10),
                    _buildModernTextField(
                      'Título da notificação',
                      _backgroundServiceTitleController,
                      Icons.title,
                      required: false,
                      hint: 'Ex: Relógio BLE',
                    ),
                    const Divider(color: Colors.white10),
                    _buildModernTextField(
                      'Texto da notificação',
                      _backgroundServiceTextController,
                      Icons.short_text,
                      required: false,
                      hint: 'Ex: Conectado e recebendo mensagens',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              AuthGuard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader('API do Servidor'),
                    const SizedBox(height: 12),
                    _buildGlassCard(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            const Icon(Icons.lan, color: Colors.white38, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('URL da API', style: TextStyle(color: Colors.white38, fontSize: 12)),
                                  const SizedBox(height: 2),
                                  Text(
                                    AppConfig.serverApiUrl,
                                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildSectionHeader('Extras'),
                    const SizedBox(height: 12),
                    _buildGlassCard(
                      child: ListTile(
                        leading: const Icon(Icons.map_outlined, color: Colors.cyanAccent),
                        title: const Text('Catálogo de Locais', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: const Text('Gerenciar locais salvos e histórico', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                        onTap: () => Navigator.of(context).pushNamed(AppRoutes.catalog),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: const Text('SALVAR ALTERAÇÕES', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    await UiModeManager().toggleUiMode();
                    if (context.mounted) {
                      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: const Text('VOLTAR PARA INTERFACE ANTIGA', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: child,
    );
  }

  Widget _buildModernTextField(String label, TextEditingController controller, IconData icon, {bool required = true, String? hint}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextFormField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: Colors.white38, size: 20),
          labelStyle: const TextStyle(color: Colors.white38, fontSize: 14),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        validator: required ? (val) => val == null || val.isEmpty ? 'Obrigatório' : null : null,
      ),
    );
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    final settings = BleSettingsModel(
      connectionMode: _connectionMode,
      serviceUuid: _serviceUuidController.text.trim(),
      writeCharacteristicUuid: _writeUuidController.text.trim(),
      notifyCharacteristicUuid: _notifyUuidController.text.trim(),
      preferredDeviceName: _deviceNameController.text.trim(),
      preferredDeviceId: _deviceIdController.text.trim().isEmpty ? null : _deviceIdController.text.trim(),
      autoReconnect: _autoReconnect,
      enableMockMode: _enableMockMode,
      keepServiceWhenAppClosed: _keepServiceWhenAppClosed,
      keepBleAliveInBackground: _keepBleAliveInBackground,
      backgroundNotifyOnRx: _backgroundNotifyOnRx,
      backgroundNotifyFilterEnabled: _backgroundNotifyFilterEnabled,
      backgroundNotifyAllowedPatterns: _backgroundNotifyAllowedPatterns,
      backgroundServiceTitle: _backgroundServiceTitleController.text.trim().isEmpty ? null : _backgroundServiceTitleController.text.trim(),
      backgroundServiceText: _backgroundServiceTextController.text.trim().isEmpty ? null : _backgroundServiceTextController.text.trim(),
      serverApiUrl: AppConfig.serverApiUrl,
    );

    final result = await _di.saveSettings(settings);
    if (result.isSuccess) {
      await _pushForegroundConfigIfRunning(settings);
      if (!_keepServiceWhenAppClosed) {
        await _foregroundService.stopBleKeepAliveService();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configurações salvas!'), backgroundColor: Colors.cyan),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro ao salvar configurações'),
          backgroundColor: Colors.red,
        ),
      );
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
}
