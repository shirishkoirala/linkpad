import 'dart:convert';

String keyboardMessage({
  String? key,
  String? text,
  Set<String> modifiers = const {},
}) {
  if ((key == null) == (text == null) ||
      modifiers.any((m) => !{'shift', 'ctrl', 'alt', 'super'}.contains(m))) {
    throw ArgumentError('Invalid keyboard input');
  }
  if (text != null &&
      (text.isEmpty ||
          text.runes.length > 128 ||
          modifiers.isNotEmpty ||
          text.runes.any((r) => r < 32 || (r >= 127 && r < 160)))) {
    throw ArgumentError('Invalid keyboard text');
  }
  const keys = {
    'up',
    'down',
    'left',
    'right',
    'enter',
    'backspace',
    'tab',
    'escape',
    'space',
    'delete',
    'home',
    'end',
    'pageup',
    'pagedown',
  };
  if (key != null &&
      !keys.contains(key) &&
      !(key.length == 1 &&
          key.codeUnitAt(0) >= 32 &&
          key.codeUnitAt(0) <= 126)) {
    throw ArgumentError('Invalid keyboard key');
  }
  return jsonEncode({
    'version': 1,
    'type': 'keyboard',
    if (key != null) 'key': key,
    if (text != null) 'text': text,
    if (modifiers.isNotEmpty) 'modifiers': modifiers.toList(),
  });
}
