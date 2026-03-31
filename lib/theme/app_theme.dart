import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color backgroundNavy = Color(0xFF0A0E21);
  static const Color surfaceNavy = Color(0xFF1D1E33);
  static const Color accentGold = Color(0xFFD4AF37);
  static const Color lightGold = Color(0xFFCFB53B);
  static const Color errorRed = Color(0xFFFB3B3B);
  static const Color textMain = Colors.white;
  static const Color textSecondary = Color(0xFF8D8E98);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.backgroundNavy,
      primaryColor: AppColors.accentGold,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accentGold,
        secondary: AppColors.lightGold,
        surface: AppColors.surfaceNavy,
        error: AppColors.errorRed,
      ),
      textTheme: GoogleFonts.outfitTextTheme(
        const TextTheme(
          displayLarge: TextStyle(
            color: AppColors.textMain,
            fontWeight: FontWeight.bold,
          ),
          titleLarge: TextStyle(
            color: AppColors.textMain,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: TextStyle(color: AppColors.textMain),
          bodyMedium: TextStyle(color: AppColors.textSecondary),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.backgroundNavy,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.textMain,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
