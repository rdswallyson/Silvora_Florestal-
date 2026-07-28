import 'package:flutter/material.dart';

/// Estado global simples do app (sem backend, apenas protótipo).
class AppState extends ChangeNotifier {
  static final AppState instance = AppState._();
  AppState._();

  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  String userName = 'João Pereira';
  String userRole = 'Gerente';

  void toggleTheme() {
    _themeMode =
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  void setTheme(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  bool get isDark => _themeMode == ThemeMode.dark;

  void updateUserName(String name) {
    userName = name.isNotEmpty ? name : userName;
    notifyListeners();
  }
}
