import 'package:flutter/material.dart';
import 'package:stickerly_v2/app/theme/stickerly_colors.dart';
import 'package:stickerly_v2/app/theme/stickerly_spacing.dart';

abstract final class StickerlyTheme {
  static ThemeData light() {
    const colorScheme = ColorScheme.light(
      primary: StickerlyColors.pink,
      onPrimary: Colors.white,
      secondary: StickerlyColors.purple,
      onSecondary: Colors.white,
      error: StickerlyColors.danger,
      onError: Colors.white,
      surface: StickerlyColors.surface,
      onSurface: StickerlyColors.ink,
      outline: StickerlyColors.line,
    );

    final baseTextTheme = ThemeData.light().textTheme.apply(
      fontFamily: 'MemomentKkukkukk',
      bodyColor: StickerlyColors.ink,
      displayColor: StickerlyColors.ink,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: StickerlyColors.paper,
      fontFamily: 'MemomentKkukkukk',
      fontFamilyFallback: const ['MemomentKkukkukk'],
      textTheme: baseTextTheme,
      primaryTextTheme: baseTextTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: StickerlyColors.paper,
        foregroundColor: StickerlyColors.ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(
        color: StickerlyColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(StickerlyRadii.large)),
          side: BorderSide(color: StickerlyColors.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: StickerlyColors.pink,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(StickerlyRadii.medium),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
