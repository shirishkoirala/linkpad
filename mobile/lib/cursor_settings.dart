import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CursorSettings extends ChangeNotifier {
  CursorSettings({FlutterSecureStorage storage = const FlutterSecureStorage()})
    : _storage = storage;

  static const storageKey = 'cursor_sensitivity_v1';
  static const minimum = 0.25, maximum = 3.0, defaultSensitivity = 1.0;
  final FlutterSecureStorage _storage;
  double _sensitivity = defaultSensitivity;
  int _revision = 0;
  bool _disposed = false;
  Future<void> _writes = Future<void>.value();
  String? warning;

  double get sensitivity => _sensitivity;
  String get label => '${(_sensitivity * 100).round()}%';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    final revision = _revision;
    try {
      final raw = await _storage.read(key: storageKey);
      if (_disposed || _revision != revision) return;
      final value = double.tryParse(raw ?? '');
      if (value != null &&
          value.isFinite &&
          value >= minimum &&
          value <= maximum) {
        _sensitivity = value;
        _notify();
      }
    } catch (_) {
      if (!_disposed && _revision == revision) {
        warning =
            'Could not load cursor settings. Using the default sensitivity.';
        _notify();
      }
    }
  }

  void setSensitivity(double value) {
    if (!value.isFinite) return;
    _revision++;
    _sensitivity = value.clamp(minimum, maximum);
    warning = null;
    _notify();
  }

  Future<void> save() {
    final value = _sensitivity;
    _writes = _writes.then((_) async {
      try {
        await _storage.write(key: storageKey, value: value.toString());
        warning = null;
      } catch (_) {
        warning =
            'Sensitivity changed for now, but could not be saved. Try again.';
      }
      _notify();
    });
    return _writes;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
