import 'package:flutter/material.dart';

abstract final class StickerlyTextStyles {
  static const wordmark = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1,
  );

  static const screenTitle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
  );

  static const cardTitle = TextStyle(fontSize: 18, fontWeight: FontWeight.w700);

  static const body = TextStyle(fontSize: 16, height: 1.35);

  static const caption = TextStyle(fontSize: 13, height: 1.3);
}
