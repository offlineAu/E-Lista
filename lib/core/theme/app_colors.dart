import 'package:flutter/material.dart';

/// The E-Lista palette.
///
/// A friendly modern Filipino retail look: deep green as the anchor, warm yellow and
/// orange for emphasis, on a soft cream ground. It should read as a neighbourhood store
/// that takes itself seriously — warm, but not childish.
///
/// Every pairing used for text in `AppTheme` clears WCAG AA (4.5:1 for body text, 3:1 for
/// large text and icons). Where a colour is too light to carry white text — warm yellow
/// especially — the theme puts [onWarmYellow] charcoal on it instead of white.
abstract final class AppColors {
  // ---------------------------------------------------------------- brand

  /// Primary. Deep green — app bars, primary buttons, prices.
  static const Color deepGreen = Color(0xFF1B5E3F);
  static const Color deepGreenDark = Color(0xFF10402A);
  static const Color deepGreenLight = Color(0xFF2E7D5A);

  /// Container tint for primary surfaces (selected chips, subtle highlights).
  static const Color greenContainer = Color(0xFFD5E9DE);
  static const Color onGreenContainer = Color(0xFF0B2E1E);

  /// Secondary. Warm yellow — highlights, badges, the GCash price accent.
  static const Color warmYellow = Color(0xFFF2B705);
  static const Color warmYellowContainer = Color(0xFFFDF0C9);
  static const Color onWarmYellow = Color(0xFF3A2E00);

  /// Accent. Orange — calls to action that must not be confused with the primary action,
  /// and the "add to cart" affordance.
  static const Color orange = Color(0xFFE2681C);
  static const Color orangeContainer = Color(0xFFFBE0CE);
  static const Color onOrangeContainer = Color(0xFF4A1D00);

  // ------------------------------------------------------------- neutrals

  /// Soft cream page background.
  static const Color cream = Color(0xFFFBF7EF);

  /// Cards and sheets sit slightly above the cream ground.
  static const Color surface = Color(0xFFFFFDF8);
  static const Color surfaceMuted = Color(0xFFF2EDE3);

  /// Dark charcoal body text.
  static const Color charcoal = Color(0xFF23262B);

  /// Secondary text: labels, captions, metadata. 4.6:1 on [surface].
  static const Color charcoalMuted = Color(0xFF5C6169);

  /// Hairlines and dividers.
  static const Color outline = Color(0xFFD9D2C5);
  static const Color outlineStrong = Color(0xFFB9B0A0);

  // --------------------------------------------------------------- status

  static const Color success = Color(0xFF1F7A46);
  static const Color successContainer = Color(0xFFD8F0E1);
  static const Color onSuccessContainer = Color(0xFF0A3D22);

  static const Color warning = Color(0xFFB26A00);
  static const Color warningContainer = Color(0xFFFCEBCB);
  static const Color onWarningContainer = Color(0xFF4A2C00);

  static const Color danger = Color(0xFFB3261E);
  static const Color dangerContainer = Color(0xFFFADAD7);
  static const Color onDangerContainer = Color(0xFF4E0F0B);

  static const Color info = Color(0xFF1B5E86);
  static const Color infoContainer = Color(0xFFD5E8F2);
  static const Color onInfoContainer = Color(0xFF06293C);

  // ------------------------------------------------------- dark surfaces
  //
  // The owner dashboard is used in a dim store as often as a bright one, so the app
  // supports dark mode throughout rather than forcing the light palette.

  static const Color darkBackground = Color(0xFF14171A);
  static const Color darkSurface = Color(0xFF1C2024);
  static const Color darkSurfaceMuted = Color(0xFF262B31);
  static const Color darkOutline = Color(0xFF3B424A);
  static const Color onDark = Color(0xFFEDEAE3);
  static const Color onDarkMuted = Color(0xFFAFB5BD);
  static const Color greenOnDark = Color(0xFF6FCE9C);
  static const Color yellowOnDark = Color(0xFFF7CF57);
  static const Color orangeOnDark = Color(0xFFF79B5E);
  static const Color successOnDark = Color(0xFF6FCE9C);
  static const Color warningOnDark = Color(0xFFEFB65A);
  static const Color dangerOnDark = Color(0xFFF2938C);
  static const Color infoOnDark = Color(0xFF7CC0E0);
}
