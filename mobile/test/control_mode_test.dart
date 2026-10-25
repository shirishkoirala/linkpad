import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/control_deck.dart';
import 'package:linkpad_controller/cursor_settings.dart';
import 'package:linkpad_controller/main.dart';
import 'package:linkpad_controller/mobile_controls.dart';
import 'package:linkpad_controller/remote_page.dart';
import 'control_deck_test.dart' show FakePeer;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('every control tab survives an app settings reload', () async {
    for (final mode in MobileControlMode.values) {
      final settings = CursorSettings();
      settings.setLastControlMode(mode);
      await settings.save();
      final restored = CursorSettings();
      await restored.load();
      expect(restored.lastControlMode, mode);
      settings.dispose();
      restored.dispose();
    }
  });

  test(
    'invalid modes fall back safely and a late restore cannot replace a new choice',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        CursorSettings.controlModeKey: 'unknown',
      });
      final settings = CursorSettings();
      addTearDown(settings.dispose);
      await settings.load();
      expect(settings.lastControlMode, MobileControlMode.touchpad);
      FlutterSecureStorage.setMockInitialValues({
        CursorSettings.controlModeKey: 'remote',
      });
      final loading = settings.load();
      settings.setLastControlMode(MobileControlMode.keyboard);
      await loading;
      expect(settings.lastControlMode, MobileControlMode.keyboard);
      await settings.save();
    },
  );

  test(
    'saving another preference before load does not erase the stored tab',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        CursorSettings.controlModeKey: 'remote',
      });
      final settings = CursorSettings();
      addTearDown(settings.dispose);
      settings.setSensitivity(2);
      settings.setKeepScreenAwake(true);
      await settings.save();
      await settings.load();
      expect(settings.lastControlMode, MobileControlMode.remote);
      expect(settings.sensitivity, 2);
      expect(settings.keepScreenAwake, isTrue);
    },
  );

  testWidgets('Keyboard restores without restoring a held modifier', (
    tester,
  ) async {
    final settings = CursorSettings()
      ..setLastControlMode(MobileControlMode.keyboard);
    final peer = FakePeer();
    addTearDown(settings.dispose);
    addTearDown(peer.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: linkpadTheme(Brightness.light),
        home: ControlDeck(peer: peer, settings: settings),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MobileControlScaffold>(find.byType(MobileControlScaffold))
          .mode,
      MobileControlMode.keyboard,
    );
    await tester.ensureVisible(find.text('c'));
    await tester.tap(find.text('c'));
    await tester.pump();
    expect(peer.typed, ['c']);
    await tester.tap(find.text('Touchpad'));
    await tester.pumpAndSettle();
    expect(settings.lastControlMode, MobileControlMode.touchpad);
  });

  testWidgets(
    'Remote remains selected after disconnect and restores on the next controller',
    (tester) async {
      final settings = CursorSettings();
      final peer = FakePeer();
      addTearDown(settings.dispose);
      addTearDown(peer.dispose);
      Widget page(int key) => MaterialApp(
        theme: linkpadTheme(Brightness.light),
        home: ControlDeck(key: ValueKey(key), peer: peer, settings: settings),
      );
      await tester.pumpWidget(page(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remote'));
      await tester.pumpAndSettle();
      expect(settings.lastControlMode, MobileControlMode.remote);
      await tester.tap(find.byTooltip('Computers'));
      await tester.pumpAndSettle();
      expect(settings.lastControlMode, MobileControlMode.remote);
      peer.resume();
      await tester.pumpWidget(page(2));
      await tester.pumpAndSettle();
      expect(find.byType(RemotePage), findsOneWidget);
      expect(
        tester
            .widget<MobileControlScaffold>(find.byType(MobileControlScaffold))
            .mode,
        MobileControlMode.remote,
      );
      await tester.tap(find.text('Keyboard'));
      await tester.pumpAndSettle();
      expect(settings.lastControlMode, MobileControlMode.keyboard);
      await settings.save();
      final restored = CursorSettings();
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.lastControlMode, MobileControlMode.keyboard);
    },
  );
}
