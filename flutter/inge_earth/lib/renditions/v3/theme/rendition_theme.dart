import 'package:flutter/material.dart';

abstract final class RenditionTokens {
  static const background = Color(0xFFF7F7F5);
  static const surface = Color(0xFFFFFFFF);
  static const secondarySurface = Color(0xFFF1F1EE);
  static const ink = Color(0xFF111311);
  static const secondary = Color(0xFF656965);
  static const tertiary = Color(0xFF8A8E89);
  static const border = Color(0xFFD8DAD6);
  static const divider = Color(0xFFE5E6E2);
  static const margin = 16.0;
}

ThemeData renditionTheme() {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: RenditionTokens.border),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: RenditionTokens.background,
    colorScheme: const ColorScheme.light(
      primary: RenditionTokens.ink,
      onPrimary: RenditionTokens.surface,
      secondary: RenditionTokens.secondary,
      surface: RenditionTokens.surface,
      onSurface: RenditionTokens.ink,
      outline: RenditionTokens.border,
      error: Color(0xFF943E3E),
    ),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontSize: 30,
        height: 1.12,
        fontWeight: FontWeight.w700,
        color: RenditionTokens.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: RenditionTokens.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: RenditionTokens.ink,
      ),
      bodyMedium: TextStyle(fontSize: 14, color: RenditionTokens.ink),
      bodySmall: TextStyle(fontSize: 12, color: RenditionTokens.secondary),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: RenditionTokens.surface,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: RenditionTokens.ink),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      labelStyle: const TextStyle(
        fontSize: 14,
        color: RenditionTokens.secondary,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: RenditionTokens.ink,
        foregroundColor: RenditionTokens.surface,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: RenditionTokens.divider,
      thickness: 1,
    ),
  );
}
