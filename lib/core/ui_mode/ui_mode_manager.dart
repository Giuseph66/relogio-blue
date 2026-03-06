import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UiModeManager {
  static final UiModeManager _instance = UiModeManager._internal();
  factory UiModeManager() => _instance;
  UiModeManager._internal();

  static const String _keyUseModernUi = 'use_modern_ui';
  
  // ValueNotifier to allow UI components to listen for changes
  final ValueNotifier<bool> useModernUiNotifier = ValueNotifier<bool>(true);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    useModernUiNotifier.value = prefs.getBool(_keyUseModernUi) ?? true;
  }

  bool get isModernUi => useModernUiNotifier.value;

  Future<void> toggleUiMode() async {
    final prefs = await SharedPreferences.getInstance();
    final newValue = !useModernUiNotifier.value;
    await prefs.setBool(_keyUseModernUi, newValue);
    useModernUiNotifier.value = newValue;
  }
}
