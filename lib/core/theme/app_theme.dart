import 'package:flutter/material.dart';

class AppTheme {
  // BeatBoss Color Palette
  static const Color primaryGreen = Color(0xFF1DB954);
  static const Color darkBackground = Color(0xFF020202);
  static const Color darkSidebar = Color(0xFF0A0A0A);
  static const Color darkCard = Color(0xFF1A1A1A);
  static const Color lightBackground = Color(0xFFF0F0F3); // Darker off-white
  static const Color lightSidebar = Color(0xFFE8E8EB);
  static const Color lightCard =
      Color(0xFFFFFFFF); // Keep cards white for contrast, background is darker

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primaryGreen,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: primaryGreen,
        secondary: primaryGreen,
        surface: darkCard,
        background: darkBackground,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      iconTheme: const IconThemeData(color: Colors.white70),
      textTheme: const TextTheme(
        headlineLarge:
            TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        headlineMedium:
            TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: Colors.white),
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white70),
        bodySmall: TextStyle(color: Colors.white30),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primaryGreen,
        inactiveTrackColor: Colors.white10,
        thumbColor: primaryGreen,
        overlayColor: primaryGreen.withOpacity(0.2),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        trackHeight: 4,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.black,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: primaryGreen),
        ),
        hintStyle: const TextStyle(color: Colors.white30),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkCard.withOpacity(0.95),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: primaryGreen,
        contentTextStyle: const TextStyle(color: Colors.black),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primaryGreen,
      scaffoldBackgroundColor: lightBackground,
      colorScheme: const ColorScheme.light(
        primary: primaryGreen,
        secondary: primaryGreen,
        surface: lightCard,
        background: lightBackground,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: lightBackground,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.black,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: Colors.black87),
      ),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      iconTheme: const IconThemeData(color: Colors.black54),
      textTheme: const TextTheme(
        headlineLarge:
            TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        headlineMedium:
            TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        titleLarge: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: Colors.black, fontSize: 17),
        bodyLarge: TextStyle(color: Colors.black, fontSize: 17),
        bodyMedium: TextStyle(
            color: Colors.black87, fontSize: 15), // Darker for readability
        bodySmall: TextStyle(color: Colors.black54), // Darker for readability
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primaryGreen,
        inactiveTrackColor: Colors.black12,
        thumbColor: primaryGreen,
        overlayColor: primaryGreen.withOpacity(0.2),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        trackHeight: 4,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.black,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightSidebar,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: primaryGreen),
        ),
        hintStyle: const TextStyle(color: Colors.black38),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: lightCard.withOpacity(0.95),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: primaryGreen,
        contentTextStyle: const TextStyle(color: Colors.black),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
