import 'dart:io';

import 'package:flutter/material.dart';

class AssetFileImage extends StatelessWidget {
  const AssetFileImage({
    required this.path,
    this.fit,
    this.width,
    this.height,
    this.filterQuality = FilterQuality.medium,
    super.key,
  });

  final String path;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) {
      return const ColoredBox(color: Color(0xFFF2EDF4));
    }
    if (path.startsWith('assets/')) {
      return Image.asset(
        path,
        fit: fit,
        width: width,
        height: height,
        filterQuality: filterQuality,
        frameBuilder: _keepPlaceholderUntilReady,
      );
    }
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: fit,
        width: width,
        height: height,
        filterQuality: filterQuality,
        frameBuilder: _keepPlaceholderUntilReady,
        errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFFF2EDF4)),
      );
    }
    return Image.file(
      File(path),
      fit: fit,
      width: width,
      height: height,
      filterQuality: filterQuality,
      frameBuilder: _keepPlaceholderUntilReady,
      errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFFF2EDF4)),
    );
  }

  Widget _keepPlaceholderUntilReady(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded || frame != null) return child;
    return const ColoredBox(color: Color(0xFFF2EDF4));
  }
}
