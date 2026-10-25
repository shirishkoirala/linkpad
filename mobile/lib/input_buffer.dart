import 'dart:collection';

class PointerInput {
  const PointerInput(this.dx, this.dy, [this.button, this.isScroll = false]);
  final int dx;
  final int dy;
  final String? button;
  final bool isScroll;
}

class _Input {
  _Input(this.created, this.dx, this.dy, this.button, [this.isScroll = false]);
  final Duration created;
  double dx;
  double dy;
  final String? button;
  final bool isScroll;
}

/// Bounded, ordered input with a monotonic age limit. Never survives a session.
class InputBuffer {
  InputBuffer({this.maxAge = const Duration(milliseconds: 150)});
  final Duration maxAge;
  final _queue = Queue<_Input>();

  void clear() => _queue.clear();

  void _expire(Duration now) {
    while (_queue.isNotEmpty && now - _queue.first.created >= maxAge) {
      _queue.removeFirst();
    }
  }

  void move(double dx, double dy, Duration now) {
    _motion(dx, dy, now, false);
  }

  void scroll(double dx, double dy, Duration now) {
    _motion(dx, dy, now, true);
  }

  void _motion(double dx, double dy, Duration now, bool isScroll) {
    if (!dx.isFinite || !dy.isFinite) return;
    _expire(now);
    if (_queue.isEmpty ||
        _queue.last.button != null ||
        _queue.last.isScroll != isScroll) {
      if (_queue.length >= 32) return;
      _queue.add(_Input(now, 0, 0, null, isScroll));
    }
    final motion = _queue.last;
    // Bound backlog even if the caller produces implausibly large deltas.
    motion.dx = (motion.dx + dx.clamp(-500, 500)).clamp(-500, 500).toDouble();
    motion.dy = (motion.dy + dy.clamp(-500, 500)).clamp(-500, 500).toDouble();
  }

  void click(String button, Duration now) {
    if (button != 'left' && button != 'right') return;
    _expire(now);
    if (_queue.length >= 32 ||
        _queue.where((input) => input.button != null).length >= 8) {
      return;
    }
    _queue.add(_Input(now, 0, 0, button));
  }

  bool hasReady(Duration now) {
    _expire(now);
    // A subpixel remainder must not obstruct a later click.
    while (_queue.length > 1 &&
        _queue.first.button == null &&
        _queue.first.dx.abs() < 1 &&
        _queue.first.dy.abs() < 1) {
      _queue.removeFirst();
    }
    return _queue.isNotEmpty &&
        (_queue.first.button != null ||
            _queue.first.dx.abs() >= 1 ||
            _queue.first.dy.abs() >= 1);
  }

  bool hasMotionReady(Duration now) =>
      hasReady(now) && _queue.first.button == null && !_queue.first.isScroll;

  PointerInput? take(Duration now) {
    if (!hasReady(now)) return null;
    final input = _queue.first;
    if (input.button != null) {
      _queue.removeFirst();
      return PointerInput(0, 0, input.button);
    }
    final dx = input.dx.truncate();
    final dy = input.dy.truncate();
    input.dx -= dx;
    input.dy -= dy;
    if (input.dx == 0 && input.dy == 0) _queue.removeFirst();
    return PointerInput(dx, dy, null, input.isScroll);
  }
}
