import 'package:flutter/material.dart';

import '../../domain/entities/watch_response.dart';
import '../controllers/history_controller.dart';

class HistoryPage extends StatefulWidget {
  final HistoryController controller;

  const HistoryPage({super.key, required this.controller});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.load();
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Color _syncColor(SyncStatus s) => switch (s) {
        SyncStatus.pending => Colors.orangeAccent,
        SyncStatus.synced => Colors.greenAccent,
        SyncStatus.failed => Colors.redAccent,
      };

  IconData _syncIcon(SyncStatus s) => switch (s) {
        SyncStatus.pending => Icons.schedule,
        SyncStatus.synced => Icons.cloud_done_rounded,
        SyncStatus.failed => Icons.cloud_off_rounded,
      };

  String _syncLabel(SyncStatus s) => switch (s) {
        SyncStatus.pending => 'Pendente',
        SyncStatus.synced => 'Sincronizado',
        SyncStatus.failed => 'Falhou',
      };

  Color _questionColor(QuestionStatus s) => switch (s) {
        QuestionStatus.watchOffline => Colors.grey,
        QuestionStatus.questionSent => Colors.amberAccent,
        QuestionStatus.answered => Colors.cyanAccent,
      };

  IconData _questionIcon(QuestionStatus s) => switch (s) {
        QuestionStatus.watchOffline => Icons.watch_off_rounded,
        QuestionStatus.questionSent => Icons.watch_rounded,
        QuestionStatus.answered => Icons.check_circle_rounded,
      };

  String _questionLabel(QuestionStatus s) => switch (s) {
        QuestionStatus.watchOffline => 'Relógio offline',
        QuestionStatus.questionSent => 'Enviada, sem resposta',
        QuestionStatus.answered => 'Respondida',
      };

  String _formatDateTime(DateTime dt) {
    final d = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    final t = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$d $t';
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Visitas'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (ctrl.responses.isNotEmpty)
            IconButton(
              tooltip: 'Limpar histórico',
              icon: const Icon(Icons.delete_sweep_rounded),
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: ctrl.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ctrl.responses.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: ctrl.load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: ctrl.responses.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _buildCard(ctrl.responses[i]),
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_rounded, size: 64, color: Colors.white24),
          SizedBox(height: 16),
          Text('Nenhuma visita ainda.', style: TextStyle(color: Colors.white54, fontSize: 16)),
          SizedBox(height: 8),
          Text(
            'Os registros de visita aparecerão aqui.',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(WatchResponse r) {
    final qColor = _questionColor(r.questionStatus);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _showDetail(r),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header ───────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.locationName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // Question status badge
                _badge(
                  icon: _questionIcon(r.questionStatus),
                  label: _questionLabel(r.questionStatus),
                  color: qColor,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // ─── Question text ─────────────────────────────────────────
            if (r.questionText != null)
              _infoRow(Icons.help_outline_rounded, r.questionText!),
            if (r.answerId != null && r.answerId!.isNotEmpty) ...[
              const SizedBox(height: 4),
              _infoRow(Icons.check_circle_outline_rounded, 'Resposta: ${r.answerLabel}'),
            ],
            const SizedBox(height: 8),
            // ─── Footer ────────────────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.access_time, size: 13, color: Colors.white38),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _formatDateTime(r.timestamp),
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
                // Sync status mini badge
                _badge(
                  icon: _syncIcon(r.syncStatus),
                  label: _syncLabel(r.syncStatus),
                  color: _syncColor(r.syncStatus),
                  small: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge({
    required IconData icon,
    required String label,
    required Color color,
    bool small = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 6 : 10, vertical: small ? 2 : 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: small ? 11 : 13),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: small ? 10 : 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white54),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ─── Detail bottom sheet ───────────────────────────────────────────────────

  void _showDetail(WatchResponse r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _DetailSheet(
        response: r,
        controller: widget.controller,
        questionLabel: _questionLabel(r.questionStatus),
        questionColor: _questionColor(r.questionStatus),
        questionIcon: _questionIcon(r.questionStatus),
        syncLabel: _syncLabel(r.syncStatus),
        syncColor: _syncColor(r.syncStatus),
        syncIcon: _syncIcon(r.syncStatus),
        formatDateTime: _formatDateTime,
      ),
    );
  }

  // ─── Clear confirm ─────────────────────────────────────────────────────────

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Limpar histórico', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Todos os registros locais serão removidos. Continuar?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.clearAll();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Detail sheet widget
// ─────────────────────────────────────────────────────────────────────────────

class _DetailSheet extends StatefulWidget {
  final WatchResponse response;
  final HistoryController controller;
  final String questionLabel;
  final Color questionColor;
  final IconData questionIcon;
  final String syncLabel;
  final Color syncColor;
  final IconData syncIcon;
  final String Function(DateTime) formatDateTime;

  const _DetailSheet({
    required this.response,
    required this.controller,
    required this.questionLabel,
    required this.questionColor,
    required this.questionIcon,
    required this.syncLabel,
    required this.syncColor,
    required this.syncIcon,
    required this.formatDateTime,
  });

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  bool _busy = false;
  String? _feedback;

  Future<void> _doResend() async {
    setState(() { _busy = true; _feedback = null; });
    final msg = await widget.controller.resendQuestion(widget.response);
    if (!mounted) return;
    // On success, close the sheet – the list will rebuild with fresh data.
    // On failure/pending, show inline feedback.
    if (msg.startsWith('Pergunta reenviada')) {
      Navigator.of(context).pop();
    } else {
      setState(() { _busy = false; _feedback = msg; });
    }
  }

  Future<void> _doSync() async {
    setState(() { _busy = true; _feedback = null; });
    final msg = await widget.controller.retrySync(widget.response);
    if (mounted) setState(() { _busy = false; _feedback = msg; });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.response;

    final canResend = r.questionStatus != QuestionStatus.answered &&
        r.questionCommand != null &&
        r.questionCommand!.isNotEmpty;

    final canSync = r.questionStatus == QuestionStatus.answered &&
        r.syncStatus != SyncStatus.synced;

    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Location
          Text(
            r.locationName,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.formatDateTime(r.timestamp),
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
          const Divider(color: Colors.white12, height: 28),

          // Question status
          _row(
            icon: widget.questionIcon,
            color: widget.questionColor,
            label: 'Status da pergunta',
            value: widget.questionLabel,
          ),
          const SizedBox(height: 12),

          // Question text
          if (r.questionText != null) ...[
            _row(
              icon: Icons.help_outline_rounded,
              color: Colors.white54,
              label: 'Pergunta',
              value: r.questionText!,
            ),
            const SizedBox(height: 12),
          ],

          // Answer
          _row(
            icon: Icons.check_circle_outline_rounded,
            color: r.answerId != null ? Colors.cyanAccent : Colors.white24,
            label: 'Resposta do relógio',
            value: r.answerLabel ?? '—',
          ),
          const SizedBox(height: 12),

          // Sync status
          _row(
            icon: widget.syncIcon,
            color: widget.syncColor,
            label: 'Sincronização com servidor',
            value: widget.syncLabel,
          ),

          const SizedBox(height: 24),

          // Feedback message
          if (_feedback != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _feedback!,
                style: const TextStyle(color: Colors.cyanAccent, fontSize: 13),
              ),
            ),

          // Action buttons
          if (canResend || canSync)
            Row(
              children: [
                if (canResend)
                  Expanded(
                    child: _actionButton(
                      icon: Icons.send_rounded,
                      label: 'Reenviar Pergunta',
                      color: Colors.amberAccent,
                      onPressed: _busy ? null : _doResend,
                    ),
                  ),
                if (canResend && canSync) const SizedBox(width: 12),
                if (canSync)
                  Expanded(
                    child: _actionButton(
                      icon: Icons.cloud_upload_rounded,
                      label: 'Sincronizar',
                      color: Colors.greenAccent,
                      onPressed: _busy ? null : _doSync,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: Colors.black87),
      label: Text(label, style: const TextStyle(color: Colors.black87, fontSize: 13)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
