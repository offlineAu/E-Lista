import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Material 3 themes for E-Lista.
///
/// One theme serves both roles. The customer screens lean on the cream ground, big
/// product cards and large touch targets; the owner screens reuse the same tokens with
/// denser layouts, which keeps the app coherent instead of feeling like two apps stapled
/// together.
///
/// Sizing decisions are deliberate rather than defaults:
/// * Body text starts at 15sp, not 14sp — this is used one-handed, often outdoors.
/// * Interactive targets are at least 48dp, per the Material accessibility guidance.
/// * Text scales with the system setting; nothing is clamped below the user's choice.
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
    primary: AppColors.deepGreen,
    onPrimary: Colors.white,
    primaryContainer: AppColors.greenContainer,
    onPrimaryContainer: AppColors.onGreenContainer,
    secondary: AppColors.warmYellow,
    onSecondary: AppColors.onWarmYellow,
    secondaryContainer: AppColors.warmYellowContainer,
    onSecondaryContainer: AppColors.onWarmYellow,
    tertiary: AppColors.orange,
    onTertiary: Colors.white,
    tertiaryContainer: AppColors.orangeContainer,
    onTertiaryContainer: AppColors.onOrangeContainer,
    error: AppColors.danger,
    onError: Colors.white,
    errorContainer: AppColors.dangerContainer,
    onErrorContainer: AppColors.onDangerContainer,
    surface: AppColors.surface,
    onSurface: AppColors.charcoal,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: AppColors.surface,
    surfaceContainer: AppColors.cream,
    surfaceContainerHigh: AppColors.surfaceMuted,
    surfaceContainerHighest: AppColors.surfaceMuted,
    onSurfaceVariant: AppColors.charcoalMuted,
    outline: AppColors.outlineStrong,
    outlineVariant: AppColors.outline,
    inverseSurface: AppColors.charcoal,
    onInverseSurface: AppColors.cream,
    inversePrimary: AppColors.greenOnDark,
    shadow: Color(0x1A000000),
    scrim: Color(0x99000000),
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.greenOnDark,
    onPrimary: Color(0xFF042816),
    primaryContainer: Color(0xFF1B4633),
    onPrimaryContainer: Color(0xFFCDEBDB),
    secondary: AppColors.yellowOnDark,
    onSecondary: Color(0xFF3A2E00),
    secondaryContainer: Color(0xFF4E3D00),
    onSecondaryContainer: Color(0xFFFBE9B4),
    tertiary: AppColors.orangeOnDark,
    onTertiary: Color(0xFF3D1500),
    tertiaryContainer: Color(0xFF5B2A0B),
    onTertiaryContainer: Color(0xFFFBDCC6),
    error: AppColors.dangerOnDark,
    onError: Color(0xFF470D08),
    errorContainer: Color(0xFF6B1C16),
    onErrorContainer: Color(0xFFFBDAD6),
    surface: AppColors.darkSurface,
    onSurface: AppColors.onDark,
    surfaceContainerLowest: Color(0xFF101315),
    surfaceContainerLow: AppColors.darkBackground,
    surfaceContainer: AppColors.darkSurface,
    surfaceContainerHigh: AppColors.darkSurfaceMuted,
    surfaceContainerHighest: Color(0xFF2E343B),
    onSurfaceVariant: AppColors.onDarkMuted,
    outline: AppColors.darkOutline,
    outlineVariant: Color(0xFF2E343B),
    inverseSurface: AppColors.cream,
    onInverseSurface: AppColors.charcoal,
    inversePrimary: AppColors.deepGreen,
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
          ? AppColors.cream
          : AppColors.darkBackground,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? AppColors.cream : AppColors.darkBackground,
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
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: scheme.outlineVariant),
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
    return base
        .copyWith(
          displaySmall: base.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          headlineMedium: base.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
          headlineSmall: base.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          titleLarge: base.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          // 15sp body: this app is read one-handed, often in daylight.
          bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, height: 1.4),
          bodyMedium: base.bodyMedium?.copyWith(fontSize: 15, height: 1.4),
          bodySmall: base.bodySmall?.copyWith(fontSize: 13, height: 1.35),
          labelLarge: base.labelLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          labelMedium: base.labelMedium?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        )
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  }
}
