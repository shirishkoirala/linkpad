import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:linkpad_controller/cursor_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('sensitivity survives reload and reset', () async {
    final settings = CursorSettings();
    await settings.load();
    expect(settings.sensitivity, 1);
    settings.setSensitivity(2.25);
    await settings.save();
    final restored = CursorSettings();
    await restored.load();
    expect(restored.sensitivity, 2.25);
    restored.setSensitivity(CursorSettings.defaultSensitivity);
    await restored.save();
    final reset = CursorSettings();
    await reset.load();
    expect(reset.sensitivity, 1);
    settings.dispose();
    restored.dispose();
    reset.dispose();
  });

  test('invalid stored values cannot break pointer movement', () async {
    for (final value in ['NaN', 'Infinity', '-2', '100', 'bad']) {
      FlutterSecureStorage.setMockInitialValues({
        CursorSettings.storageKey: value,
      });
      final settings = CursorSettings();
      await settings.load();
      expect(settings.sensitivity, 1);
      settings.dispose();
    }
  });

  test('an asynchronous restore cannot replace a new slider choice', () async {
    FlutterSecureStorage.setMockInitialValues({
      CursorSettings.storageKey: '0.5',
    });
    final settings = CursorSettings();
    final loading = settings.load();
    settings.setSensitivity(2);
    await loading;
    expect(settings.sensitivity, 2);
    await Future.wait([
      settings.save(),
      (() {
        settings.setSensitivity(3);
        return settings.save();
      })(),
    ]);
    final restored = CursorSettings();
    await restored.load();
    expect(restored.sensitivity, 3);
    settings.dispose();
    restored.dispose();
  });
}
