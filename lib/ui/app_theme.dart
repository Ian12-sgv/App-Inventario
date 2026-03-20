import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  static const Color navy = Color(0xFF162538);
  static const Color gold = Color(0xFF1778F2);
  static const Color bannerBlue = Color(0xFF0C4F8B);
  static const Color royalBlue = Color(0xFF0C4F8B);
  static const Color bg = Color(0xFFF2F3F5);
  static const Color green = Color(0xFF1F9D55);
  static const Color red = Color(0xFFB42318);
  static const SystemUiOverlayStyle bannerOverlay = SystemUiOverlayStyle(
    statusBarColor: bannerBlue,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);

    final scheme = base.colorScheme.copyWith(
      primary: gold,
      onPrimary: Colors.white,
      secondary: gold,
      onSecondary: Colors.white,
      surface: Colors.white,
      onSurface: navy,
    );

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: scheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: bannerBlue,
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        systemOverlayStyle: bannerOverlay,
        toolbarHeight: 70,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 24,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: gold,
          side: const BorderSide(color: gold, width: 1.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: navy,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        modalBackgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        showDragHandle: true,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.resolveWith<Color?>(
            (states) =>
                states.contains(MaterialState.selected) ? gold : Colors.white,
          ),
          foregroundColor: MaterialStateProperty.resolveWith<Color?>(
            (states) =>
                states.contains(MaterialState.selected) ? Colors.white : navy,
          ),
          side: MaterialStateProperty.resolveWith<BorderSide?>(
            (states) => BorderSide(
              color: states.contains(MaterialState.selected)
                  ? gold
                  : const Color(0xFFD6DCE4),
              width: 1.2,
            ),
          ),
          textStyle: MaterialStateProperty.all(
            const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
          ),
          padding: MaterialStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF2F4F7),
        selectedColor: gold,
        secondarySelectedColor: gold,
        disabledColor: const Color(0xFFE5E7EB),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: const TextStyle(color: navy, fontWeight: FontWeight.w900),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
        brightness: Brightness.light,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 60,
        backgroundColor: Colors.white,
        elevation: 0,
        indicatorColor: const Color(0xFFEAF2FF),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: MaterialStateProperty.resolveWith<IconThemeData>((states) {
          final selected = states.contains(MaterialState.selected);
          return IconThemeData(
            color: selected ? navy : const Color(0xFF9AA3AE),
            size: 24,
          );
        }),
        labelTextStyle: MaterialStateProperty.resolveWith<TextStyle>((states) {
          final selected = states.contains(MaterialState.selected);
          return TextStyle(
            color: selected ? navy : const Color(0xFF9AA3AE),
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            fontSize: 11,
          );
        }),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        elevation: 0,
        selectedItemColor: navy,
        unselectedItemColor: Color(0xFF9AA3AE),
        selectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
    );
  }
}
