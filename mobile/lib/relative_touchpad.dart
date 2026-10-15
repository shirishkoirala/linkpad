import 'package:flutter/material.dart';

class RelativeTouchpad extends StatefulWidget {
  const RelativeTouchpad({
    super.key,
    required this.enabled,
    required this.onMove,
    this.onClick,
    this.onScroll,
    required this.child,
  });
  final bool enabled;
  final void Function(double dx, double dy) onMove;
  final void Function(String button)? onClick;
  final void Function(double dx, double dy)? onScroll;
  final Widget child;

  @override
  State<RelativeTouchpad> createState() => _RelativeTouchpadState();
}

class _RelativeTouchpadState extends State<RelativeTouchpad> {
  final _origins = <int, Offset>{};
  final _positions = <int, Offset>{};
  Offset? _scrollLast;
  int? _primary;
  Offset? _lastSent;
  Duration _started = Duration.zero;
  int _peakFingers = 0;
  bool _tap = true;
  bool _cancelled = false;

  void _reset() {
    _origins.clear();
    _positions.clear();
    _scrollLast = null;
    _primary = null;
    _lastSent = null;
    _peakFingers = 0;
    _tap = true;
    _cancelled = false;
  }

  @override
  void didUpdateWidget(RelativeTouchpad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _reset();
  }

  void _down(PointerDownEvent event) {
    if (!widget.enabled) return;
    if (_origins.isEmpty) {
      _reset();
      _started = event.timeStamp;
      _primary = event.pointer;
      _lastSent = event.localPosition;
    } else if (event.timeStamp - _started > const Duration(milliseconds: 150)) {
      _tap = false;
    }
    _origins[event.pointer] = event.localPosition;
    _positions[event.pointer] = event.localPosition;
    if (_positions.length == 2) _scrollLast = _centroid;
    if (_origins.length > _peakFingers) _peakFingers = _origins.length;
    if (_peakFingers > 2) _tap = false;
  }

  Offset get _centroid =>
      _positions.values.reduce((a, b) => a + b) / _positions.length.toDouble();

  void _move(PointerMoveEvent event) {
    final origin = _origins[event.pointer];
    if (!widget.enabled || origin == null) return;
    _positions[event.pointer] = event.localPosition;
    if ((event.localPosition - origin).distance > 6) _tap = false;
    if (!_tap &&
        _peakFingers == 2 &&
        _positions.length == 2 &&
        _scrollLast != null) {
      final center = _centroid;
      final delta = center - _scrollLast!;
      _scrollLast = center;
      widget.onScroll?.call(delta.dx, delta.dy);
      return;
    }
    // Tiny movements belong to a tap. Two-finger contacts never move the cursor.
    if (_tap || _peakFingers != 1 || event.pointer != _primary) return;
    final delta = event.localPosition - _lastSent!;
    _lastSent = event.localPosition;
    widget.onMove(delta.dx, delta.dy);
  }

  void _end(PointerEvent event, {bool cancelled = false}) {
    if (!_origins.containsKey(event.pointer)) return;
    _cancelled = _cancelled || cancelled;
    final origin = _origins.remove(event.pointer)!;
    _positions.remove(event.pointer);
    _scrollLast = null;
    if ((event.localPosition - origin).distance > 6) _tap = false;
    if (_origins.isNotEmpty) return;
    if (widget.enabled &&
        _tap &&
        !_cancelled &&
        event.timeStamp - _started <= const Duration(milliseconds: 300)) {
      widget.onClick?.call(_peakFingers == 2 ? 'right' : 'left');
    }
    _reset();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _end,
    onPointerCancel: (event) => _end(event, cancelled: true),
    child: widget.child,
  );
}
