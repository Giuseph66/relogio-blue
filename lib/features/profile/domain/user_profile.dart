import 'package:flutter/foundation.dart';

/// Optional personal profile. A field that was not filled in is simply absent.
///
/// Keys, limits and enums mirror `server/src/services/profile-validator.js`.
@immutable
class UserProfile {
  static const textLimits = {
    'name': 80,
    'neighborhood': 80,
    'city': 80,
    'work': 120,
    'education': 120,
    'about': 300,
  };

  static const sexLabels = {
    'feminino': 'Feminino',
    'masculino': 'Masculino',
    'outro': 'Outro',
    'nao_informar': 'Prefiro não informar',
  };

  static const occupationLabels = {
    'estudante': 'Estudante',
    'empregado': 'Trabalho (empregado)',
    'autonomo': 'Autônomo',
    'desempregado': 'Sem trabalho no momento',
    'aposentado': 'Aposentado',
    'do_lar': 'Cuido da casa',
  };

  final Map<String, Object> _values;

  const UserProfile._(this._values);
  static const empty = UserProfile._({});

  /// Normalizes exactly like the server, so both sides compare equal.
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final values = <String, Object>{};
    for (final field in textLimits.keys) {
      final value = json[field];
      if (value is String && value.trim().isNotEmpty) {
        values[field] = value.trim();
      }
    }
    final birth = json['birthDate'];
    if (birth is String && DateTime.tryParse(birth) != null) {
      values['birthDate'] = birth;
    }
    if (sexLabels.containsKey(json['sex'])) {
      values['sex'] = json['sex'] as String;
    }
    final occupations = json['occupations'];
    if (occupations is List) {
      final selected =
          occupationLabels.keys.where(occupations.contains).toList();
      if (selected.isNotEmpty) values['occupations'] = selected;
    }
    return UserProfile._(values);
  }

  Map<String, dynamic> toJson() => Map.of(_values);

  bool get isEmpty => _values.isEmpty;

  String? text(String field) => _values[field] as String?;
  String? get name => text('name');
  String? get sex => text('sex');
  List<String> get occupations =>
      (_values['occupations'] as List?)?.cast<String>() ?? const [];

  DateTime? get birthDate {
    final value = text('birthDate');
    return value == null ? null : DateTime.parse(value);
  }

  int? ageAt(DateTime now) {
    final birth = birthDate;
    if (birth == null) return null;
    final hadBirthday = now.month > birth.month ||
        (now.month == birth.month && now.day >= birth.day);
    final age = now.year - birth.year - (hadBirthday ? 0 : 1);
    return age < 0 ? null : age;
  }

  /// Field-by-field three-way merge: what [mine] changed since [base] wins,
  /// everything else comes from [theirs].
  static UserProfile merge({
    required UserProfile base,
    required UserProfile mine,
    required UserProfile theirs,
  }) {
    final values = Map.of(theirs._values);
    for (final field in {...base._values.keys, ...mine._values.keys}) {
      final value = mine._values[field];
      if (_same(value, base._values[field])) continue;
      if (value == null) {
        values.remove(field);
      } else {
        values[field] = value;
      }
    }
    return UserProfile._(values);
  }

  static bool _same(Object? a, Object? b) =>
      a is List && b is List ? listEquals(a, b) : a == b;

  @override
  bool operator ==(Object other) =>
      other is UserProfile &&
      _values.length == other._values.length &&
      _values.keys.every((k) => _same(_values[k], other._values[k]));

  @override
  int get hashCode => Object.hashAllUnordered(_values.keys);
}

/// Parses "dd/mm/aaaa" into ISO "yyyy-mm-dd". Null when it is not a real,
/// past date.
String? parseBirthDate(String input, {DateTime? now}) {
  final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(input.trim());
  if (match == null) return null;
  final day = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final year = int.parse(match[3]!);
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  if (year < 1900 || date.isAfter(now ?? DateTime.now())) return null;
  return '${match[3]}-${match[2]}-${match[1]}';
}

String formatBirthDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';
