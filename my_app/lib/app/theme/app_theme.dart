import 'package:flutter/material.dart';

class AppTheme {
  static const Color brandBlue = Color(0xFF0284C7);
  static const Color brandGreen = Color(0xFF22C55E);
  static const Color ink = Color(0xFF0F172A);
  static const Color pageBg = Color(0xFFF6FAFF);

  static ThemeData light() {
    final cs = ColorScheme.fromSeed(seedColor: brandBlue, brightness: Brightness.light);
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: pageBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFE5E7EB), thickness: 1),
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: ink),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: ink),
        bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink),
        bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink),
      ),
    );
  }
}
