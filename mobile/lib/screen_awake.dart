import 'dart:io';
import 'package:flutter/services.dart';
import 'cursor_settings.dart';
import 'peer_client.dart';

/// Serializes wake requests, releasing them on background, disconnect, or exit.
class ScreenAwakeController {
  ScreenAwakeController({
    required this.settings,
    required this.peer,
    required bool foreground,
    Future<void> Function(bool)? apply,
    bool? supported,
  }) : _foreground = foreground,
       _apply = apply ?? _nativeApply,
       _supported = supported ?? (Platform.isIOS || Platform.isAndroid) {
    settings.addListener(_sync);
    peer.addListener(_sync);
    _sync();
  }
  final CursorSettings settings;
  final PeerClient peer;
  final Future<void> Function(bool) _apply;
  final bool _supported;
  bool _foreground, _disposed = false;
  bool? _requested;
  int _generation = 0;
  Future<void> _pending = Future<void>.value();
  Future<void> get settled => _pending;

  static Future<void> _nativeApply(bool enabled) => const MethodChannel(
    'linkpad/screen',
  ).invokeMethod<void>('setKeepScreenAwake', {'enabled': enabled});

  void setForeground(bool value) {
    _foreground = value;
    _sync();
  }

  void _sync() {
    if (_disposed || !_supported) return;
    final enabled = _foreground && peer.connected && settings.keepScreenAwake;
    if (_requested == enabled) return;
    _requested = enabled;
    final generation = ++_generation;
    _pending = _pending.then((_) async {
      if (_disposed || generation != _generation) return;
      try {
        await _apply(enabled);
        if (!_disposed && generation == _generation) {
          settings.reportAwakeWarning(null);
        }
      } catch (_) {
        if (!_disposed && generation == _generation) {
          settings.reportAwakeWarning(
            'Could not change screen sleep. Toggle Keep screen awake to try again.',
          );
        }
      }
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    settings.removeListener(_sync);
    peer.removeListener(_sync);
    if (_supported) {
      _pending = _pending.then((_) async {
        try {
          await _apply(false);
        } catch (_) {
          /* Native activity lifecycle also releases the flag. */
        }
      });
    }
  }
}
