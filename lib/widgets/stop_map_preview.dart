import 'package:flutter/material.dart';

import '../app_styles.dart';

/// Presentation only. Replace this widget with the chosen map/position adapter.
/// No device coordinates, distance checks, or location permissions are used.
class StopMapPreview extends StatelessWidget {
  const StopMapPreview({super.key, this.route, this.arrival, this.onBusTap});

  final String? route;
  final String? arrival;
  final VoidCallback? onBusTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, bounds) {
    return InteractiveViewer(
      minScale: 1, maxScale: 3,
      child: SizedBox(width: bounds.maxWidth, height: bounds.maxHeight,
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _StreetPainter())),
          Align(alignment: const Alignment(0.05, 0.08), child: Container(
            width: 210, height: 210,
            decoration: BoxDecoration(shape: BoxShape.circle,
              color: const Color(0x5575D6CC),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.6), width: 1.5)),
            child: const Center(child: _Marker(icon: Icons.directions_bus_rounded, color: AppColors.primary, size: 56)),
          )),
          const Align(alignment: Alignment(0.02, 0.27), child: _Marker(icon: Icons.circle, color: AppColors.routeBlue, size: 26)),
          if (route != null) Align(alignment: const Alignment(0.2, -0.35), child: Semantics(
            button: true, label: '$route번 버스 $arrival',
            child: GestureDetector(onTap: onBusTap, child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(24)),
                child: Text('$arrival 후 도착', style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w900))),
              const SizedBox(height: 8),
              const _Marker(icon: Icons.directions_bus_rounded, color: AppColors.primary, size: 46),
              Container(margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                child: Text(route!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
            ])),
          )),
          const Positioned(right: 16, top: 190, child: DecoratedBox(
            decoration: BoxDecoration(color: Colors.white70, borderRadius: BorderRadius.all(Radius.circular(12))),
            child: Padding(padding: EdgeInsets.all(8), child: Text('샘플 지도', style: TextStyle(color: AppColors.secondaryText, fontSize: 11))),
          )),
        ])),
    );
  });
}

class _Marker extends StatelessWidget {
  const _Marker({required this.icon, required this.color, required this.size});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(width: size, height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [BoxShadow(color: Color(0x2607524E), blurRadius: 12, offset: Offset(0, 4))]),
    child: Icon(icon, color: Colors.white, size: size * 0.52));
}

class _StreetPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF0F0E9));
    final park = Paint()..color = const Color(0xFFDDEACF);
    final building = Paint()..color = const Color(0xFFE1E4E4);
    for (var row = 0; row < 9; row++) {
      for (var col = 0; col < 6; col++) {
        final rect = Rect.fromLTWH(col * size.width / 5 + 9, row * size.height / 8 + 12, size.width / 5 - 23, size.height / 8 - 25);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(7)), (row + col) % 4 == 0 ? park : building);
      }
    }
    final river = Path()..moveTo(0, 0)..lineTo(size.width * 0.14, 0)
      ..cubicTo(size.width * 0.05, size.height * 0.4, size.width * 0.33, size.height * 0.5, size.width * 0.12, size.height)
      ..lineTo(0, size.height)..close();
    canvas.drawPath(river, Paint()..color = const Color(0xFFC4E2EB));
    final road = Paint()..color = Colors.white..strokeWidth = 16..strokeCap = StrokeCap.round;
    for (var i = 1; i < 8; i++) {
      final y = i * size.height / 8;
      canvas.drawLine(Offset(0, y + 45), Offset(size.width, y - 45), road);
    }
    for (var i = 1; i < 5; i++) {
      final x = i * size.width / 5;
      canvas.drawLine(Offset(x + 60, 0), Offset(x - 70, size.height), road);
    }
    final path = Path()..moveTo(size.width * 0.28, size.height)
      ..cubicTo(size.width * 0.48, size.height * 0.7, size.width * 0.55, size.height * 0.35, size.width * 0.65, 0);
    canvas.drawPath(path, Paint()..color = const Color(0xFFBCE3DD)..style = PaintingStyle.stroke..strokeWidth = 19);
    canvas.drawPath(path, Paint()..color = AppColors.primary..style = PaintingStyle.stroke..strokeWidth = 5);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
