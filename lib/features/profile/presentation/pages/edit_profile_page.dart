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
      appBar: AppBar(title: const Text('Meu perfil')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: _formKey,
              // Not a lazy list: off-screen fields must also be validated.
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Nada aqui é obrigatório. Preencha só o que quiser.',
                      style: TextStyle(color: context.palette.textSecondary),
                    ),
                    const SizedBox(height: 20),
                    _field('name', 'Nome', hints: const [AutofillHints.name]),
                    TextFormField(
                      controller: _birth,
                      keyboardType: TextInputType.number,
                      inputFormatters: [_BirthDateFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Data de nascimento',
                        hintText: 'dd/mm/aaaa',
                        helperText: 'Usada para mostrar a sua idade',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => value == null ||
                              value.trim().isEmpty ||
                              parseBirthDate(value) != null
                          ? null
                          : 'Use uma data válida, como 31/01/2004, ou deixe em branco',
                    ),
                    const SizedBox(height: 16),
                    _label('Sexo'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final entry in UserProfile.sexLabels.entries)
                          ChoiceChip(
                            label: Text(entry.value),
                            selected: _sex == entry.key,
                            // Tapping the selected option clears it.
                            onSelected: (selected) => setState(
                                () => _sex = selected ? entry.key : null),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _field('city', 'Cidade',
                        hints: const [AutofillHints.addressCity]),
                    _field('neighborhood', 'Bairro'),
                    _label('O que você faz hoje'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final entry in UserProfile.occupationLabels.entries)
                          FilterChip(
                            label: Text(entry.value),
                            selected: _occupations.contains(entry.key),
                            onSelected: (selected) => setState(() => selected
                                ? _occupations.add(entry.key)
                                : _occupations.remove(entry.key)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _field('work', 'Com o que trabalha',
                        hint: 'Cargo, área ou empresa'),
                    _field('education', 'Estudos',
                        hint: 'Curso, escola ou faculdade'),
                    _field('about', 'Sobre mim', lines: 3),
                    Text(
                      hasAccount
                          ? 'Seus dados ficam neste aparelho e na sua conta no servidor, para aparecer também no site. Não são publicados nem ligados às suas respostas, e você pode apagar quando quiser.'
                          : 'Sem conta, seus dados ficam só neste aparelho. Se você entrar numa conta que ainda não tem perfil, eles passam para ela. Não são publicados nem ligados às suas respostas, e você pode apagar quando quiser.',
                      style: TextStyle(
                        color: context.palette.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: context.palette.accent,
                          foregroundColor: context.palette.onAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(_saving ? 'Salvando…' : 'Salvar'),
                      ),
                    ),
                    if (!_initial.isEmpty) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _saving ? null : _clear,
                        style: TextButton.styleFrom(
                          foregroundColor: context.palette.danger,
                        ),
                        child: const Text('Apagar perfil'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            color: context.palette.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _field(
    String field,
    String label, {
    String? hint,
    int lines = 1,
    List<String>? hints,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          controller: _text[field],
          maxLines: lines,
          autofillHints: hints,
          textCapitalization: TextCapitalization.sentences,
          // UTF-16 length, the unit the server counts in.
          inputFormatters: [_LimitFormatter(UserProfile.textLimits[field]!)],
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
      );
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
