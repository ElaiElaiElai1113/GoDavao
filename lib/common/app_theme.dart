import 'package:flutter/material.dart';
import 'package:godavao/common/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:godavao/common/app_colors.dart';

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.purple,
        brightness: Brightness.light,
      ),
    );

    final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme);

    return base.copyWith(
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      textTheme: _textTheme(textTheme),
      scaffoldBackgroundColor: AppColors.bg,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        hintStyle: TextStyle(color: Colors.grey.shade600),
      ),
      chipTheme: base.chipTheme.copyWith(
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        shape: const StadiumBorder(),
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 12,
        minLeadingWidth: 36,
      ),
      dividerTheme: DividerThemeData(
        color: Colors.grey.shade200,
        thickness: 1,
        space: 20,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.purple),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.purple,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: const BorderSide(color: AppColors.purple),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.purple,
        foregroundColor: Colors.white,
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    return base.copyWith(
      titleLarge: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.black87),
      titleMedium: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87),
      titleSmall: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87),
      bodyLarge: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87),
      bodyMedium: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87),
      bodySmall: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black87),
      labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black87),
    );
  }
}
