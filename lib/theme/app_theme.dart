import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta de marca SILVORA baseada nas referências visuais.
class BrandColors {
  static const forest = Color(0xFF1B5E20);
  static const forestLight = Color(0xFF4CAF50);
  static const forestDark = Color(0xFF0E2B1B);
  static const forestCard = Color(0xFF2E7D32);
  static const black = Color(0xFF121212);
  static const white = Color(0xFFFFFFFF);
  static const graySurface = Color(0xFF1E1E1E);
  static const grayLight = Color(0xFFE6E6E6);
  static const alert = Color(0xFFFF8C00);
  static const alertSoft = Color(0xFFFFF3E0);
  static const success = Color(0xFF43A047);
  static const successSoft = Color(0xFFE8F5E9);
  static const danger = Color(0xFFD32F2F);
  static const info = Color(0xFF1976D2);
  static const cream = Color(0xFFFFF8F0);
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: BrandColors.forest,
      brightness: Brightness.light,
      primary: BrandColors.forest,
      secondary: BrandColors.forestLight,
      tertiary: BrandColors.alert,
    );
    return _base(scheme, Brightness.light);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: BrandColors.forest,
      brightness: Brightness.dark,
      primary: BrandColors.forestLight,
      secondary: const Color(0xFF81C784),
      tertiary: BrandColors.alert,
      surface: BrandColors.graySurface,
    );
    return _base(scheme, Brightness.dark);
  }

  static ThemeData _base(ColorScheme scheme, Brightness brightness) {
    final base = GoogleFonts.interTextTheme(
      brightness == Brightness.dark
          ? ThemeData.dark().textTheme
          : ThemeData.light().textTheme,
    );
    final textTheme = base.copyWith(
      displayLarge: GoogleFonts.exo2(textStyle: base.displayLarge),
      displayMedium: GoogleFonts.exo2(textStyle: base.displayMedium),
      displaySmall: GoogleFonts.exo2(textStyle: base.displaySmall),
      headlineLarge: GoogleFonts.exo2(textStyle: base.headlineLarge),
      headlineMedium: GoogleFonts.exo2(textStyle: base.headlineMedium),
      headlineSmall: GoogleFonts.exo2(textStyle: base.headlineSmall),
      titleLarge: GoogleFonts.exo2(textStyle: base.titleLarge),
    );
    final radius = BorderRadius.circular(20);
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? BrandColors.black : const Color(0xFFF6F7F6),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor:
            isDark ? BrandColors.graySurface : const Color(0xFFF6F7F6),
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: isDark ? BrandColors.graySurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle:
              textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        side: BorderSide.none,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: isDark ? BrandColors.graySurface : Colors.white,
        indicatorColor: scheme.primary.withValues(alpha: 0.16),
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.4),
        space: 1,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}
