import 'package:flutter/material.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../ble_old/presentation/controllers/messages_controller.dart';
import '../../../ble_old/presentation/controllers/ble_controller.dart';
import '../../../ble_old/domain/entities/ble_message.dart';
import '../../../ble_old/domain/repositories/ble_repository.dart' as ble;

class ModernMessagesPage extends StatefulWidget {
  const ModernMessagesPage({super.key});

  @override
  State<ModernMessagesPage> createState() => _ModernMessagesPageState();
}

class _ModernMessagesPageState extends State<ModernMessagesPage> {
  late final MessagesController _messagesController;
  late final BleController _bleController;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  ble.ConnectionState _connectionState = ble.ConnectionState.disconnected;

  @override
  void initState() {
    super.initState();
    _messagesController = MessagesController();
    _bleController = BleController();
    _bleController.connectionState.listen((state) {
      if (!mounted) return;
      setState(() => _connectionState = state);
    });
  }

  @override
  void dispose() {
    _bleController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _connectionState == ble.ConnectionState.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Console'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        children: [
          _buildStatusBar(),
          if (!isConnected)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.pushNamed(context, AppRoutes.connect),
                  icon: const Icon(Icons.bluetooth_searching, size: 18),
                  label: const Text('Conectar dispositivo'),
                ),
              ),
            ),
          Expanded(child: _buildMessageList()),
          _buildQuickCommands(isConnected),
          _buildInputArea(isConnected),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return StreamBuilder<TickStatus>(
      stream: _messagesController.tickStatus,
      initialData: const TickStatus(),
      builder: (context, snapshot) {
        final status = snapshot.data ?? const TickStatus();
        final isOnline = status.online;
        
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isOnline ? Colors.greenAccent : Colors.redAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isOnline ? 'Conectado' : 'Offline',
                style: TextStyle(
                  color: isOnline ? Colors.greenAccent : Colors.redAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              _buildSmallBadge(_connectionLabel()),
              const SizedBox(width: 8),
              _buildSmallBadge('TICK: ${status.tickNumber ?? "--"}'),
              const SizedBox(width: 8),
              if (status.lastSeen != null)
                _buildSmallBadge(_formatTime(status.lastSeen!)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSmallBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white54, fontSize: 10)),
    );
  }

  Widget _buildMessageList() {
    return StreamBuilder<List<BleMessage>>(
      stream: _messagesController.messages,
      builder: (context, snapshot) {
        final allMessages = snapshot.data ?? [];
        final messages = allMessages.where((msg) {
          final content = msg.content.toLowerCase().trim();
          return !content.startsWith('tick:') && !content.startsWith('tick :');
        }).toList();

        if (messages.isEmpty) {
          return const Center(child: Text('Nenhum log disponível', style: TextStyle(color: Colors.white24)));
        }

        _scrollToBottom();

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final msg = messages[index];
            return _buildChatBubble(msg);
          },
        );
      },
    );
  }

  Widget _buildChatBubble(BleMessage message) {
    final bool isRx = message.isReceived;
    return Align(
      alignment: isRx ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isRx ? Colors.white.withOpacity(0.08) : Colors.cyanAccent.withOpacity(0.15),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isRx ? 4 : 20),
            bottomRight: Radius.circular(isRx ? 20 : 4),
          ),
          border: Border.all(
            color: isRx ? Colors.white10 : Colors.cyanAccent.withOpacity(0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isRx ? Icons.south_west : Icons.north_east,
                  size: 10,
                  color: isRx ? Colors.white38 : Colors.cyanAccent,
                ),
                const SizedBox(width: 4),
                Text(
                  _formatTime(message.timestamp),
                  style: const TextStyle(color: Colors.white24, fontSize: 9),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              message.content,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickCommands(bool isConnected) {
    final commands = ['PING', 'STATUS', 'RESET', 'LED_ON', 'LED_OFF', 'TIME'];
    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        scrollDirection: Axis.horizontal,
        itemCount: commands.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return ActionChip(
            label: Text(commands[index], style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            backgroundColor: Colors.white10,
            labelStyle: TextStyle(color: isConnected ? Colors.white70 : Colors.white30),
            onPressed: isConnected ? () => _sendMessage(commands[index]) : null,
          );
        },
      ),
    );
  }

  Widget _buildInputArea(bool isConnected) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              onSubmitted: (_) => _sendMessage(),
              enabled: isConnected,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enviar comando...',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: isConnected ? _sendMessage : null,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.send,
                color: isConnected ? Colors.black : Colors.black38,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage([String? text]) async {
    if (_connectionState != ble.ConnectionState.connected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dispositivo desconectado. Conecte antes de enviar comandos.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final content = text ?? _messageController.text.trim();
    if (content.isNotEmpty) {
      final sent = await _messagesController.sendMessage(content);
      if (!sent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Falha ao enviar mensagem para o dispositivo'),
            backgroundColor: Colors.red,
          ),
        );
      }
      if (text == null) _messageController.clear();
      _scrollToBottom();
    }
  }

  String _connectionLabel() {
    return switch (_connectionState) {
      ble.ConnectionState.disconnected => 'BLE: desconectado',
      ble.ConnectionState.connecting => 'BLE: conectando',
      ble.ConnectionState.connected => 'BLE: conectado',
      ble.ConnectionState.disconnecting => 'BLE: desconectando',
    };
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}
