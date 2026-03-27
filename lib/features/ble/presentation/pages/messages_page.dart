import 'package:flutter/material.dart';
import '../../../../core/ble/ble_question_protocol.dart';
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

class _QuickQuestionPreset {
  final String label;
  final String question;
  final List<BleQuestionOption> options;

  const _QuickQuestionPreset({
    required this.label,
    required this.question,
    required this.options,
  });
}

const List<_QuickQuestionPreset> _questionPresets = [
  _QuickQuestionPreset(
    label: 'Confirmar',
    question: 'Confirmar acao?',
    options: [
      BleQuestionOption(id: 'ok', label: 'OK'),
      BleQuestionOption(id: 'cancel', label: 'Cancelar'),
    ],
  ),
  _QuickQuestionPreset(
    label: 'Modo',
    question: 'Escolha o modo',
    options: [
      BleQuestionOption(id: 'casa', label: 'Casa'),
      BleQuestionOption(id: 'rua', label: 'Rua'),
      BleQuestionOption(id: 'sono', label: 'Sono'),
    ],
  ),
  _QuickQuestionPreset(
    label: 'Prioridade',
    question: 'Qual prioridade?',
    options: [
      BleQuestionOption(id: 'b1', label: 'Baixa'),
      BleQuestionOption(id: 'm1', label: 'Media'),
      BleQuestionOption(id: 'a1', label: 'Alta'),
    ],
  ),
  _QuickQuestionPreset(
    label: 'Cantina',
    question: 'Oque voce achou da nova cantina ?',
    options: [
      BleQuestionOption(id: 'boa', label: 'Boa'),
      BleQuestionOption(id: 'ruim', label: 'Ruim'),
      BleQuestionOption(id: 'antes', label: 'antes era melhor'),
    ],
  ),
];

class _ModernMessagesPageState extends State<ModernMessagesPage> {
  late final MessagesController _messagesController;
  late final BleController _bleController;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  ble.ConnectionState _connectionState = ble.ConnectionState.disconnected;
  int _questionCounter = 0;

  @override
  void initState() {
    super.initState();
    _messagesController = MessagesController();
    _bleController = BleController();
    _bleController.connectionState.listen((state) {
      if (!mounted) return;
      setState(() => _connectionState = state);
    });
    // Rebuild quando o tick status mudar para refletir isWatchConnected
    _messagesController.tickStatus.listen((_) {
      if (mounted) setState(() {});
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
    final isConnected =
        _connectionState == ble.ConnectionState.connected ||
        _messagesController.isWatchConnected;

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
                  onPressed: () =>
                      Navigator.pushNamed(context, AppRoutes.connect),
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
            color: Colors.white.withValues(alpha: 0.05),
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
      child: Text(
        text,
        style: const TextStyle(color: Colors.white54, fontSize: 10),
      ),
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
        final questionIndex = <String, BleQuestionPrompt>{};
        for (final msg in messages) {
          final prompt = tryParseBleQuestionCommand(msg.content);
          if (prompt != null) {
            questionIndex[prompt.questionId] = prompt;
          }
        }

        if (messages.isEmpty) {
          return const Center(
            child: Text(
              'Nenhum log disponível',
              style: TextStyle(color: Colors.white24),
            ),
          );
        }

        _scrollToBottom();

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final msg = messages[index];
            return _buildChatBubble(msg, questionIndex);
          },
        );
      },
    );
  }

  Widget _buildChatBubble(
    BleMessage message,
    Map<String, BleQuestionPrompt> questionIndex,
  ) {
    final bool isRx = message.isReceived;
    final parsedQuestion = tryParseBleQuestionCommand(message.content);
    final parsedResult = tryParseBleQuestionResult(message.content);
    return Align(
      alignment: isRx ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isRx
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.cyanAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isRx ? 4 : 20),
            bottomRight: Radius.circular(isRx ? 20 : 4),
          ),
          border: Border.all(
            color: isRx
                ? Colors.white10
                : Colors.cyanAccent.withValues(alpha: 0.3),
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
            if (parsedQuestion != null)
              _buildQuestionBubble(parsedQuestion)
            else if (parsedResult != null)
              _buildQuestionResultBubble(parsedResult, questionIndex)
            else
              Text(
                message.content,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionBubble(BleQuestionPrompt prompt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pergunta ${prompt.questionId}',
          style: const TextStyle(
            color: Colors.cyanAccent,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          prompt.question,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: prompt.options
              .map((option) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(
                    '${option.id}: ${option.label}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                );
              })
              .toList(growable: false),
        ),
      ],
    );
  }

  Widget _buildQuestionResultBubble(
    BleQuestionResult result,
    Map<String, BleQuestionPrompt> questionIndex,
  ) {
    final prompt = questionIndex[result.questionId];
    String? optionLabel;
    if (prompt != null && result.answerId != null) {
      for (final option in prompt.options) {
        if (option.id == result.answerId) {
          optionLabel = option.label;
          break;
        }
      }
    }

    if (result.isAnswer) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resposta do relogio',
            style: TextStyle(
              color: Colors.greenAccent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            prompt == null
                ? '${result.questionId} -> ${result.answerId}'
                : '${prompt.question}\n${result.answerId}${optionLabel == null ? '' : ' ($optionLabel)'}',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Erro de pergunta',
          style: TextStyle(
            color: Colors.orangeAccent,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${result.questionId} -> ${_mapQuestionError(result.errorCode ?? 'UNKNOWN')}',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildQuickCommands(bool isConnected) {
    final commands = ['PING', 'LED_ON', 'LED_OFF', 'LED_STATUS'];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 40,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              scrollDirection: Axis.horizontal,
              itemCount: commands.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                return ActionChip(
                  label: Text(
                    commands[index],
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: Colors.white10,
                  labelStyle: TextStyle(
                    color: isConnected ? Colors.white70 : Colors.white30,
                  ),
                  onPressed: isConnected
                      ? () => _sendMessage(commands[index])
                      : null,
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              scrollDirection: Axis.horizontal,
              itemCount: _questionPresets.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index == _questionPresets.length) {
                  return ActionChip(
                    avatar: const Icon(
                      Icons.quiz_outlined,
                      size: 16,
                      color: Colors.black,
                    ),
                    label: const Text(
                      'Nova pergunta',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    backgroundColor: isConnected
                        ? Colors.cyanAccent
                        : Colors.white12,
                    onPressed: isConnected ? _showQuestionComposer : null,
                  );
                }

                final preset = _questionPresets[index];
                return ActionChip(
                  label: Text(
                    preset.label,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: Colors.orange.withValues(alpha: 0.18),
                  labelStyle: TextStyle(
                    color: isConnected ? Colors.orangeAccent : Colors.white30,
                  ),
                  onPressed: isConnected
                      ? () => _sendQuestionPreset(preset)
                      : null,
                );
              },
            ),
          ),
        ],
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
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: isConnected ? _showQuestionComposer : null,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isConnected ? Colors.orangeAccent : Colors.white10,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.quiz_outlined,
                color: isConnected ? Colors.black : Colors.white38,
                size: 20,
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
    final canSend =
        _connectionState == ble.ConnectionState.connected ||
        _messagesController.isWatchConnected;
    if (!canSend) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Dispositivo desconectado. Conecte antes de enviar comandos.',
          ),
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

  Future<void> _sendQuestionPreset(_QuickQuestionPreset preset) async {
    final prompt = BleQuestionPrompt(
      questionId: _nextQuestionId(),
      question: preset.question,
      options: preset.options,
    );
    await _sendQuestionPrompt(prompt);
  }

  Future<void> _sendQuestionPrompt(BleQuestionPrompt prompt) async {
    final payload = buildBleQuestionCommand(prompt);
    if (payload.length > bleQuestionMaxPayloadLength) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pergunta muito grande para o BLE. Reduza texto e alternativas.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await _sendMessage(payload);
  }

  Future<void> _showQuestionComposer() async {
    final canSend =
        _connectionState == ble.ConnectionState.connected ||
        _messagesController.isWatchConnected;
    if (!canSend) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Conecte o dispositivo antes de abrir a pergunta estruturada.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final questionController = TextEditingController();
    final optionLabelControllers = List.generate(
      4,
      (_) => TextEditingController(),
    );
    final optionIdControllers = List.generate(
      4,
      (_) => TextEditingController(),
    );
    String? errorText;

    try {
      final prompt = await showDialog<BleQuestionPrompt>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                backgroundColor: const Color(0xFF161A22),
                title: const Text(
                  'Nova pergunta BLE',
                  style: TextStyle(color: Colors.white),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: questionController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Pergunta',
                          labelStyle: TextStyle(color: Colors.white70),
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (var i = 0; i < 4; i++) ...[
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: optionLabelControllers[i],
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'Opcao ${i + 1}',
                                  labelStyle: const TextStyle(
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: optionIdControllers[i],
                                style: const TextStyle(color: Colors.white),
                                decoration: const InputDecoration(
                                  labelText: 'ID',
                                  labelStyle: TextStyle(color: Colors.white70),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (errorText != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            errorText!,
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () {
                      final question = sanitizeBleQuestionText(
                        questionController.text,
                        maxLength: 44,
                      );
                      final options = <BleQuestionOption>[];

                      for (var i = 0; i < 4; i++) {
                        final label = sanitizeBleQuestionText(
                          optionLabelControllers[i].text,
                          maxLength: 14,
                        );
                        if (label.isEmpty) {
                          continue;
                        }
                        final rawId = optionIdControllers[i].text.trim().isEmpty
                            ? _autoOptionId(label, i)
                            : optionIdControllers[i].text;
                        final id = sanitizeBleQuestionText(
                          rawId,
                          maxLength: 16,
                        ).toLowerCase();
                        options.add(BleQuestionOption(id: id, label: label));
                      }

                      if (question.isEmpty) {
                        setDialogState(() => errorText = 'Informe a pergunta.');
                        return;
                      }
                      if (options.length < bleQuestionMinOptions) {
                        setDialogState(
                          () => errorText =
                              'Informe pelo menos duas alternativas.',
                        );
                        return;
                      }

                      final prompt = BleQuestionPrompt(
                        questionId: _nextQuestionId(),
                        question: question,
                        options: options
                            .take(bleQuestionMaxOptions)
                            .toList(growable: false),
                      );
                      final payload = buildBleQuestionCommand(prompt);
                      if (payload.length > bleQuestionMaxPayloadLength) {
                        setDialogState(() {
                          errorText =
                              'Pergunta muito grande para o BLE. Reduza texto/opcoes.';
                        });
                        return;
                      }

                      Navigator.of(context).pop(prompt);
                    },
                    child: const Text('Enviar'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (prompt != null) {
        await _sendQuestionPrompt(prompt);
      }
    } finally {
      questionController.dispose();
      for (final controller in optionLabelControllers) {
        controller.dispose();
      }
      for (final controller in optionIdControllers) {
        controller.dispose();
      }
    }
  }

  String _nextQuestionId() {
    _questionCounter = (_questionCounter % 999) + 1;
    return 'Q${_questionCounter.toString().padLeft(3, '0')}';
  }

  String _autoOptionId(String label, int index) {
    final base = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (base.isEmpty) {
      return 'op${index + 1}';
    }
    return base.length > 12 ? base.substring(0, 12) : base;
  }

  String _mapQuestionError(String code) {
    return switch (code.toUpperCase()) {
      'TIMEOUT' => 'Tempo esgotado',
      'INVALID' => 'Resposta invalida',
      'INVALID_FORMAT' => 'Formato invalido',
      _ => code,
    };
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
