import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Clips both painting and hit testing to one quarter of the D-pad ring.
class DpadSector extends StatelessWidget {
  const DpadSector({
    super.key,
    required this.direction,
    required this.innerRadius,
    required this.child,
  });
  final String direction;
  final double innerRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ClipPath(clipper: _SectorClipper(direction, innerRadius), child: child);
}

Path _sectorPath(Size size, String direction, double innerRadius) {
  final start = switch (direction) {
    'up' => -3 * math.pi / 4,
    'right' => -math.pi / 4,
    'down' => math.pi / 4,
    'left' => 3 * math.pi / 4,
    _ => throw ArgumentError.value(direction, 'direction'),
  };
  final center = size.center(Offset.zero);
  final outer = math.min(size.width, size.height) / 2;
  final end = start + math.pi / 2;
  return Path()
    ..moveTo(
      center.dx + math.cos(start) * outer,
      center.dy + math.sin(start) * outer,
    )
    ..arcTo(
      Rect.fromCircle(center: center, radius: outer),
      start,
      math.pi / 2,
      false,
    )
    ..lineTo(
      center.dx + math.cos(end) * innerRadius,
      center.dy + math.sin(end) * innerRadius,
    )
    ..arcTo(
      Rect.fromCircle(center: center, radius: innerRadius),
      end,
      -math.pi / 2,
      false,
    )
    ..close();
}

class _SectorClipper extends CustomClipper<Path> {
  const _SectorClipper(this.direction, this.innerRadius);
  final String direction;
  final double innerRadius;
  @override
  Path getClip(Size size) => _sectorPath(size, direction, innerRadius);
  @override
  bool shouldReclip(_SectorClipper old) =>
      old.direction != direction || old.innerRadius != innerRadius;
}
