import 'package:flutter/material.dart';
import '../../../../core/widgets/app_drawer.dart';
import '../../../../core/routes/app_routes.dart';
import '../controllers/messages_controller.dart';
import '../controllers/ble_controller.dart';
import '../../domain/entities/ble_message.dart';
import '../../domain/repositories/ble_repository.dart' as ble;

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
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

  @override
  Widget build(BuildContext context) {
    final isConnected = _connectionState == ble.ConnectionState.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mensagens'),
        actions: [
          IconButton(
            tooltip: 'Configurações',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          StreamBuilder<TickStatus>(
            stream: _messagesController.tickStatus,
            initialData: const TickStatus(),
            builder: (context, snapshot) {
              final status = snapshot.data ?? const TickStatus();
              return _buildTickStatus(status);
            },
          ),
          Expanded(
            child: StreamBuilder<List<BleMessage>>(
              stream: _messagesController.messages,
              builder: (context, snapshot) {
                final allMessages = snapshot.data ?? [];
                // Filter out "tick: ..." messages - they only update the status bar
                final messages = allMessages.where((msg) {
                  final content = msg.content.toLowerCase().trim();
                  return !content.startsWith('tick:') && !content.startsWith('tick :');
                }).toList();
                
                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'Nenhuma mensagem ainda',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                });
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    return _buildMessageItem(messages[index]);
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.2))),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Digite uma mensagem...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.1),
                        ),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _sendMessage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.all(16),
                      ),
                      child: const Icon(Icons.send),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildQuickButton('PING', () => _sendQuickMessage('PING')),
                    _buildQuickButton('STATUS', () => _sendQuickMessage('STATUS')),
                    _buildQuickButton('RESET', () => _sendQuickMessage('RESET')),
                    _buildQuickButton('LED ON', () => _sendQuickMessage('LED_ON')),
                    _buildQuickButton('LED OFF', () => _sendQuickMessage('LED_OFF')),
                    _buildQuickButton('LED STATUS', () => _sendQuickMessage('LED_STATUS')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTickStatus(TickStatus status) {
    final isOnline = status.online;
    final tickLabel = status.tickNumber != null ? status.tickNumber.toString() : '--';
    final timeLabel = status.lastSeen != null ? _formatTime(status.lastSeen!) : '--:--:--';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.circle,
            size: 10,
            color: isOnline ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Text(
            isOnline ? 'Online' : 'Offline',
            style: TextStyle(
              color: isOnline ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Text(
            'TICK: $tickLabel',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(width: 12),
          Text(
            timeLabel,
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(BleMessage message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: message.isReceived
            ? Colors.blue.withOpacity(0.2)
            : Colors.green.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: message.isReceived ? Colors.blue : Colors.green,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                message.isReceived ? Icons.download : Icons.upload,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                message.isReceived ? 'RX' : 'TX',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                _formatTime(message.timestamp),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message.content,
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white.withOpacity(0.2),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: Text(label),
    );
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isNotEmpty) {
      _messagesController.sendMessage(text);
      _messageController.clear();
    }
  }

  void _sendQuickMessage(String message) {
    _messagesController.sendMessage(message);
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}
