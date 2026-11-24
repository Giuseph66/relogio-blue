import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/auth/account_api.dart';
import '../../../../core/auth/auth_service.dart';
import '../../../../core/di/dependency_injection.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../ble_old/presentation/controllers/messages_controller.dart';
import '../../../history/domain/entities/watch_response.dart';
import '../../../location_tracker/presentation/controllers/location_tracker_controller.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/settings_tiles.dart';
import '../../data/profile_service.dart';
import '../../domain/user_profile.dart';
import 'edit_profile_page.dart';

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

  final Listenable _accountChanges = Listenable.merge([
    AuthService().isAuthenticatedNotifier,
    AuthService().accountNotifier,
    ProfileService().record,
  ]);

  StreamSubscription<TickStatus>? _tickSub;
  int _answered = 0;
  int _pendingSync = 0;
  int _unanswered = 0;

  @override
  void initState() {
    super.initState();
    _tracker = _di.locationTrackerController;
    _tracker.addListener(_onChanged);
    widget.refresh?.addListener(_onRefresh);
    _accountChanges.addListener(_onChanged);
    _tickSub = _messages.tickStatus.listen((_) => _onChanged());
    _loadResponses();
  }

  @override
  void dispose() {
    _tracker.removeListener(_onChanged);
    widget.refresh?.removeListener(_onRefresh);
    _accountChanges.removeListener(_onChanged);
    _tickSub?.cancel();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onRefresh() {
    _loadResponses();
    ProfileService().sync();
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
                r.syncStatus != SyncStatus.synced &&
                r.syncStatus != SyncStatus.rejected)
            .length;
      });
    } catch (_) {
      // Stats are informative only; keep previous values on failure.
    }
  }

  Future<void> _logout() async {
    // Best effort: whatever cannot be sent now waits for the next login.
    await ProfileService().sync();
    try {
      await AuthService().logout();
    } catch (_) {
      _toast('Não foi possível sair agora. Confira a conexão e tente novamente.');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editProfile() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const EditProfilePage()),
      );

  void _openLogin({bool register = false}) => Navigator.pushNamed(
        context,
        AppRoutes.login,
        arguments: register ? AppRoutes.registerArgument : null,
      );

  Future<void> _deleteAccount() async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (password == null) return;
    try {
      await ProfileService().deleteAccount(password);
    } on AccountException catch (error) {
      _toast(error.message);
      return;
    } catch (_) {
      _toast('Sem conexão com o servidor. A conta não foi excluída.');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    final account = auth.account;
    final signedIn = auth.isAuthenticated || account != null;
    final record = ProfileService().record.value;
    final name = record.profile.name;

    return RefreshIndicator(
      color: context.palette.accent,
      onRefresh: () async {
        await Future.wait([_loadResponses(), ProfileService().sync()]);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          _AccountCard(
            title: name ??
                (auth.isAuthenticated
                    ? 'Administrador'
                    : account != null
                        ? 'Minha conta'
                        : 'Visitante'),
            subtitle: auth.isAuthenticated
                ? auth.email
                : account?.email ?? 'Usando sem conta',
            status: auth.isAuthenticated
                ? 'Administrador'
                : account != null
                    ? (record.dirty
                        ? 'Alterações aguardando conexão'
                        : 'Conta conectada')
                    : 'Perfil salvo só neste aparelho',
            authenticated: signedIn,
            pending: record.dirty,
          ),
          if (auth.sessionExpired) ...[
            const SizedBox(height: 12),
            const _InfoBanner(
              text: 'Sua sessão expirou. Entre novamente para ver e sincronizar o perfil da sua conta.',
            ),
          ],
          const SizedBox(height: 24),
          const _SectionTitle('Sobre você'),
          const SizedBox(height: 12),
          _ProfileCard(profile: record.profile, onEdit: _editProfile),
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
          if (signedIn) ...[
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
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
              ),
            ),
            if (account != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _deleteAccount,
                style: TextButton.styleFrom(
                  foregroundColor: context.palette.textSecondary,
                ),
                child: const Text('Excluir minha conta'),
              ),
            ],
          ] else ...[
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _openLogin,
                icon: const Icon(Icons.login_rounded),
                label: const Text('Entrar'),
                style: FilledButton.styleFrom(
                  backgroundColor: context.palette.accent,
                  foregroundColor: context.palette.onAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _openLogin(register: true),
              child: const Text('Criar conta (opcional)'),
            ),
            Text(
              'Com uma conta, o mesmo perfil aparece no celular e no site.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.palette.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
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
  final String title;
  final String subtitle;
  final String status;
  final bool authenticated;
  final bool pending;

  const _AccountCard({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.authenticated,
    required this.pending,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = pending ? context.palette.caution : authenticated ? context.palette.success : context.palette.textSecondary;
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
              title.characters.first.toUpperCase(),
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
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.palette.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
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
                    Expanded(
                      child: Text(
                        status,
                        style: TextStyle(color: statusColor, fontSize: 12),
                      ),
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

/// Filled-in fields, or an invitation to fill them. Everything is optional.
class _ProfileCard extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback onEdit;

  const _ProfileCard({required this.profile, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    if (profile.isEmpty) {
      return SettingsSection(
        footer: 'Opcional. Você pode usar o aplicativo sem preencher nada.',
        children: [
          SettingsTile(
            icon: Icons.person_add_alt_1_outlined,
            title: 'Preencher meu perfil',
            subtitle: 'Nome, idade, onde mora, o que faz…',
            onTap: onEdit,
          ),
        ],
      );
    }

    final birth = profile.birthDate;
    final age = profile.ageAt(DateTime.now());
    final place = [profile.text('neighborhood'), profile.text('city')]
        .nonNulls
        .join(', ');
    final occupation = profile.occupations
        .map((o) => UserProfile.occupationLabels[o])
        .join(', ');

    return SettingsSection(
      children: [
        if (birth != null)
          _tile(
            icon: Icons.cake_outlined,
            value: age == null ? formatBirthDate(birth) : '$age anos',
            label: 'Idade',
          ),
        if (profile.sex != null)
          _tile(
            icon: Icons.person_outline_rounded,
            value: UserProfile.sexLabels[profile.sex]!,
            label: 'Sexo',
          ),
        if (place.isNotEmpty)
          _tile(
            icon: Icons.home_outlined,
            value: place,
            label: 'Onde mora',
          ),
        if (occupation.isNotEmpty)
          _tile(
            icon: Icons.badge_outlined,
            value: occupation,
            label: 'Ocupação',
          ),
        if (profile.text('work') case final work?)
          _tile(
            icon: Icons.work_outline_rounded,
            value: work,
            label: 'Trabalho',
          ),
        if (profile.text('education') case final education?)
          _tile(
            icon: Icons.school_outlined,
            value: education,
            label: 'Estudos',
          ),
        if (profile.text('about') case final about?)
          _tile(
            icon: Icons.notes_rounded,
            value: about,
            label: 'Sobre mim',
          ),
        MergeSemantics(
          child: SettingsTile(
            icon: Icons.edit_outlined,
            title: 'Editar perfil',
            onTap: onEdit,
          ),
        ),
      ],
    );
  }

  /// Read as one item per field by screen readers.
  Widget _tile({
    required IconData icon,
    required String value,
    required String label,
  }) =>
      Semantics(
        container: true,
        label: '$label: $value',
        excludeSemantics: true,
        child: SettingsTile(icon: icon, title: value, subtitle: label),
      );
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Excluir conta?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sua conta e seu perfil serão apagados do servidor e deste aparelho. Não dá para desfazer.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirme sua senha'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _password.text),
          style: TextButton.styleFrom(foregroundColor: context.palette.danger),
          child: const Text('Excluir'),
        ),
      ],
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
