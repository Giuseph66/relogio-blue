import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/auth/auth_service.dart';
import '../../../../core/theme/app_palette.dart';
import '../../data/profile_service.dart';
import '../../domain/user_profile.dart';

/// Optional profile form. Saving an empty form is valid; nothing is required.
class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _service = ProfileService();
  late final UserProfile _initial = _service.record.value.profile;

  late final Map<String, TextEditingController> _text = {
    for (final field in UserProfile.textLimits.keys)
      field: TextEditingController(text: _initial.text(field) ?? ''),
  };
  late final _birth = TextEditingController(
    text: _initial.birthDate == null ? '' : formatBirthDate(_initial.birthDate!),
  );
  late String? _sex = _initial.sex;
  late final Set<String> _occupations = _initial.occupations.toSet();
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in _text.values) {
      controller.dispose();
    }
    _birth.dispose();
    super.dispose();
  }

  UserProfile get _edited => UserProfile.fromJson({
        for (final entry in _text.entries) entry.key: entry.value.text,
        'birthDate': parseBirthDate(_birth.text),
        'sex': _sex,
        'occupations': _occupations.toList(),
      });

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // Keep what another device may have synced while this form was open.
    await _store(
      UserProfile.merge(
        base: _initial,
        mine: _edited,
        theirs: _service.record.value.profile,
      ),
      'Perfil salvo',
    );
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar perfil?'),
        content: Text(AuthService().account == null
            ? 'Todos os dados do perfil serão apagados deste aparelho.'
            : 'Todos os dados do perfil serão apagados deste aparelho e do servidor. Sua conta continua existindo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: context.palette.danger),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _store(UserProfile.empty, 'Perfil apagado');
  }

  Future<void> _store(UserProfile profile, String message) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.save(profile);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(const SnackBar(
        content: Text('Não foi possível salvar neste aparelho. Tente novamente.'),
      ));
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final hasAccount = AuthService().account != null;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Meu perfil'),
      ),
      bottomNavigationBar: _SaveBar(saving: _saving, onSave: _save),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _formKey,
            // Not a lazy list: off-screen fields must also be validated.
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(name: _text['name']!),
                  const SizedBox(height: 24),
                  _Section(
                    title: 'Você',
                    children: [
                      _field('name', 'Nome', Icons.person_outline_rounded,
                          capitalization: TextCapitalization.words,
                          hints: const [AutofillHints.name]),
                      _birthField(),
                      _Choices(
                        label: 'Sexo',
                        options: UserProfile.sexLabels,
                        selected: {?_sex},
                        // Tapping the selected option clears it.
                        onTap: (key) =>
                            setState(() => _sex = _sex == key ? null : key),
                      ),
                    ],
                  ),
                  _Section(
                    title: 'Onde mora',
                    children: [
                      _field('city', 'Cidade', Icons.location_city_rounded,
                          capitalization: TextCapitalization.words,
                          hints: const [AutofillHints.addressCity]),
                      _field('neighborhood', 'Bairro', Icons.home_outlined,
                          capitalization: TextCapitalization.words),
                    ],
                  ),
                  _Section(
                    title: 'O que você faz',
                    children: [
                      _Choices(
                        label: 'Hoje eu sou ou estou',
                        hint: 'Pode marcar mais de um',
                        options: UserProfile.occupationLabels,
                        selected: _occupations,
                        onTap: (key) => setState(() {
                          if (!_occupations.remove(key)) _occupations.add(key);
                        }),
                      ),
                      _field('work', 'Trabalho', Icons.work_outline_rounded,
                          hint: 'Cargo, área ou empresa'),
                      _field('education', 'Estudos', Icons.school_outlined,
                          hint: 'Curso, escola ou faculdade'),
                    ],
                  ),
                  _Section(
                    title: 'Sobre mim',
                    children: [
                      _field('about', 'Conte um pouco sobre você', null,
                          lines: 4, counter: true),
                    ],
                  ),
                  _PrivacyNote(hasAccount: hasAccount),
                  if (!_initial.isEmpty) ...[
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _saving ? null : _clear,
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      label: const Text('Apagar perfil'),
                      style: TextButton.styleFrom(
                        foregroundColor: context.palette.danger,
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _birthField() => ValueListenableBuilder<TextEditingValue>(
        valueListenable: _birth,
        builder: (context, value, _) {
          final iso = parseBirthDate(value.text);
          final age = iso == null
              ? null
              : UserProfile.fromJson({'birthDate': iso}).ageAt(DateTime.now());
          return TextFormField(
            controller: _birth,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [_BirthDateFormatter()],
            decoration: _fieldDecoration(
              context,
              label: 'Data de nascimento',
              hint: 'dd/mm/aaaa',
              icon: Icons.cake_outlined,
            ).copyWith(
              suffixText: age == null ? null : (age == 1 ? '1 ano' : '$age anos'),
              suffixStyle: TextStyle(
                color: context.palette.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            validator: (value) => value == null ||
                    value.trim().isEmpty ||
                    parseBirthDate(value) != null
                ? null
                : 'Use uma data válida, como 31/01/2004, ou deixe em branco',
          );
        },
      );

  Widget _field(
    String field,
    String label,
    IconData? icon, {
    String? hint,
    int lines = 1,
    bool counter = false,
    TextCapitalization capitalization = TextCapitalization.sentences,
    List<String>? hints,
  }) {
    final limit = UserProfile.textLimits[field]!;
    return TextFormField(
      controller: _text[field],
      minLines: lines,
      maxLines: lines,
      textInputAction: lines > 1 ? null : TextInputAction.next,
      autofillHints: hints,
      textCapitalization: capitalization,
      // UTF-16 length, the unit the server counts in.
      inputFormatters: [_LimitFormatter(limit)],
      buildCounter: counter
          ? (context,
                  {required currentLength, required isFocused, maxLength}) =>
              Text(
                '${_text[field]!.text.length}/$limit',
                style: TextStyle(
                  color: context.palette.textSecondary,
                  fontSize: 12,
                ),
              )
          : null,
      decoration:
          _fieldDecoration(context, label: label, hint: hint, icon: icon),
    );
  }
}

InputDecoration _fieldDecoration(
  BuildContext context, {
  required String label,
  String? hint,
  IconData? icon,
}) {
  final p = context.palette;
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    alignLabelWithHint: true,
    errorMaxLines: 2,
    prefixIcon: icon == null
        ? null
        : Icon(icon, size: 21, color: p.textSecondary),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
    enabledBorder: border(p.textPrimary.withValues(alpha: 0.16)),
    focusedBorder: border(p.accent, 2),
    errorBorder: border(p.danger),
    focusedErrorBorder: border(p.danger, 2),
    floatingLabelStyle: WidgetStateTextStyle.resolveWith(
      (states) => TextStyle(
        color: states.contains(WidgetState.error)
            ? p.danger
            : states.contains(WidgetState.focused)
                ? p.accent
                : p.textSecondary,
      ),
    ),
  );
}

/// Initial and name, following what is typed.
class _Header extends StatelessWidget {
  final TextEditingController name;
  const _Header({required this.name});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: name,
      builder: (context, value, _) {
        final text = value.text.trim();
        return Row(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.accent.withValues(alpha: 0.12),
                ),
                child: text.isEmpty
                    ? Icon(Icons.person_rounded, size: 32, color: p.accent)
                    : Text(
                        text.characters.first.toUpperCase(),
                        style: TextStyle(
                          color: p.accent,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text.isEmpty ? 'Conte quem é você' : text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tudo é opcional. Preencha só o que quiser.',
                    style: TextStyle(color: p.textSecondary, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 10),
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: p.border),
            ),
            // Ink of the chips must paint above the card color.
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 16,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Choices extends StatelessWidget {
  final String label;
  final String? hint;
  final Map<String, String> options;
  final Set<String> selected;
  final ValueChanged<String> onTap;

  const _Choices({
    required this.label,
    required this.options,
    required this.selected,
    required this.onTap,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: p.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (hint != null)
          Text(hint!, style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in options.entries)
              FilterChip(
                label: Text(entry.value),
                selected: selected.contains(entry.key),
                onSelected: (_) => onTap(entry.key),
                showCheckmark: true,
                checkmarkColor: p.accent,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                backgroundColor: Colors.transparent,
                selectedColor: p.accent.withValues(alpha: 0.12),
                shape: const StadiumBorder(),
                side: BorderSide(
                  color: selected.contains(entry.key)
                      ? p.accent
                      : p.textPrimary.withValues(alpha: 0.16),
                ),
                labelStyle: TextStyle(
                  color: selected.contains(entry.key)
                      ? p.accent
                      : p.textPrimary,
                  fontSize: 14,
                  fontWeight: selected.contains(entry.key)
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  final bool hasAccount;
  const _PrivacyNote({required this.hasAccount});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, size: 18, color: p.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasAccount
                  ? 'Seus dados ficam neste aparelho e na sua conta no servidor, para aparecer também no site. Não são publicados nem ligados às suas respostas, e você pode apagar quando quiser.'
                  : 'Sem conta, seus dados ficam só neste aparelho. Se você entrar numa conta que ainda não tem perfil, eles passam para ela. Não são publicados nem ligados às suas respostas, e você pode apagar quando quiser.',
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Always reachable, however long the form is.
class _SaveBar extends StatelessWidget {
  final bool saving;
  final VoidCallback onSave;
  const _SaveBar({required this.saving, required this.onSave});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.card,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 608),
              child: FilledButton(
                onPressed: saving ? null : onSave,
                style: FilledButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: p.onAccent,
                  minimumSize: const Size.fromHeight(52),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(saving ? 'Salvando…' : 'Salvar'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LimitFormatter extends TextInputFormatter {
  final int max;
  _LimitFormatter(this.max);

  @override
  TextEditingValue formatEditUpdate(
          TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.text.length <= max ? newValue : oldValue;
}

/// Inserts the slashes of dd/mm/aaaa while typing.
class _BirthDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 8) digits = digits.substring(0, 8);
    final text = [
      digits.substring(0, digits.length.clamp(0, 2)),
      if (digits.length > 2) digits.substring(2, digits.length.clamp(2, 4)),
      if (digits.length > 4) digits.substring(4),
    ].join('/');
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
