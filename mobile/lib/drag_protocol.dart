import 'dart:convert';

const dragCapability = 'drag.v1';

String dragMessage(String action, [int dx = 0, int dy = 0]) {
  if (!{'start', 'move', 'hold', 'end'}.contains(action) ||
      dx.abs() > 500 ||
      dy.abs() > 500 ||
      (action != 'move' && (dx != 0 || dy != 0))) {
    throw ArgumentError('Invalid drag input');
  }
  return jsonEncode({
    'version': 1,
    'type': 'drag',
    'action': action,
    if (dx != 0) 'dx': dx,
    if (dy != 0) 'dy': dy,
  });
}
