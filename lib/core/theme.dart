import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
    // Poppins aplicado em cima da escala de texto padrão do Material —
    // troca só a fonte, mantendo tamanhos/pesos que os widgets já esperam.
    final textTheme = GoogleFonts.poppinsTextTheme(
      ThemeData(brightness: Brightness.dark).textTheme,
    ).apply(bodyColor: textPrimary, displayColor: textPrimary);

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: accent,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accent,
        surface: surface,
      ),
      // Ripple/splash na cor de destaque em vez do cinza padrão do
      // Material, que destoa em cima de um fundo escuro.
      splashColor: accent.withOpacity(0.12),
      highlightColor: accent.withOpacity(0.05),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        foregroundColor: textPrimary,
        titleTextStyle: GoogleFonts.poppins(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      textTheme: textTheme.copyWith(
        bodyLarge: textTheme.bodyLarge?.copyWith(color: textPrimary),
        bodyMedium: textTheme.bodyMedium?.copyWith(color: textSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.black,
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
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
