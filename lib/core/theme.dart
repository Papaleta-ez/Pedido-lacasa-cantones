import 'package:flutter/material.dart';

const ink = Color(0xFF121212),
    imperial = Color(0xFFC8102E),
    gold = Color(0xFFD4AF37),
    jade = Color(0xFF00A86B),
    ivory = Color(0xFFFDFBF7);
final posTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: ink,
  colorScheme: ColorScheme.fromSeed(
    seedColor: gold,
    brightness: Brightness.dark,
    primary: gold,
    secondary: jade,
    surface: const Color(0xFF202020),
  ),
  textTheme: ThemeData.dark().textTheme.apply(
    bodyColor: ivory,
    displayColor: ivory,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(minimumSize: const Size(56, 56)),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(minimumSize: const Size(56, 56)),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(minimumSize: const Size(56, 56)),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(minimumSize: const Size(56, 56)),
  ),
  chipTheme: const ChipThemeData(
    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
  ),
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(),
    filled: true,
  ),
);
String money(num cents, [String currency = 'C\$']) =>
    '$currency ${(cents / 100).toStringAsFixed(2)}';
void notice(BuildContext context, Object message) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('$message')));
}
