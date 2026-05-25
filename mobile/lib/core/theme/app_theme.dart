import 'package:flutter/material.dart';

/// アプリ共通のテーマ。配色・コンポーネントの体裁を一箇所に集約する。
/// 地図のコミカル調（クリーム/緑/青）と調和する柔らかいティールを基調にする。
class AppTheme {
  AppTheme._();

  /// ブランドのシード色（つながり・場所を感じる柔らかいティール）。
  static const seed = Color(0xFF2E9E8F);

  /// ライトテーマ。
  static ThemeData light() => _build(ColorScheme.fromSeed(seedColor: seed));

  /// ダークテーマ（システム設定がダークのとき使用）。
  static ThemeData dark() => _build(
        ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
      );

  /// ColorScheme から共通の体裁で ThemeData を組み立てる。
  static ThemeData _build(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: const DividerThemeData(space: 24),
    );
  }
}
