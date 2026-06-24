import 'package:flutter/material.dart';
import 'package:stickerly_v2/app/theme/stickerly_colors.dart';
import 'package:stickerly_v2/app/theme/stickerly_text_styles.dart';

class StickerlyWordmark extends StatelessWidget {
  const StickerlyWordmark({this.scale = 1, super.key});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Stickerly'),
          TextSpan(
            text: '.',
            style: StickerlyTextStyles.wordmark.copyWith(
              color: StickerlyColors.pink,
              fontSize: StickerlyTextStyles.wordmark.fontSize! * scale,
            ),
          ),
        ],
      ),
      style: StickerlyTextStyles.wordmark.copyWith(
        fontSize: StickerlyTextStyles.wordmark.fontSize! * scale,
      ),
    );
  }
}
