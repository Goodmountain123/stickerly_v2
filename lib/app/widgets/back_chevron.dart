import 'package:flutter/material.dart';

class BackChevronGraphic extends StatelessWidget {
  const BackChevronGraphic({this.width = 24, this.height = 24, this.color = const Color(0xCC2B2540), super.key});

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _BackChevronPainter(color),
      ),
    );
  }
}

class _BackChevronPainter extends CustomPainter {
  _BackChevronPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    // Draw a chevron path from top-right to center-left to bottom-right
    path.moveTo(size.width * 0.68, size.height * 0.12);
    path.lineTo(size.width * 0.32, size.height * 0.5);
    path.lineTo(size.width * 0.68, size.height * 0.88);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
