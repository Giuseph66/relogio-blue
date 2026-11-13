import 'package:flutter/material.dart';

/// Semantic colors of the app. Screens must use these (via `context.palette`)
/// instead of hard-coded `Colors.*`, so light and dark themes both work.
///
/// Light values are darker variants chosen for WCAG AA contrast on white
/// (e.g. accent #00838F ≈ 4.9:1, whereas cyanAccent would be ≈ 1.2:1).
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  /// Brand color for primary actions, selected states and links.
  final Color accent;

  /// Text/icon color on top of [accent].
  final Color onAccent;

  final Color success;
  final Color warning; // orange: locations, attention
  final Color caution; // amber: in-progress / waiting
  final Color danger;
  final Color info; // purple: advanced / diagnostics

  /// Main text color. Use `.withValues(alpha:)` for secondary text, borders
  /// and subtle fills — works in both themes.
  final Color textPrimary;

  final Color scaffold;

  /// Cards, grouped lists, nav bar.
  final Color card;

  /// Dialogs, sheets, floating cards.
  final Color cardElevated;

  const AppPalette({
    required this.accent,
    required this.onAccent,
    required this.success,
    required this.warning,
    required this.caution,
    required this.danger,
    required this.info,
    required this.textPrimary,
    required this.scaffold,
    required this.card,
    required this.cardElevated,
  });

  static const dark = AppPalette(
    accent: Color(0xFF18FFFF), // cyanAccent
    onAccent: Colors.black,
    success: Color(0xFF69F0AE),
    warning: Color(0xFFFFAB40),
    caution: Color(0xFFFFD740),
    danger: Color(0xFFFF5252),
    info: Color(0xFFE040FB),
    textPrimary: Colors.white,
    scaffold: Color(0xFF0A0A0A),
    card: Color(0xFF151515),
    cardElevated: Color(0xFF1E1E1E),
  );

  static const light = AppPalette(
    accent: Color(0xFF00838F),
    onAccent: Colors.white,
    success: Color(0xFF2E7D32),
    warning: Color(0xFFD84315),
    caution: Color(0xFF8D6E00),
    danger: Color(0xFFC62828),
    info: Color(0xFF7B1FA2),
    textPrimary: Color(0xFF111418),
    scaffold: Color(0xFFF2F4F7),
    card: Colors.white,
    cardElevated: Colors.white,
  );

  /// Secondary text (descriptions, values).
  Color get textSecondary => textPrimary.withValues(alpha: 0.62);

  /// Tertiary text (captions, hints, chevrons).
  Color get textMuted => textPrimary.withValues(alpha: 0.45);

  /// Hairline borders / dividers.
  Color get border => textPrimary.withValues(alpha: 0.08);

  @override
  AppPalette copyWith({
    Color? accent,
    Color? onAccent,
    Color? success,
    Color? warning,
    Color? caution,
    Color? danger,
    Color? info,
    Color? textPrimary,
    Color? scaffold,
    Color? card,
    Color? cardElevated,
  }) {
    return AppPalette(
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      caution: caution ?? this.caution,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      textPrimary: textPrimary ?? this.textPrimary,
      scaffold: scaffold ?? this.scaffold,
      card: card ?? this.card,
      cardElevated: cardElevated ?? this.cardElevated,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      caution: Color.lerp(caution, other.caution, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      scaffold: Color.lerp(scaffold, other.scaffold, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardElevated: Color.lerp(cardElevated, other.cardElevated, t)!,
    );
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;

  bool get isDarkTheme => Theme.of(this).brightness == Brightness.dark;
}
