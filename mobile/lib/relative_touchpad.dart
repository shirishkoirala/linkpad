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
    if (oldWidget.enabled != widget.enabled) {
      // A network pause does not lift the user's fingers. Keep their contact
      // identities, but never resume an interrupted tap or replay movement.
      _tap = false;
      _lastSent = null;
      _scrollLast = null;
    }
  }

  void _down(PointerDownEvent event) {
    if (_origins.isEmpty) {
      _reset();
      _started = event.timeStamp;
      _primary = event.pointer;
      _lastSent = event.position;
    } else if (event.timeStamp - _started > const Duration(milliseconds: 150)) {
      _tap = false;
    }
    _origins[event.pointer] = event.position;
    _positions[event.pointer] = event.position;
    if (_positions.length == 2) _scrollLast = _centroid;
    if (_origins.length > _peakFingers) _peakFingers = _origins.length;
    if (_peakFingers > 2) _tap = false;
    if (!widget.enabled) _tap = false;
  }

  Offset get _centroid =>
      _positions.values.reduce((a, b) => a + b) / _positions.length.toDouble();

  void _move(PointerMoveEvent event) {
    final origin = _origins[event.pointer];
    if (origin == null) return;
    _positions[event.pointer] = event.position;
    if ((event.position - origin).distance > 6) _tap = false;
    if (!widget.enabled) return;
    if (!_tap && _peakFingers == 2 && _positions.length == 2) {
      final center = _centroid;
      final previous = _scrollLast;
      _scrollLast = center;
      if (previous != null) {
        final delta = center - previous;
        widget.onScroll?.call(delta.dx, delta.dy);
      }
      return;
    }
    // Tiny movements belong to a tap. Two-finger contacts never move the cursor.
    if (_tap || _peakFingers != 1 || event.pointer != _primary) return;
    final previous = _lastSent;
    _lastSent = event.position;
    if (previous == null) return;
    final delta = event.position - previous;
    widget.onMove(delta.dx, delta.dy);
  }

  void _end(PointerEvent event, {bool cancelled = false}) {
    if (!_origins.containsKey(event.pointer)) return;
    _cancelled = _cancelled || cancelled;
    final origin = _origins.remove(event.pointer)!;
    _positions.remove(event.pointer);
    _scrollLast = null;
    if ((event.position - origin).distance > 6) _tap = false;
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
