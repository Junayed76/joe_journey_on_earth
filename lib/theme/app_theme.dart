import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppColors {
  static bool isDark = false;

  static const Color appBarBg = Color(0xFF211A26);
  static const Color appBarText = Colors.white;

  static Color get background => isDark ? const Color(0xFF0F0D17) : const Color(0xFFF7F5F1);

  // Card এখন app bar-এর চেয়ে সামান্য হালকা shade — background থেকে আলাদা বোঝা যাবে
  static Color get surface => isDark ? const Color(0xFF2C2333) : const Color(0xFFFFFFFF);

  static Color get textDark => isDark ? const Color(0xFFF0EAE0) : const Color(0xFF2A2420);
  static Color get textMuted => isDark ? const Color(0xFFB8AFA0) : const Color(0xFF6E655A);

  static const Color terracotta = Color(0xFFBE9158);
  static const Color chipBg = Color(0xFFE0B788);

  // Date badge — dark mode-এ আলাদা, নিজস্ব contrast
  static Color get dateBadgeBg => isDark ? terracotta.withOpacity(0.22) : chipBg;
  static Color get dateBadgeText => isDark ? terracotta : appBarBg;

  // Card-এ dark mode-এ subtle border (shadow দেখা না গেলেও depth বোঝাতে)
  static Color get cardBorder => isDark ? Colors.white.withOpacity(0.07) : Colors.transparent;
  static Color get cardShadow => isDark ? Colors.black.withOpacity(0.5) : Colors.black.withOpacity(0.12);

  static Color get terracottaSoft => chipBg;
  static Color get sage => terracotta;
  static Color get sageSoft => surface;
  static Color get blush => terracotta;
  static Color get blushSoft => surface;
  static Color get olive => terracotta;
  static Color get oliveSoft => surface;
  static Color get streakAccent => terracotta;

  static List<Color> get cardColors => [surface];
  static List<Color> get cardAccents => [terracotta];
}
class AppTheme {
  static final ValueNotifier<int> rebuildNotifier = ValueNotifier(0);

  static Future<void> loadSavedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    AppColors.isDark = prefs.getBool('dark_mode') ?? false;
  }

  static Future<void> toggleDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', value);
    AppColors.isDark = value;
    rebuildNotifier.value++;
  }

  static ThemeData get theme {
    return ThemeData(
      brightness: AppColors.isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.terracotta,
        brightness: AppColors.isDark ? Brightness.dark : Brightness.light,
        surface: AppColors.background,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.appBarBg,
        elevation: 2,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.appBarText),
        titleTextStyle: GoogleFonts.spaceGrotesk(
          color: AppColors.appBarText,
          fontSize: 19,
          fontWeight: FontWeight.w600,
        ),
      ),
      textTheme: TextTheme(
        headlineSmall: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: AppColors.textDark),
        titleMedium: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.textDark),
        bodyMedium: GoogleFonts.inter(fontWeight: FontWeight.w400, color: AppColors.textDark, height: 1.5),
        bodySmall: GoogleFonts.inter(fontWeight: FontWeight.w400, color: AppColors.textMuted),
      ),
      cardTheme: CardThemeData(
        elevation: 4,
        surfaceTintColor: Colors.transparent, // এটাই shadow invisible হওয়ার আসল কারণ ছিল
        shadowColor: Colors.black.withValues(alpha: 0.3),
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.terracotta,
          foregroundColor: AppColors.isDark ? Colors.black : Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
      chipTheme: ChipThemeData(
      backgroundColor: AppColors.chipBg,
      selectedColor: AppColors.terracotta,
      labelStyle: TextStyle(fontSize: 13, color: AppColors.appBarBg, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide.none,
    ),
      useMaterial3: true,
    );
  }
}