import 'package:flutter/material.dart';
import 'package:stickerly_v2/app/theme/stickerly_colors.dart';

class StickerlyWordmark extends StatelessWidget {
  const StickerlyWordmark({this.scale = 1, super.key});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final baseSize = 32.0 * scale;
    const letterSpacing = -1.28;
    final baseStyle = TextStyle(
      color: Colors.black,
      fontSize: baseSize,
      fontWeight: FontWeight.normal,
      letterSpacing: letterSpacing,
      fontFamily: 'MemomentKkukkukk',
    );

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          const TextSpan(text: 'Stickerly'),
          TextSpan(
            text: '.',
            style: baseStyle.copyWith(color: StickerlyColors.pink),
          ),
        ],
      ),
    );
  }
}
