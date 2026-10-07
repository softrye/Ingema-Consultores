import 'package:flutter/painting.dart';

/// Identidad corporativa oficial INGEMA para las superficies Flutter.
///
/// Fuente normativa: Manual Corporativo Ingema 2025, "05 Elementos graficos >
/// Colores" y "Tipografias". Es el equivalente exacto de
/// qml/Mobile/flowcore/FlowColors.qml (QML) y de las variables --ingema-* de
/// android/web/inge-ai/src/inge/liquid-glass.scss (IA web). No agregar aqui
/// colores de marca que no esten en el manual.
abstract final class IngemaBrand {
  // Paleta oficial.
  static const deep = Color(0xff151a30); // RGB 21, 26, 48
  static const navy = Color(0xff1c2d50); // RGB 28, 45, 80
  static const blue = Color(0xff0654a2); // RGB 6, 84, 162
  static const green = Color(0xff486426); // RGB 72, 100, 38

  // Derivados por mezcla con blanco/negro (contraste WCAG); no son colores de
  // marca nuevos. Mismos valores que FlowColors.qml.
  static const deepShade = Color(0xff111527); // Deep + 18 % negro
  static const blueTint = Color(0xff8fb2d5); // Blue + 55 % blanco
  static const greenTint = Color(0xffadb99d); // Green + 55 % blanco
  static const blueWash = Color(0xffebf1f8); // Blue 8 % sobre blanco
  static const greenWash = Color(0xffedf0e9); // Green 10 % sobre blanco

  // Escala de texto Light: INGEMA Deep con alpha aplanado sobre blanco.
  static const inkSecondary = Color(0xff575a6a);
  static const inkTertiary = Color(0xff656876);
  static const inkDisabled = Color(0xffa6a8b0);

  // Escala Dark: blanco aplanado sobre INGEMA Deep.
  static const paperPrimary = Color(0xfff6f6f7);
  static const paperSecondary = Color(0xffc2c3c9);
  static const paperTertiary = Color(0xff989aa4);

  // Tipografia corporativa: Rubik (assets/fonts/rubik, declarada en pubspec).
  // Semibold (w600) titulos/botones; Regular (w400) cuerpo; Light (w300)
  // solo para texto secundario grande con buen contraste.
  static const fontFamily = 'Rubik';
  static const semibold = FontWeight.w600;
  static const regular = FontWeight.w400;
  static const light = FontWeight.w300;
}
