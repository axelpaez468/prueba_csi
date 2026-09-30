import 'package:flutter/material.dart';

/// Paleta y tema de la aplicación. Toda la UI toma los colores de aquí.
class AppColors {
  const AppColors._();

  static const primary = Color(0xFF2450C8); // azul corporativo
  static const primaryDark = Color(0xFF16307F);
  static const accent = Color(0xFF0E9F6E); // esmeralda para acciones positivas
  static const background = Color(0xFFF1F4F9);
  static const surface = Colors.white;
  static const border = Color(0xFFE3E8EF);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);

  // Barra de navegación (header oscuro del ERP).
  static const navbar = Color(0xFF0B1426);
  static const navbarClaro = Color(0xFF16243F);
  static const navbarTexto = Color(0xFFCBD5E1);

  /// Degradado de marca (encabezado del panel, destacados).
  static const degradado = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0B1426), Color(0xFF16307F), Color(0xFF2450C8)],
    stops: [0, 0.55, 1],
  );

  static const success = Color(0xFF1E8E5A);
  static const successBg = Color(0xFFE6F4EC);
  static const warning = Color(0xFFB26A00);
  static const warningBg = Color(0xFFFFF3DC);
  static const danger = Color(0xFFC62828);
  static const dangerBg = Color(0xFFFDECEC);
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.surface,
      error: AppColors.danger,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final text = base.textTheme.apply(bodyColor: AppColors.textPrimary, displayColor: AppColors.textPrimary);

    final bordeCampo = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.border),
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      textTheme: text.copyWith(
        headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
        headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        // Sombra suave y borde tenue: tarjetas "flotantes" sobre el fondo gris azulado.
        elevation: 1.5,
        shadowColor: const Color(0x1A0F172A),
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: const Color(0x330F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: const Color(0xFFE3EAFB),
          selectedForegroundColor: AppColors.primaryDark,
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      chipTheme: ChipThemeData(
        side: const BorderSide(color: AppColors.border),
        selectedColor: const Color(0xFFE3EAFB),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: bordeCampo,
        enabledBorder: bordeCampo,
        focusedBorder: bordeCampo.copyWith(borderSide: const BorderSide(color: AppColors.primary, width: 1.6)),
        errorBorder: bordeCampo.copyWith(borderSide: const BorderSide(color: AppColors.danger)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(0, 44),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, space: 1, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primaryDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        width: 380,
      ),
      badgeTheme: const BadgeThemeData(backgroundColor: AppColors.accent),
    );
  }
}
