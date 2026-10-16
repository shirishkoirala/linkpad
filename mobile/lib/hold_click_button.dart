import 'package:flutter/material.dart';

/// Pointer contacts hold the button; keyboard and accessibility activation click.
class HoldClickButton extends StatefulWidget {
  const HoldClickButton({
    super.key,
    required this.enabled,
    required this.supportsDrag,
    required this.holding,
    required this.onStart,
    required this.onEnd,
    required this.onCancel,
    required this.onClick,
  });
  final bool enabled, supportsDrag, holding;
  final VoidCallback onStart, onEnd, onCancel, onClick;
  @override
  State<HoldClickButton> createState() => _HoldClickButtonState();
}

class _HoldClickButtonState extends State<HoldClickButton> {
  int? _pointer;
  bool _pointerTap = false;
  void _down(PointerDownEvent event) {
    if (!widget.enabled || !widget.supportsDrag || _pointer != null) return;
    _pointer = event.pointer;
    _pointerTap = true;
    widget.onStart();
  }

  void _up(PointerEvent event, {bool cancelled = false}) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    if (cancelled) {
      widget.onCancel();
    } else {
      widget.onEnd();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pointer == null) _pointerTap = false;
    });
  }

  @override
  void dispose() {
    if (_pointer != null) {
      final end = widget.onCancel;
      WidgetsBinding.instance.addPostFrameCallback((_) => end());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: widget.supportsDrag
          ? 'Hold here while moving on the touchpad to drag'
          : 'Left click. Update the desktop server to enable dragging.',
      child: Listener(
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: (event) => _up(event, cancelled: true),
        child: FilledButton.tonal(
          onPressed: widget.enabled
              ? () {
                  if (!_pointerTap) widget.onClick();
                }
              : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            backgroundColor: widget.holding
                ? colors.primary
                : colors.surfaceContainerHighest,
            foregroundColor: widget.holding
                ? colors.onPrimary
                : colors.onSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            widget.holding ? 'Holding left · Drag' : 'Left click',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    );
  }
}
