import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GpsScreen extends StatelessWidget {
  const GpsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              // "Mapa" estilizado (placeholder do protótipo)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      BrandColors.forest.withValues(alpha: 0.10),
                      BrandColors.info.withValues(alpha: 0.06),
                    ],
                  ),
                ),
                child: CustomPaint(painter: _GridPainter(), child: const SizedBox.expand()),
              ),
              const Positioned(
                  left: 80, top: 90, child: _Marker(Icons.groups, BrandColors.forest, 'Alpha')),
              const Positioned(
                  right: 120, top: 160, child: _Marker(Icons.groups, BrandColors.forest, 'Bravo')),
              const Positioned(
                  left: 200, bottom: 140, child: _Marker(Icons.groups, BrandColors.forest, 'Charlie')),
              const Positioned(
                  right: 80, top: 70, child: _Marker(Icons.local_shipping, BrandColors.info, 'Scania')),
              const Positioned(
                  left: 120, bottom: 220, child: _Marker(Icons.local_shipping, BrandColors.info, 'Volvo')),
              Positioned(
                right: 16,
                bottom: 16,
                child: Column(
                  children: [
                    FloatingActionButton.small(
                        heroTag: 'zin',
                        onPressed: () {},
                        child: const Icon(Icons.add)),
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                        heroTag: 'zout',
                        onPressed: () {},
                        child: const Icon(Icons.remove)),
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                        heroTag: 'loc',
                        onPressed: () {},
                        child: const Icon(Icons.my_location)),
                  ],
                ),
              ),
              Positioned(
                left: 16,
                top: 16,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        _LegendRow(BrandColors.forest, 'Equipes (3)'),
                        SizedBox(height: 6),
                        _LegendRow(BrandColors.info, 'Caminhões (5)'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Marker extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _Marker(this.icon, this.color, this.label);
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 2),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(6)),
          child: Text(label,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendRow(this.color, this.label);
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    ]);
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.15)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
