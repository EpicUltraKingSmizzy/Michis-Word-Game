import 'package:material_ui/material_ui.dart';

/// Colours and text styles for the chunky, playful look.
abstract final class MwgColors {
  static const skyTop = Color(0xFF5BC8F5);
  static const periwinkle = Color(0xFF6A7BFF);
  static const purpleBottom = Color(0xFF7B61FF);
  static const tile = Color(0xFF3B0F5C);
  static const tileEdge = Color(0xFF220734);
  static const tileSelected = Color(0xFF7A1FC2);
  static const tileSelectedEdge = Color(0xFF4E0F80);
  static const pink = Color(0xFFFFC2EC);
  static const orange = Color(0xFFE8890C);
  static const mint = Color(0xFF7FF0A8);
  static const green = Color(0xFF2EF58A);
  static const greenEdge = Color(0xFF16A85A);
  static const red = Color(0xFFE5484D);
  static const pill = Color(0xFF3B0F5C);
  static const card = Color(0x8C12245E);
  static const cardBorder = Color(0x33FFFFFF);
  static const cyan = Color(0xFFA6F3FF);
  static const navy = Color(0xFF101A4A);
  static const magenta = Color(0xFF9A1E8C);
  static const gold = Color(0xFFFFD34E);
  static const ribbon = Color(0xFF27C36A);

  /// Grey-silver for words the player missed (tiles, line and label).
  static const silver = Color(0xFFC9CED6);
  static const silverEdge = Color(0xFF8D94A0);
  static const silverLine = Color(0xFFEDEFF3);
}

const String fontUi = 'Fredoka';
const String fontTile = 'Montserrat';

TextStyle uiText(double size, {FontWeight weight = FontWeight.w600, Color color = Colors.white}) =>
    TextStyle(fontFamily: fontUi, fontSize: size, fontWeight: weight, color: color, height: 1.15);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: fontUi,
    colorScheme: ColorScheme.fromSeed(
      seedColor: MwgColors.purpleBottom,
      brightness: Brightness.dark,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    textTheme: base.textTheme.apply(fontFamily: fontUi, bodyColor: Colors.white, displayColor: Colors.white),
    sliderTheme: const SliderThemeData(
      activeTrackColor: MwgColors.cyan,
      inactiveTrackColor: Color(0xFF0B1640),
      thumbColor: MwgColors.cyan,
      overlayColor: Color(0x33A6F3FF),
      trackHeight: 10,
      valueIndicatorColor: MwgColors.pill,
    ),
  );
}

const gameGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [MwgColors.skyTop, MwgColors.periwinkle, MwgColors.purpleBottom],
);

const resultsGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [MwgColors.navy, Color(0xFF3A1F78), MwgColors.magenta],
);
