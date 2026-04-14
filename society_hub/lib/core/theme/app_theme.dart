import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Elevated Living Framework Colors
  static const Color primary = Color(0xFF3525CD);
  static const Color primaryContainer = Color(0xFF4F46E5);
  static const Color primaryFixed = Color(0xFFE2DFFF);
  
  static const Color secondary = Color(0xFF006E2F);
  static const Color secondaryContainer = Color(0xFF6BFF8F);
  static const Color secondaryFixed = Color(0xFF6BFF8F);
  
  static const Color surface = Color(0xFFF8F9FA); // Base canvas
  static const Color surfaceContainerLow = Color(0xFFF3F4F5); // Sub-sections
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF); // Hero cards
  static const Color surfaceContainerHighest = Color(0xFFE1E3E4); // Inputs
  
  static const Color onSurface = Color(0xFF191C1D);
  static const Color onSurfaceVariant = Color(0xFF464555);
  static const Color outlineVariant = Color(0xFFC7C4D8); // Ghost borders
  
  static const Color error = Color(0xFFBA1A1A);
  static const Color errorContainer = Color(0xFFFFDAD6);

  // Layout & Spacing Constants
  static const double radiusLg = 32.0; // 2rem
  static const double radiusMd = 24.0; // 1.5rem
  
  /// The ambient depth shadow for floating elements
  static List<BoxShadow> get ambientShadows => [
        BoxShadow(
          color: onSurface.withValues(alpha: 0.06),
          blurRadius: 40.0,
          spreadRadius: 0.0,
          offset: const Offset(0, 0),
        )
      ];

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: primary,
        primaryContainer: primaryContainer,
        secondary: secondary,
        secondaryContainer: secondaryContainer,
        surface: surface,
        surfaceContainerLow: surfaceContainerLow,
        surfaceContainerLowest: surfaceContainerLowest,
        surfaceContainerHighest: surfaceContainerHighest,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        outlineVariant: outlineVariant,
        error: error,
        errorContainer: errorContainer,
      ),
      scaffoldBackgroundColor: surface,
      textTheme: GoogleFonts.interTextTheme().copyWith(
        displayLarge: GoogleFonts.manrope(fontWeight: FontWeight.w800, color: onSurface),
        displayMedium: GoogleFonts.manrope(fontWeight: FontWeight.w800, color: onSurface),
        displaySmall: GoogleFonts.manrope(fontWeight: FontWeight.w800, color: onSurface),
        headlineLarge: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: onSurface),
        headlineMedium: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: onSurface),
        headlineSmall: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: onSurface),
        titleLarge: GoogleFonts.manrope(fontWeight: FontWeight.w600, color: onSurface),
        bodyLarge: GoogleFonts.inter(fontWeight: FontWeight.w400, color: onSurface),
        bodyMedium: GoogleFonts.inter(fontWeight: FontWeight.w400, color: onSurface),
        labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w500, color: onSurface),
        labelSmall: GoogleFonts.inter(fontWeight: FontWeight.w500, color: onSurface).copyWith(letterSpacing: 1.1),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: onSurface),
      ),
      cardTheme: CardThemeData(
        color: surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide.none,
        ),
        labelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: onSurfaceVariant),
      ),
    );
  }

  // Dark theme isn't fully defined in Stitch output but we adopt it symmetrically
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFC3C0FF),
        primaryContainer: primary,
        secondary: Color(0xFF6BFF8F),
        surface: Color(0xFF191C1D),
        surfaceContainerLow: Color(0xFF2E3132),
        surfaceContainerLowest: Color(0xFF464555),
        surfaceContainerHighest: Color(0xFF777587),
        onSurface: Color(0xFFF0F1F2),
        outlineVariant: Color(0xFFC7C4D8),
        error: Color(0xFFFFDAD6),
      ),
      scaffoldBackgroundColor: const Color(0xFF191C1D),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
        displayLarge: GoogleFonts.manrope(fontWeight: FontWeight.w800),
        displayMedium: GoogleFonts.manrope(fontWeight: FontWeight.w800),
        displaySmall: GoogleFonts.manrope(fontWeight: FontWeight.w800),
        headlineLarge: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        headlineMedium: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        titleLarge: GoogleFonts.manrope(fontWeight: FontWeight.w600),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: Colors.white),
      ),
    );
  }
}

