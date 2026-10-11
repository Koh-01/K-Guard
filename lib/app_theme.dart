import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xFF171717);
  static const canvas = Color(0xFFF5F5F5);
  static const surface = Color(0xFFFFFFFF);
  static const subtle = Color(0xFFFAFAFA);
  static const blue = Color(0xFF0A72EF);
  static const success = Color(0xFF16803C);
  static const warning = Color(0xFFB45309);
  static const danger = Color(0xFFD92D20);
  static const muted = Color(0xFF666666);

  static Color hairline(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0x1AFFFFFF)
          : const Color(0x14000000);
}

abstract final class AppTheme {
  static ThemeData light() => _theme(Brightness.light);
  static ThemeData dark() => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: dark ? const Color(0xFFF5F5F5) : AppColors.ink,
      onPrimary: dark ? AppColors.ink : Colors.white,
      primaryContainer:
          dark ? const Color(0xFF242424) : const Color(0xFFEAF3FF),
      onPrimaryContainer:
          dark ? const Color(0xFFF5F5F5) : const Color(0xFF084A91),
      secondary: dark ? const Color(0xFF57A0FF) : AppColors.blue,
      onSecondary: Colors.white,
      secondaryContainer:
          dark ? const Color(0xFF12243A) : const Color(0xFFEAF3FF),
      onSecondaryContainer:
          dark ? const Color(0xFFB9D7FF) : const Color(0xFF084A91),
      tertiary: dark ? const Color(0xFF73D995) : AppColors.success,
      onTertiary: dark ? AppColors.ink : Colors.white,
      error: dark ? const Color(0xFFFF6B61) : AppColors.danger,
      onError: Colors.white,
      surface: dark ? const Color(0xFF141414) : AppColors.surface,
      onSurface: dark ? const Color(0xFFF5F5F5) : AppColors.ink,
      surfaceContainerLowest:
          dark ? const Color(0xFF101010) : AppColors.surface,
      surfaceContainerLow: dark ? const Color(0xFF171717) : AppColors.subtle,
      surfaceContainer:
          dark ? const Color(0xFF1C1C1C) : const Color(0xFFF2F2F2),
      surfaceContainerHigh:
          dark ? const Color(0xFF242424) : const Color(0xFFEBEBEB),
      surfaceContainerHighest:
          dark ? const Color(0xFF2C2C2C) : const Color(0xFFE2E2E2),
      onSurfaceVariant: dark ? const Color(0xFFA3A3A3) : AppColors.muted,
      outline: dark ? const Color(0xFF4A4A4A) : const Color(0xFFD4D4D4),
      outlineVariant: dark ? const Color(0xFF303030) : const Color(0xFFE8E8E8),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: dark ? const Color(0xFFF5F5F5) : AppColors.ink,
      onInverseSurface: dark ? AppColors.ink : Colors.white,
      inversePrimary: dark ? AppColors.ink : const Color(0xFFF5F5F5),
    );

    final base = ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor:
          dark ? const Color(0xFF090909) : AppColors.canvas,
      canvasColor: dark ? const Color(0xFF090909) : AppColors.canvas,
      fontFamilyFallback: const ['Arial', 'sans-serif'],
      splashFactory: InkSparkle.splashFactory,
    );

    final text = base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w600, letterSpacing: -1.2, height: 1.08),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600, letterSpacing: -0.9, height: 1.12),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600, letterSpacing: -0.7, height: 1.18),
      titleLarge: base.textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.45),
      titleMedium: base.textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
      titleSmall:
          base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.5),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.45),
      bodySmall: base.textTheme.bodySmall
          ?.copyWith(height: 1.4, color: scheme.onSurfaceVariant),
      labelLarge:
          base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
    );

    final hairline = dark ? const Color(0x1AFFFFFF) : const Color(0x14000000);
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );

    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: hairline),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.secondary, width: 2),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.surfaceContainerHigh,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) =>
            text.labelSmall?.copyWith(
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w600
                    : FontWeight.w500,
                color: scheme.onSurface)),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            size: 23,
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant)),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minVerticalPadding: 10,
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
        subtitleTextStyle:
            text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: text.labelMedium,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? scheme.surfaceContainerHigh
                  : scheme.surface),
          foregroundColor: WidgetStatePropertyAll(scheme.onSurface),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.secondary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurfaceVariant),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.surfaceContainerHighest),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    );
  }
}
