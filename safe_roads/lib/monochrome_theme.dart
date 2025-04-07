import 'package:flutter/material.dart';

final ColorScheme monochromeColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Colors.black,
  onPrimary: Colors.white,
  secondary: Colors.grey[300]!,
  onSecondary: Colors.black,
  error: Colors.red,
  onError: Colors.white,
  surface: Colors.grey[50]!,
  onSurface: Colors.black,
);

final ThemeData monochromeTheme = ThemeData(
  colorScheme: monochromeColorScheme,
  useMaterial3: true,
  scaffoldBackgroundColor: monochromeColorScheme.surface,
  appBarTheme: AppBarTheme(
    backgroundColor: monochromeColorScheme.primary,
    foregroundColor: monochromeColorScheme.onPrimary,
    elevation: 0,
  ),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: monochromeColorScheme.secondary,
    foregroundColor: monochromeColorScheme.onSecondary,
  ),
  textTheme: ThemeData.light().textTheme.apply(
        bodyColor: Colors.black,
        displayColor: Colors.black,
      ),
);
