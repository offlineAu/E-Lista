import 'package:flutter/material.dart';

/// The E-Lista palette.
///
/// A modern, friendly retail look: a deepened rose as the anchor (buttons, prices, the
/// primary action), a soft violet as the second accent, and a warmer pink as a third,
/// distinct-from-primary tone for badges and callouts — all drawn from one soft-pink family
/// on a near-white blush ground. The five original reference swatches (`#FDE4F2` through
/// `#E68BBE`) are pastel by nature, so they live on here as containers and tints; the raw
/// brand colors below are deepened just enough to carry white text accessibly.
///
/// Every pairing used for text in `AppTheme` clears WCAG AA (4.5:1 for body text, 3:1 for
/// large text and icons).
abstract final class AppColors {
  // ---------------------------------------------------------------- brand

  /// Primary. Deepened rose — app bars, primary buttons, prices.
  static const Color primaryRose = Color(0xFFC93E82);
  static const Color primaryRoseDark = Color(0xFFA32E68);

  /// Container tint for primary surfaces (selected chips, subtle highlights) — one of the
  /// original sampled swatches.
  static const Color primaryRoseContainer = Color(0xFFF9CEE7);
  static const Color onPrimaryRoseContainer = Color(0xFF7A2354);

  /// Secondary. Soft violet — the one deliberately "tech" note in an otherwise warm
  /// palette; charts' second series, secondary actions.
  static const Color accentViolet = Color(0xFF7C5CFC);
  static const Color accentVioletContainer = Color(0xFFEEE8FF);
  static const Color onAccentVioletContainer = Color(0xFF4A34A8);

  /// Tertiary. A warmer, lighter pink — calls to action that must not be confused with the
  /// primary action, and badge/highlight accents.
  static const Color tertiaryPink = Color(0xFFE68BBE);
  static const Color tertiaryPinkContainer = Color(0xFFFDE4F2);
  static const Color onTertiaryPinkContainer = Color(0xFF8A3D63);

  // ------------------------------------------------------------- neutrals

  /// Soft near-white, warm-pink-tinted page background.
  static const Color blush = Color(0xFFFFFBFD);

  /// Cards and sheets sit slightly above the blush ground.
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFFDE4F2);

  /// Dark plum body text.
  static const Color plum = Color(0xFF3D1228);

  /// Secondary text: labels, captions, metadata.
  static const Color plumMuted = Color(0xFF6B5361);

  /// Hairlines and dividers.
  static const Color outline = Color(0xFFF3D6E7);
  static const Color outlineStrong = Color(0xFFE0AFC9);

  // --------------------------------------------------------------- status
  //
  // Conventional regardless of brand palette — a warning is amber, an error is red, no
  // matter what hue the rest of the app is wearing.

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
  // supports dark mode throughout rather than forcing the light palette. Dark surfaces keep
  // a warm plum tint rather than going neutral-gray, so dark mode still reads as this app.

  static const Color darkBackground = Color(0xFF1A1116);
  static const Color darkSurface = Color(0xFF241820);
  static const Color darkSurfaceMuted = Color(0xFF2E1E29);
  static const Color darkOutline = Color(0xFF3A2732);
  static const Color onDark = Color(0xFFF5E9F0);
  static const Color onDarkMuted = Color(0xFFC7AFC0);
  static const Color primaryRoseOnDark = Color(0xFFF2A8D2);
  static const Color accentVioletOnDark = Color(0xFFB39DFF);
  static const Color tertiaryPinkOnDark = Color(0xFFF7C2E0);
  static const Color successOnDark = Color(0xFF6FCE9C);
  static const Color warningOnDark = Color(0xFFEFB65A);
  static const Color dangerOnDark = Color(0xFFF2938C);
  static const Color infoOnDark = Color(0xFF7CC0E0);
}
