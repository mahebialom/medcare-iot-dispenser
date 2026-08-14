import 'package:flutter/material.dart';

/// Same token set as the JSX prototype's LIGHT/DARK objects — one class,
/// two const instances, so every screen just takes an `AppColors c` and
/// never hardcodes a color.
class AppColors {
  const AppColors({
    required this.page,
    required this.cardBg,
    required this.panel,
    required this.inputBg,
    required this.border,
    required this.borderSoft,
    required this.ink,
    required this.text2,
    required this.muted,
    required this.muted2,
    required this.primary,
    required this.green,
    required this.greenBg,
    required this.greenBorder,
    required this.red,
    required this.redBg,
    required this.redBorder,
    required this.amber,
    required this.amberBg,
    required this.amberBorder,
    required this.headerGrad,
    required this.deviceGrad,
    required this.deviceBorder,
    required this.deviceHeading,
    required this.weekendBg,
    required this.weekendText,
  });

  final Color page, cardBg, panel, inputBg, border, borderSoft;
  final Color ink, text2, muted, muted2;
  final Color primary, green, greenBg, greenBorder;
  final Color red, redBg, redBorder;
  final Color amber, amberBg, amberBorder;
  final Gradient headerGrad, deviceGrad;
  final Color deviceBorder, deviceHeading;
  final Color weekendBg, weekendText;

  static const light = AppColors(
    page: Color(0xFFF0F4F8),
    cardBg: Colors.white,
    panel: Color(0xFFF8FAFC),
    inputBg: Color(0xFFF8FAFC),
    border: Color(0xFFE2E8F0),
    borderSoft: Color(0xFFE9ECEF),
    ink: Color(0xFF1A202C),
    text2: Color(0xFF374151),
    muted: Color(0xFF6B7280),
    muted2: Color(0xFF9CA3AF),
    primary: Color(0xFF0F4C81),
    green: Color(0xFF1A6B4A),
    greenBg: Color(0xFFE6F4EA),
    greenBorder: Color(0xFFB7DFC3),
    red: Color(0xFFC0392B),
    redBg: Color(0xFFFFF3F3),
    redBorder: Color(0xFFFFC9C9),
    amber: Color(0xFF856404),
    amberBg: Color(0xFFFFF3CD),
    amberBorder: Color(0xFFFFC107),
    headerGrad: LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFF0F4C81), Color(0xFF1A6B4A)],
    ),
    deviceGrad: LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFFE8F5E9), Color(0xFFE3F2FD)],
    ),
    deviceBorder: Color(0xFFB2DFDB),
    deviceHeading: Color(0xFF1A4E8A),
    weekendBg: Color(0xFFF0F0F0),
    weekendText: Color(0xFF999999),
  );

  static const dark = AppColors(
    page: Color(0xFF0D1117),
    cardBg: Color(0xFF161B22),
    panel: Color(0xFF1C2431),
    inputBg: Color(0xFF0D1117),
    border: Color(0xFF30363D),
    borderSoft: Color(0xFF30363D),
    ink: Color(0xFFE6EDF3),
    text2: Color(0xFFC9D1D9),
    muted: Color(0xFF8B949E),
    muted2: Color(0xFF6E7681),
    primary: Color(0xFF58A6FF),
    green: Color(0xFF3FB950),
    greenBg: Color(0x332EA043),
    greenBorder: Color(0xFF2EA043),
    red: Color(0xFFF85149),
    redBg: Color(0x33DA3633),
    redBorder: Color(0xFFDA3633),
    amber: Color(0xFFE3B341),
    amberBg: Color(0x33D29922),
    amberBorder: Color(0xFFD29922),
    headerGrad: LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFF0C3A63), Color(0xFF103B2C)],
    ),
    deviceGrad: LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFF10231A), Color(0xFF0E2236)],
    ),
    deviceBorder: Color(0xFF1F3A4D),
    deviceHeading: Color(0xFF58A6FF),
    weekendBg: Color(0xFF21262D),
    weekendText: Color(0xFF6E7681),
  );
}

/// Builds a real Flutter ThemeData from an AppColors instance. Without
/// this, standard Material widgets (TextField, Chip, SwitchListTile...)
/// fall back to Flutter's own default light theme regardless of our
/// dark/light toggle — which is why input text was invisible on a dark
/// background: it was always rendering as default (black) text.
extension AppColorsTheming on AppColors {
  ThemeData themeData(Brightness brightness) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: cardBg,
      canvasColor: cardBg,
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
      primaryTextTheme: base.primaryTextTheme.apply(bodyColor: ink, displayColor: ink),
      colorScheme: base.colorScheme.copyWith(
        primary: primary,
        secondary: primary,
        surface: cardBg,
        onSurface: ink,
        error: red,
      ),
      inputDecorationTheme: InputDecorationTheme(
        labelStyle: TextStyle(color: muted),
        floatingLabelStyle: TextStyle(color: primary),
        hintStyle: TextStyle(color: muted2),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: border)),
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: primary, width: 2)),
      ),
      iconTheme: base.iconTheme.copyWith(color: ink),
    );
  }
}