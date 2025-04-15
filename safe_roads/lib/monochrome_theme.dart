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

final ColorScheme monochromeDarkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Colors.white,
  onPrimary: Colors.black,
  secondary: Colors.grey[800]!,
  onSecondary: Colors.white,
  error: Colors.red[400]!,
  onError: Colors.black,
  surface: Colors.grey[900]!,
  onSurface: Colors.white,
);

final ThemeData monochromeDarkTheme = ThemeData(
  colorScheme: monochromeDarkColorScheme,
  useMaterial3: true,
  scaffoldBackgroundColor: monochromeDarkColorScheme.surface,
  appBarTheme: AppBarTheme(
    backgroundColor: monochromeDarkColorScheme.primary,
    foregroundColor: monochromeDarkColorScheme.onPrimary,
    elevation: 0,
  ),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: monochromeDarkColorScheme.secondary,
    foregroundColor: monochromeDarkColorScheme.onSecondary,
  ),
  textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
);