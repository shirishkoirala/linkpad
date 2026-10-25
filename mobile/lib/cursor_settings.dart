import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'control_mode.dart';

class CursorSettings extends ChangeNotifier {
  CursorSettings({FlutterSecureStorage storage = const FlutterSecureStorage()})
    : _storage = storage;

  static const storageKey = 'cursor_sensitivity_v1';
  static const keepAwakeKey = 'keep_screen_awake_v1';
  static const controlModeKey = 'last_control_mode_v1';
  static const minimum = 0.25, maximum = 3.0, defaultSensitivity = 1.0;
  final FlutterSecureStorage _storage;
  double _sensitivity = defaultSensitivity;
  int _revision = 0;
  int _awakeRevision = 0;
  bool _keepScreenAwake = false, _awakeDirty = false;
  MobileControlMode _lastControlMode = MobileControlMode.touchpad;
  int _modeRevision = 0;
  bool _modeDirty = false;
  String? awakeWarning;
  bool _disposed = false;
  Future<void> _writes = Future<void>.value();
  String? warning;

  double get sensitivity => _sensitivity;
  bool get keepScreenAwake => _keepScreenAwake;
  MobileControlMode get lastControlMode => _lastControlMode;
  String get label => '${(_sensitivity * 100).round()}%';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    await Future.wait([
      _loadSensitivity(),
      _loadScreenAwake(),
      _loadControlMode(),
    ]);
  }

  Future<void> _loadControlMode() async {
    final revision = _modeRevision;
    try {
      final raw = await _storage.read(key: controlModeKey);
      if (_disposed || revision != _modeRevision) return;
      _lastControlMode = MobileControlMode.values.firstWhere(
        (mode) => mode.name == raw,
        orElse: () => MobileControlMode.touchpad,
      );
      _notify();
    } catch (_) {
      if (!_disposed && revision == _modeRevision) {
        warning = 'Could not restore your last tab. Using Touchpad.';
        _notify();
      }
    }
  }

  void setLastControlMode(MobileControlMode mode) {
    _modeRevision++;
    _modeDirty = true;
    _lastControlMode = mode;
    _notify();
  }

  Future<void> _loadScreenAwake() async {
    final revision = _awakeRevision;
    try {
      final raw = await _storage.read(key: keepAwakeKey);
      if (_disposed || revision != _awakeRevision) return;
      _keepScreenAwake = raw == 'true';
      _notify();
    } catch (_) {
      if (!_disposed && revision == _awakeRevision) {
        awakeWarning =
            'Could not load the screen preference. Keep screen awake is off.';
        _notify();
      }
    }
  }

  void setKeepScreenAwake(bool value) {
    _awakeRevision++;
    _awakeDirty = true;
    _keepScreenAwake = value;
    awakeWarning = null;
    _notify();
  }

  void reportAwakeWarning(String? message) {
    if (awakeWarning == message) return;
    awakeWarning = message;
    _notify();
  }

  Future<void> _loadSensitivity() async {
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
    final awake = _keepScreenAwake, dirty = _awakeDirty;
    final awakeRevision = _awakeRevision;
    final mode = _lastControlMode, modeDirty = _modeDirty;
    final modeRevision = _modeRevision;
    _writes = _writes.then((_) async {
      try {
        await _storage.write(key: storageKey, value: value.toString());
        if (dirty) {
          await _storage.write(key: keepAwakeKey, value: awake.toString());
          if (_awakeRevision == awakeRevision) _awakeDirty = false;
        }
        if (modeDirty) {
          await _storage.write(key: controlModeKey, value: mode.name);
          if (_modeRevision == modeRevision) _modeDirty = false;
        }
        warning = null;
      } catch (_) {
        warning =
            'Settings changed for now, but could not be saved. Try again.';
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
