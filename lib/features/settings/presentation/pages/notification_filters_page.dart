import 'package:flutter/material.dart';

import '../../../../core/background/ble_foreground_service.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../ble_old/domain/entities/ble_settings.dart';

class NotificationFiltersPage extends StatefulWidget {
  const NotificationFiltersPage({super.key});

  @override
  State<NotificationFiltersPage> createState() => _NotificationFiltersPageState();
}

class _NotificationFiltersPageState extends State<NotificationFiltersPage> {
  static const List<String> _presetPatterns = [
    'BTN:',
    'SOS',
    'ALARM',
    'BATERIA',
    'STATUS',
    'ERROR',
  ];

  final DependencyInjection _di = DependencyInjection();
  final BleForegroundServiceManager _foregroundService =
      BleForegroundServiceManager();
  final TextEditingController _customPatternController = TextEditingController();

  BleSettings? _baseSettings;
  bool _backgroundNotifyOnRx = true;
  bool _backgroundNotifyFilterEnabled = false;
  List<String> _backgroundNotifyAllowedPatterns = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _customPatternController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final result = await _di.loadSettings();
    final settings = result.valueOrNull;
    if (settings == null || !mounted) return;

    setState(() {
      _baseSettings = settings;
      _backgroundNotifyOnRx = settings.backgroundNotifyOnRx;
      _backgroundNotifyFilterEnabled = settings.backgroundNotifyFilterEnabled;
      _backgroundNotifyAllowedPatterns =
          List<String>.from(settings.backgroundNotifyAllowedPatterns);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Filtros de Notificação'),
      ),
      body: _baseSettings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Escolha quais mensagens do relógio devem aparecer na barra de notificações.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  title: const Text(
                    'Notificações de RX',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Liga/desliga as notificações de mensagem do relógio',
                    style: TextStyle(color: Colors.white70),
                  ),
                  value: _backgroundNotifyOnRx,
                  onChanged: (value) =>
                      setState(() => _backgroundNotifyOnRx = value),
                ),
                SwitchListTile(
                  title: const Text(
                    'Filtrar mensagens específicas',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Quando ligado, só notifica se bater em algum filtro',
                    style: TextStyle(color: Colors.white70),
                  ),
                  value: _backgroundNotifyFilterEnabled,
                  onChanged: (value) =>
                      setState(() => _backgroundNotifyFilterEnabled = value),
                ),
                const SizedBox(height: 8),
                _buildCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Padrões rápidos',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _presetPatterns.map(_buildPatternChip).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Adicionar filtro customizado',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _customPatternController,
                              decoration: const InputDecoration(
                                hintText: 'Ex: BTN:S5 ou TEMP:ALTA',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _addCustomPattern,
                            child: const Text('Adicionar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Filtros ativos',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_backgroundNotifyAllowedPatterns.isEmpty)
                        const Text(
                          'Nenhum filtro selecionado',
                          style: TextStyle(color: Colors.white54),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _backgroundNotifyAllowedPatterns
                              .map((pattern) => InputChip(
                                    label: Text(pattern),
                                    onDeleted: () => _removePattern(pattern),
                                  ))
                              .toList(),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Salvando...' : 'Salvar filtros'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );
  }

  Widget _buildPatternChip(String pattern) {
    final selected = _isPatternSelected(pattern);
    return FilterChip(
      selected: selected,
      label: Text(pattern),
      onSelected: (_) => _togglePattern(pattern),
    );
  }

  bool _isPatternSelected(String pattern) {
    return _backgroundNotifyAllowedPatterns
        .map((e) => e.toLowerCase())
        .contains(pattern.toLowerCase());
  }

  void _togglePattern(String pattern) {
    final normalized = pattern.trim();
    if (normalized.isEmpty) return;

    setState(() {
      final exists = _isPatternSelected(normalized);
      if (exists) {
        _backgroundNotifyAllowedPatterns = _backgroundNotifyAllowedPatterns
            .where((value) => value.toLowerCase() != normalized.toLowerCase())
            .toList();
      } else {
        _backgroundNotifyAllowedPatterns = [
          ..._backgroundNotifyAllowedPatterns,
          normalized,
        ];
      }
    });
  }

  void _removePattern(String pattern) {
    setState(() {
      _backgroundNotifyAllowedPatterns = _backgroundNotifyAllowedPatterns
          .where((value) => value.toLowerCase() != pattern.toLowerCase())
          .toList();
    });
  }

  void _addCustomPattern() {
    final pattern = _customPatternController.text.trim();
    if (pattern.isEmpty) return;
    if (_isPatternSelected(pattern)) {
      _customPatternController.clear();
      return;
    }

    setState(() {
      _backgroundNotifyAllowedPatterns = [
        ..._backgroundNotifyAllowedPatterns,
        pattern,
      ];
    });
    _customPatternController.clear();
  }

  Future<void> _save() async {
    final baseSettings = _baseSettings;
    if (baseSettings == null) return;

    setState(() => _saving = true);
    final updatedSettings = baseSettings.copyWith(
      backgroundNotifyOnRx: _backgroundNotifyOnRx,
      backgroundNotifyFilterEnabled: _backgroundNotifyFilterEnabled,
      backgroundNotifyAllowedPatterns: _backgroundNotifyAllowedPatterns,
    );
    final result = await _di.saveSettings(updatedSettings);

    if (result.isSuccess) {
      await _updateForegroundTaskConfig(updatedSettings);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Filtros salvos com sucesso')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível salvar os filtros'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    if (mounted) {
      setState(() => _saving = false);
    }
  }

  Future<void> _updateForegroundTaskConfig(BleSettings settings) async {
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
