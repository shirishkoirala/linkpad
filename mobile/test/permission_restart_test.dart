import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/desktop/desktop_platform.dart';
import 'package:linkpad_controller/desktop/desktop_page.dart';
import 'package:linkpad_controller/desktop/server_controller.dart';
import 'package:linkpad_controller/desktop/accessibility_restart_prompt.dart';

class RestartServer extends ServerController {
  RestartServer(this.events) {
    running = true;
    inputPermissionGranted = false;
    inputAvailable = false;
  }
  final List<String> events;
  @override
  Future<void> command(String command, {String? peer, String? address}) async {
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    events.add('stop');
    running = false;
    notifyListeners();
  }

  @override
  Future<void> start() async {
    events.add('start');
    running = true;
    notifyListeners();
  }
}

class RestartPlatform extends DesktopPlatform {
  RestartPlatform(super.server, this.events);
  final List<String> events;
  bool failLaunch = false;
  @override
  bool get isMacOS => true;
  @override
  Future<void> openPermissions() async {}
  @override
  Future<void> launchFreshInstance() async {
    events.add('launch');
    if (failLaunch) throw StateError('launch failed');
  }

  @override
  Future<void> quit() async {
    events.add('quit');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'restart prompt is reachable in setup and the normal desktop page',
    (tester) async {
      for (final completed in [false, true]) {
        final events = <String>[];
        final server = RestartServer(events)
          ..onboardingLoaded = true
          ..setupCompleted = completed;
        final platform = RestartPlatform(server, events);
        await platform.checkInput();
        await tester.pumpWidget(
          MaterialApp(
            home: DesktopPage(server: server, platform: platform),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Restart Linkpad'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Restart Linkpad'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        platform.dispose();
        server.dispose();
      }
    },
  );

  testWidgets(
    'permission return prompts for full restart without restarting automatically',
    (tester) async {
      final events = <String>[];
      final server = RestartServer(events);
      final platform = RestartPlatform(server, events);
      addTearDown(platform.dispose);
      addTearDown(server.dispose);
      await platform.requestInputPermission();
      await platform.checkInput();
      expect(platform.restartRecommended, isTrue);
      expect(events, isEmpty);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AccessibilityRestartPrompt(platform: platform)),
        ),
      );
      expect(find.text('Restart Linkpad'), findsOneWidget);
      await tester.tap(find.text('Restart Linkpad'));
      await tester.pumpAndSettle();
      expect(events, ['stop', 'launch', 'quit']);
    },
  );
  test('successful access check clears restart recommendation', () async {
    final events = <String>[];
    final server = RestartServer(events);
    final platform = RestartPlatform(server, events);
    addTearDown(platform.dispose);
    addTearDown(server.dispose);
    await platform.checkInput();
    expect(platform.restartRecommended, isTrue);
    server.inputAvailable = true;
    await platform.checkInput();
    expect(platform.restartRecommended, isFalse);
  });
  test(
    'failed relaunch restores the current server and gives manual recovery',
    () async {
      final events = <String>[];
      final server = RestartServer(events);
      final platform = RestartPlatform(server, events)..failLaunch = true;
      addTearDown(platform.dispose);
      addTearDown(server.dispose);
      await platform.restartApp();
      expect(events, ['stop', 'launch', 'start']);
      expect(server.running, isTrue);
      expect(platform.error, contains('Quit and reopen'));
      expect(platform.restartBusy, isFalse);
    },
  );
}
