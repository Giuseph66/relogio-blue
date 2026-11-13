import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/auth/auth_service.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../ble_old/presentation/controllers/messages_controller.dart';
import '../../../history/domain/entities/watch_response.dart';
import '../../../location_tracker/presentation/controllers/location_tracker_controller.dart';
import '../../../../core/theme/app_palette.dart';

/// "Perfil" tab: account info, activity stats, watch status and shortcuts.
///
/// Embedded in MainScreen (no AppBar of its own). [refresh] is bumped by the
/// MainScreen every time the tab is opened so stats are always current.
class ProfilePage extends StatefulWidget {
  final ValueListenable<int>? refresh;

  const ProfilePage({super.key, this.refresh});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final DependencyInjection _di = DependencyInjection();
  final MessagesController _messages = MessagesController();
  late final LocationTrackerController _tracker;

  StreamSubscription<TickStatus>? _tickSub;
  int _answered = 0;
  int _pendingSync = 0;
  int _unanswered = 0;

  @override
  void initState() {
    super.initState();
    _tracker = _di.locationTrackerController;
    _tracker.addListener(_onChanged);
    widget.refresh?.addListener(_loadResponses);
    _tickSub = _messages.tickStatus.listen((_) => _onChanged());
    _loadResponses();
  }

  @override
  void dispose() {
    _tracker.removeListener(_onChanged);
    widget.refresh?.removeListener(_loadResponses);
    _tickSub?.cancel();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadResponses() async {
    try {
      final all = await _di.watchResponseRepository.getAll();
      if (!mounted) return;
      setState(() {
        _answered =
            all.where((r) => r.questionStatus == QuestionStatus.answered).length;
        _unanswered = all.length - _answered;
        _pendingSync = all
            .where((r) =>
                r.questionStatus == QuestionStatus.answered &&
                r.syncStatus != SyncStatus.synced)
            .length;
      });
    } catch (_) {
      // Stats are informative only; keep previous values on failure.
    }
  }

  Future<void> _logout() async {
    await AuthService().logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();

    return RefreshIndicator(
      color: context.palette.accent,
      onRefresh: _loadResponses,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: auth.isAuthenticatedNotifier,
            builder: (context, isAuth, _) => _AccountCard(
              email: isAuth ? auth.email : 'Visitante',
              authenticated: isAuth,
            ),
          ),
          const SizedBox(height: 24),
          const _SectionTitle('Atividade'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.place_rounded,
                  value: _tracker.locations.length,
                  label: 'Locais',
                  color: context.palette.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  icon: Icons.directions_walk_rounded,
                  value: _tracker.visits.length,
                  label: 'Visitas',
                  color: context.palette.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  icon: Icons.task_alt_rounded,
                  value: _answered,
                  label: 'Respostas',
                  color: context.palette.success,
                ),
              ),
            ],
          ),
          if (_pendingSync > 0 || _unanswered > 0) ...[
            const SizedBox(height: 12),
            _InfoBanner(
              text: [
                if (_unanswered > 0) '$_unanswered pergunta(s) sem resposta',
                if (_pendingSync > 0) '$_pendingSync resposta(s) aguardando envio',
              ].join(' · '),
            ),
          ],
          const SizedBox(height: 24),
          const _SectionTitle('Relógio'),
          const SizedBox(height: 12),
          _WatchStatusCard(
            online: _messages.isWatchOnline,
            connected: _messages.isWatchConnected,
            onTap: () => Navigator.pushNamed(context, AppRoutes.connect),
          ),
          const SizedBox(height: 24),
          const _SectionTitle('Atalhos'),
          const SizedBox(height: 12),
          _ShortcutTile(
            icon: Icons.history_rounded,
            title: 'Histórico de respostas',
            subtitle: 'Perguntas enviadas e respostas do relógio',
            onTap: () async {
              await Navigator.pushNamed(context, AppRoutes.history);
              _loadResponses();
            },
          ),
          _ShortcutTile(
            icon: Icons.bookmarks_outlined,
            title: 'Catálogo de locais',
            subtitle: 'Gerenciar locais salvos e visitas',
            onTap: () => Navigator.pushNamed(context, AppRoutes.catalog),
          ),
          const SizedBox(height: 24),
          ValueListenableBuilder<bool>(
            valueListenable: auth.isAuthenticatedNotifier,
            builder: (context, isAuth, _) => SizedBox(
              height: 52,
              child: isAuth
                  ? OutlinedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Sair da conta'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.palette.danger,
                        side: BorderSide(
                          color: context.palette.danger.withValues(alpha: 0.4),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: () => Navigator.pushReplacementNamed(
                        context,
                        AppRoutes.login,
                      ),
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Fazer login'),
                      style: FilledButton.styleFrom(
                        backgroundColor: context.palette.accent,
                        foregroundColor: context.palette.onAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Pieces ──────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: context.palette.accent,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
      ),
    );
  }
}

BoxDecoration _cardDecoration(BuildContext context, {Color? border}) => BoxDecoration(
      color: context.palette.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: border ?? context.palette.textPrimary.withValues(alpha: 0.08)),
    );

class _AccountCard extends StatelessWidget {
  final String email;
  final bool authenticated;

  const _AccountCard({required this.email, required this.authenticated});

  @override
  Widget build(BuildContext context) {
    final statusColor = authenticated ? context.palette.success : context.palette.textPrimary.withValues(alpha: 0.38);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(context,
        border: context.palette.accent.withValues(alpha: 0.2),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.palette.accent.withValues(alpha: 0.1),
              border: Border.all(
                color: context.palette.accent.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: Text(
              email.isNotEmpty ? email[0].toUpperCase() : '?',
              style: TextStyle(
                color: context.palette.accent,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  authenticated ? 'Administrador' : 'Não conectado',
                  style: TextStyle(
                    color: context.palette.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.palette.textPrimary.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      authenticated ? 'Sessão ativa' : 'Sem sessão',
                      style: TextStyle(color: statusColor, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final int value;
  final String label;
  final Color color;

  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: _cardDecoration(context),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: TextStyle(
              color: context.palette.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: context.palette.textPrimary.withValues(alpha: 0.55),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String text;
  const _InfoBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.palette.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: context.palette.warning, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: context.palette.warning, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _WatchStatusCard extends StatelessWidget {
  final bool online;
  final bool connected;
  final VoidCallback onTap;

  const _WatchStatusCard({
    required this.online,
    required this.connected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (color, title, subtitle) = online
        ? (context.palette.success, 'Relógio online', 'Recebendo perguntas em tempo real')
        : connected
            ? (context.palette.caution, 'Conectado', 'Aguardando sinal do relógio')
            : (context.palette.textPrimary.withValues(alpha: 0.38), 'Nenhum relógio', 'Opcional · toque para conectar');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(context),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.watch_rounded, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: context.palette.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: context.palette.textPrimary.withValues(alpha: 0.55),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: context.palette.textPrimary.withValues(alpha: 0.38)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ShortcutTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(context),
            child: Row(
              children: [
                Icon(icon, color: context.palette.accent),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: context.palette.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: context.palette.textPrimary.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: context.palette.textPrimary.withValues(alpha: 0.38)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
