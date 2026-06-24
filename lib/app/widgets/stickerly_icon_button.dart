import 'package:flutter/material.dart';
import 'package:stickerly_v2/app/theme/stickerly_colors.dart';
import 'package:stickerly_v2/app/theme/stickerly_spacing.dart';

class StickerlyIconButton extends StatelessWidget {
  const StickerlyIconButton({
    required this.asset,
    required this.label,
    required this.onPressed,
    this.size = 46,
    super.key,
  });

  final String asset;
  final String label;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: IconButton(
        onPressed: onPressed,
        tooltip: label,
        style: IconButton.styleFrom(
          fixedSize: Size.square(size),
          backgroundColor: StickerlyColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(StickerlyRadii.medium),
            side: const BorderSide(color: StickerlyColors.line),
          ),
        ),
        icon: Image.asset(asset, width: size * 0.58, height: size * 0.58),
      ),
    );
  }
}
