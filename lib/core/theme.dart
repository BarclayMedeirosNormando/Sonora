import 'package:flutter/material.dart';

/// Tema visual do Sonora: fundo escuro, estilo player de música.
/// Cor de destaque isolada aqui para ser fácil de trocar depois.
class AppTheme {
  AppTheme._();

  static const Color background = Color(0xFF121212);
  static const Color surface = Color(0xFF181818);
  static const Color surfaceHigh = Color(0xFF282828);
  static const Color accent = Color(0xFF2FE6A7);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB3B3B3);

  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: accent,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accent,
        surface: surface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        foregroundColor: textPrimary,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: textPrimary),
        bodyMedium: TextStyle(color: textSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        ),
      ),
      useMaterial3: true,
    );
  }
}
