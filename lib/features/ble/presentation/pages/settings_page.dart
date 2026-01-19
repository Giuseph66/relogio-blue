import 'package:flutter/material.dart';
import '../../../../core/widgets/app_drawer.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/ble/ble_constants.dart';
import '../../data/models/ble_settings_model.dart';
import '../../domain/entities/ble_settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
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
  bool _keepBleAliveInBackground = true;
  bool _backgroundNotifyOnRx = true;
  ConnectionMode _connectionMode = ConnectionMode.ble;
  final _di = DependencyInjection();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final result = await _di.loadSettings();
    final settings = result.valueOrNull ?? BleSettingsModel.defaults();
    setState(() {
      _serviceUuidController.text = settings.serviceUuid;
      _writeUuidController.text = settings.writeCharacteristicUuid;
      _notifyUuidController.text = settings.notifyCharacteristicUuid;
      _deviceNameController.text = settings.preferredDeviceName;
      _deviceIdController.text = settings.preferredDeviceId ?? '';
      _autoReconnect = settings.autoReconnect;
      _enableMockMode = settings.enableMockMode;
      _keepBleAliveInBackground = settings.keepBleAliveInBackground;
      _backgroundNotifyOnRx = settings.backgroundNotifyOnRx;
      _backgroundServiceTitleController.text = settings.backgroundServiceTitle ?? '';
      _backgroundServiceTextController.text = settings.backgroundServiceText ?? '';
      _connectionMode = settings.connectionMode;
    });
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
      ),
      drawer: const AppDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Configurações BLE',
                style: TextStyle(
                  fontSize: 24,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 30),
              _buildTextField(
                'Service UUID',
                _serviceUuidController,
                hint: BleConstants.defaultServiceUuid,
              ),
              const SizedBox(height: 20),
              _buildTextField(
                'Write Characteristic UUID',
                _writeUuidController,
                hint: BleConstants.defaultWriteCharacteristicUuid,
              ),
              const SizedBox(height: 20),
              _buildTextField(
                'Notify Characteristic UUID',
                _notifyUuidController,
                hint: BleConstants.defaultNotifyCharacteristicUuid,
              ),
              const SizedBox(height: 30),
              const Text(
                'Dispositivo Preferido',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              _buildTextField(
                'Nome do Dispositivo',
                _deviceNameController,
                hint: BleConstants.defaultPreferredDeviceName,
              ),
              const SizedBox(height: 20),
              _buildTextField(
                'ID do Dispositivo (opcional)',
                _deviceIdController,
                required: false,
              ),
              const SizedBox(height: 30),
              SwitchListTile(
                title: const Text('Auto Reconectar', style: TextStyle(color: Colors.white)),
                value: _autoReconnect,
                onChanged: (value) => setState(() => _autoReconnect = value),
              ),
              SwitchListTile(
                title: const Text('Modo Simulado', style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  'Ative para testar sem hardware',
                  style: TextStyle(color: Colors.white70),
                ),
                value: _enableMockMode,
                onChanged: (value) => setState(() => _enableMockMode = value),
              ),
              const SizedBox(height: 30),
              const Text(
                'Background Service',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                title: const Text('Manter BLE ativo em background', style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  'Mantém a conexão BLE ativa quando o app está em segundo plano',
                  style: TextStyle(color: Colors.white70),
                ),
                value: _keepBleAliveInBackground,
                onChanged: (value) => setState(() => _keepBleAliveInBackground = value),
              ),
              SwitchListTile(
                title: const Text('Notificar ao receber mensagem', style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  'Exibe notificação quando uma mensagem é recebida em background',
                  style: TextStyle(color: Colors.white70),
                ),
                value: _backgroundNotifyOnRx,
                onChanged: (value) => setState(() => _backgroundNotifyOnRx = value),
              ),
              const SizedBox(height: 20),
              _buildTextField(
                'Título do Serviço (opcional)',
                _backgroundServiceTitleController,
                required: false,
                hint: 'Ex: Relógio BLE',
              ),
              const SizedBox(height: 20),
              _buildTextField(
                'Texto do Serviço (opcional)',
                _backgroundServiceTextController,
                required: false,
                hint: 'Ex: Conectado e recebendo mensagens',
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                  ),
                  child: const Text('Salvar Configurações'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    String? hint,
    bool required = true,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: const TextStyle(color: Colors.white38),
      ),
      style: const TextStyle(color: Colors.white),
      validator: required
          ? (value) => value == null || value.isEmpty ? 'Campo obrigatório' : null
          : null,
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
      preferredDeviceId: _deviceIdController.text.trim().isEmpty
          ? null
          : _deviceIdController.text.trim(),
      autoReconnect: _autoReconnect,
      enableMockMode: _enableMockMode,
      keepBleAliveInBackground: _keepBleAliveInBackground,
      backgroundNotifyOnRx: _backgroundNotifyOnRx,
      backgroundServiceTitle: _backgroundServiceTitleController.text.trim().isEmpty
          ? null
          : _backgroundServiceTitleController.text.trim(),
      backgroundServiceText: _backgroundServiceTextController.text.trim().isEmpty
          ? null
          : _backgroundServiceTextController.text.trim(),
    );

    final result = await _di.saveSettings(settings);
    if (result.isSuccess) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configurações salvas com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao salvar configurações'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
