import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Material 3 themes for E-Lista.
///
/// One theme serves both roles. The customer screens lean on the blush ground, big
/// product cards and large touch targets; the owner screens reuse the same tokens with
/// denser layouts, which keeps the app coherent instead of feeling like two apps stapled
/// together.
///
/// Sizing decisions are deliberate rather than defaults:
/// * Body text starts at 15sp, not 14sp — this is used one-handed, often outdoors.
/// * Interactive targets are at least 48dp, per the Material accessibility guidance.
/// * Text scales with the system setting; nothing is clamped below the user's choice.
///
/// Typefaces: Sora for headings (geometric, a little technical, rounded at the
/// terminals so it doesn't turn cold) and Plus Jakarta Sans for body/UI text (warm,
/// legible at small sizes).
abstract final class AppTheme {
  /// The smallest side a tappable control may have.
  static const double minTouchTarget = 48;

  /// Corner radius for cards, sheets and fields. One value everywhere.
  static const double radius = 14;
  static const double radiusSmall = 10;
  static const double radiusLarge = 22;

  static ThemeData get light => _build(_lightScheme, Brightness.light);

  static ThemeData get dark => _build(_darkScheme, Brightness.dark);

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primaryRose,
    onPrimary: Colors.white,
    primaryContainer: AppColors.primaryRoseContainer,
    onPrimaryContainer: AppColors.onPrimaryRoseContainer,
    secondary: AppColors.accentViolet,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.accentVioletContainer,
    onSecondaryContainer: AppColors.onAccentVioletContainer,
    tertiary: AppColors.tertiaryPink,
    onTertiary: AppColors.plum,
    tertiaryContainer: AppColors.tertiaryPinkContainer,
    onTertiaryContainer: AppColors.onTertiaryPinkContainer,
    error: AppColors.danger,
    onError: Colors.white,
    errorContainer: AppColors.dangerContainer,
    onErrorContainer: AppColors.onDangerContainer,
    surface: AppColors.surface,
    onSurface: AppColors.plum,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: AppColors.surface,
    surfaceContainer: AppColors.blush,
    surfaceContainerHigh: AppColors.surfaceMuted,
    surfaceContainerHighest: AppColors.surfaceMuted,
    onSurfaceVariant: AppColors.plumMuted,
    outline: AppColors.outlineStrong,
    outlineVariant: AppColors.outline,
    inverseSurface: AppColors.plum,
    onInverseSurface: AppColors.blush,
    inversePrimary: AppColors.primaryRoseOnDark,
    shadow: Color(0x1A000000),
    scrim: Color(0x99000000),
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.primaryRoseOnDark,
    onPrimary: Color(0xFF3D1228),
    primaryContainer: Color(0xFF5C2A46),
    onPrimaryContainer: Color(0xFFF9CEE7),
    secondary: AppColors.accentVioletOnDark,
    onSecondary: Color(0xFF241040),
    secondaryContainer: Color(0xFF382B6B),
    onSecondaryContainer: Color(0xFFE3D9FF),
    tertiary: AppColors.tertiaryPinkOnDark,
    onTertiary: Color(0xFF4A1F38),
    tertiaryContainer: Color(0xFF5C2E48),
    onTertiaryContainer: Color(0xFFFBDDEE),
    error: AppColors.dangerOnDark,
    onError: Color(0xFF470D08),
    errorContainer: Color(0xFF6B1C16),
    onErrorContainer: Color(0xFFFBDAD6),
    surface: AppColors.darkSurface,
    onSurface: AppColors.onDark,
    surfaceContainerLowest: Color(0xFF120D10),
    surfaceContainerLow: AppColors.darkBackground,
    surfaceContainer: AppColors.darkSurface,
    surfaceContainerHigh: AppColors.darkSurfaceMuted,
    surfaceContainerHighest: Color(0xFF3A2732),
    onSurfaceVariant: AppColors.onDarkMuted,
    outline: AppColors.darkOutline,
    outlineVariant: Color(0xFF3A2732),
    inverseSurface: AppColors.blush,
    onInverseSurface: AppColors.plum,
    inversePrimary: AppColors.primaryRose,
    shadow: Color(0x33000000),
    scrim: Color(0xCC000000),
  );

  static ThemeData _build(ColorScheme scheme, Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
    );

    final textTheme = _textTheme(base.textTheme, scheme);

    return base.copyWith(
      scaffoldBackgroundColor: isLight
          ? AppColors.blush
          : AppColors.darkBackground,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? AppColors.blush : AppColors.darkBackground,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle: isLight
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        // A soft tinted shadow instead of a hairline border — the "glassy, modern" look
        // reads as cards floating above the ground, not cards outlined against it.
        elevation: 2,
        shadowColor: AppColors.primaryRose.withValues(alpha: 0.14),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, minTouchTarget),
          elevation: 0,
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: textTheme.labelLarge,
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, minTouchTarget),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? Colors.white : AppColors.darkSurfaceMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        helperStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        helperMaxLines: 3,
        errorMaxLines: 3,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isLight ? Colors.white : AppColors.darkSurfaceMuted,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        selectedLabelTextStyle: textTheme.labelMedium,
        unselectedLabelTextStyle: textTheme.labelMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(radiusLarge),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: 12,
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base, ColorScheme scheme) {
    final body = GoogleFonts.plusJakartaSansTextTheme(base);
    final heading = GoogleFonts.soraTextTheme(base);

    return body
        .copyWith(
          displaySmall: heading.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
          headlineMedium: heading.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
          headlineSmall: heading.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          titleLarge: heading.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          titleMedium: heading.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          titleSmall: heading.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          // 15sp body: this app is read one-handed, often in daylight.
          bodyLarge: body.bodyLarge?.copyWith(fontSize: 16, height: 1.4),
          bodyMedium: body.bodyMedium?.copyWith(fontSize: 15, height: 1.4),
          bodySmall: body.bodySmall?.copyWith(fontSize: 13, height: 1.35),
          labelLarge: body.labelLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          labelMedium: body.labelMedium?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        )
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  }
}
