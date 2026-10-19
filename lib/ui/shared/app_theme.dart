import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta de colores premium para el tema oscuro de TransferFiles.
/// Diseñada para dar un aspecto elegante y futurista.
class AppColors {
  AppColors._(); // Prevenir instanciación

  // ─── Fondos ────────────────────────────────────────────────
  /// Fondo principal – azul marino profundo
  static const Color background = Color(0xFF0A0E1A);

  /// Superficie de tarjetas y paneles
  static const Color surface = Color(0xFF151A2D);

  /// Superficie más clara para elementos elevados
  static const Color surfaceLight = Color(0xFF1E2442);

  // ─── Acentos ───────────────────────────────────────────────
  /// Cyan eléctrico – acento principal (PC / envío)
  static const Color primary = Color(0xFF00D4FF);

  /// Púrpura – acento secundario (Quest / recepción)
  static const Color secondary = Color(0xFF7B61FF);

  /// Verde – éxito / completado
  static const Color success = Color(0xFF00E676);

  /// Rojo – error / fallido
  static const Color error = Color(0xFFFF5252);

  // ─── Texto ─────────────────────────────────────────────────
  /// Texto principal claro
  static const Color textPrimary = Color(0xFFE8EAED);

  /// Texto secundario / subtítulos
  static const Color textSecondary = Color(0xFF9AA0B4);

  // ─── Bordes ────────────────────────────────────────────────
  /// Borde sutil para separadores y bordes de tarjeta
  static const Color border = Color(0xFF2A3050);

  // ─── Gradientes comunes ────────────────────────────────────
  /// Gradiente cyan → púrpura para botones y acentos
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Gradiente para tarjetas glassmorphism
  static const LinearGradient cardGradient = LinearGradient(
    colors: [
      Color(0x1A00D4FF), // cyan con 10% opacidad
      Color(0x0D7B61FF), // púrpura con 5% opacidad
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Gradiente para el fondo de la app
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [
      Color(0xFF0A0E1A),
      Color(0xFF0F1528),
      Color(0xFF0A0E1A),
    ],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

/// Tema principal de la aplicación TransferFiles.
/// Proporciona un ThemeData oscuro, elegante y moderno.
class AppTheme {
  AppTheme._(); // Prevenir instanciación

  /// Genera el [ThemeData] completo para la aplicación.
  static ThemeData getTheme() {
    // Tipografía base con Google Fonts Inter
    final textTheme = GoogleFonts.interTextTheme(
      ThemeData.dark().textTheme,
    ).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.surface,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        error: AppColors.error,
        onPrimary: AppColors.background,
        onSecondary: AppColors.background,
        onSurface: AppColors.textPrimary,
        onError: Colors.white,
      ),
      textTheme: textTheme,

      // ─── AppBar transparente / oscuro ────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
        iconTheme: const IconThemeData(color: AppColors.primary),
      ),

      // ─── Tarjetas con bordes redondeados ─────────────────────
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      // ─── Campos de texto elegantes ───────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceLight,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        labelStyle: GoogleFonts.inter(
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
        hintStyle: GoogleFonts.inter(
          color: AppColors.textSecondary.withValues(alpha: 0.6),
          fontSize: 14,
        ),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
      ),

      // ─── Botón elevado con aspecto de gradiente ──────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.background,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // ─── Botón de texto ──────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ─── Botón con borde ─────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ─── Pestañas ────────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),

      // ─── Iconos ──────────────────────────────────────────────
      iconTheme: const IconThemeData(
        color: AppColors.textSecondary,
        size: 24,
      ),

      // ─── Divisor ─────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      // ─── Diálogos ────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),

      // ─── Snackbar ────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceLight,
        contentTextStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // ─── Indicador de progreso ───────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.surfaceLight,
        circularTrackColor: AppColors.surfaceLight,
      ),

      // ─── Tooltip ─────────────────────────────────────────────
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        textStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontSize: 12,
        ),
      ),
    );
  }
}
