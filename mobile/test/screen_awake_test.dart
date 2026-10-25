import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:linkpad_controller/cursor_settings.dart';
import 'package:linkpad_controller/peer_client.dart';
import 'package:linkpad_controller/screen_awake.dart';
import 'package:linkpad_controller/settings_page.dart';
import 'package:linkpad_controller/main.dart';

class AwakePeer extends PeerClient {
  void change(PeerState value) {
    state = value;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'screen preference defaults off and survives reload independently of sensitivity',
    () async {
      final settings = CursorSettings();
      addTearDown(settings.dispose);
      await settings.load();
      expect(settings.keepScreenAwake, isFalse);
      settings.setKeepScreenAwake(true);
      await settings.save();
      final restored = CursorSettings();
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.keepScreenAwake, isTrue);
      expect(restored.sensitivity, 1);
      restored.setKeepScreenAwake(false);
      await restored.save();
      final off = CursorSettings();
      addTearDown(off.dispose);
      await off.load();
      expect(off.keepScreenAwake, isFalse);
    },
  );

  test(
    'a slider save before restoration cannot erase the stored screen choice',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        CursorSettings.keepAwakeKey: 'true',
      });
      final settings = CursorSettings();
      addTearDown(settings.dispose);
      settings.setSensitivity(2);
      await settings.save();
      await settings.load();
      expect(settings.keepScreenAwake, isTrue);
      expect(settings.sensitivity, 2);
      final loading = settings.load();
      settings.setKeepScreenAwake(false);
      await loading;
      expect(settings.keepScreenAwake, isFalse);
    },
  );

  test(
    'only an opted-in foreground connection holds the screen awake',
    () async {
      final settings = CursorSettings(), peer = AwakePeer();
      addTearDown(settings.dispose);
      addTearDown(peer.dispose);
      final calls = <bool>[];
      final awake = ScreenAwakeController(
        settings: settings,
        peer: peer,
        foreground: true,
        supported: true,
        apply: (enabled) async {
          calls.add(enabled);
        },
      );
      await awake.settled;
      settings.setKeepScreenAwake(true);
      await awake.settled;
      expect(calls, [false]);
      peer.change(PeerState.connected);
      await awake.settled;
      awake.setForeground(false);
      await awake.settled;
      awake.setForeground(true);
      await awake.settled;
      peer.change(PeerState.reconnecting);
      await awake.settled;
      expect(calls, [false, true, false, true, false]);
      peer.change(PeerState.connected);
      await awake.settled;
      settings.setKeepScreenAwake(false);
      await awake.settled;
      expect(calls.last, isFalse);
      awake.dispose();
      await awake.settled;
    },
  );

  test(
    'closing during an in-flight enable always releases the wake flag last',
    () async {
      final settings = CursorSettings(), peer = AwakePeer();
      addTearDown(settings.dispose);
      addTearDown(peer.dispose);
      final enabling = Completer<void>(), calls = <bool>[];
      final awake = ScreenAwakeController(
        settings: settings,
        peer: peer,
        foreground: true,
        supported: true,
        apply: (enabled) async {
          calls.add(enabled);
          if (enabled) await enabling.future;
        },
      );
      await awake.settled;
      settings.setKeepScreenAwake(true);
      peer.change(PeerState.connected);
      await Future<void>.delayed(Duration.zero);
      expect(calls.last, isTrue);
      awake.setForeground(false);
      awake.dispose();
      enabling.complete();
      await awake.settled;
      expect(calls, [false, true, false]);
    },
  );

  testWidgets('Settings toggle saves the choice without changing sensitivity', (
    tester,
  ) async {
    final settings = CursorSettings();
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: linkpadTheme(Brightness.light),
        home: SettingsPage(settings: settings),
      ),
    );
    await tester.scrollUntilVisible(find.text('Keep screen awake'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep screen awake'));
    await tester.pumpAndSettle();
    expect(settings.keepScreenAwake, isTrue);
    final restored = CursorSettings();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.keepScreenAwake, isTrue);
    expect(restored.sensitivity, 1);
    expect(tester.takeException(), isNull);
  });
}
