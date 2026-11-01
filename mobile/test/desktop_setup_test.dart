import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/desktop/desktop_setup_page.dart';
import 'package:linkpad_controller/desktop/desktop_platform.dart';
import 'package:linkpad_controller/desktop/server_controller.dart';
import 'package:linkpad_controller/main.dart';
import 'package:linkpad_controller/pairing_scanner.dart';

class SetupServer extends ServerController {
  SetupServer({super.settingsDirectory}) {
    address = 'wss://192.168.1.202:4747/ws';
  }
  int restarts = 0, permissionRequests = 0;
  bool? completedTest;
  final commands = <String>[];
  void update(void Function() change) {
    change();
    notifyListeners();
  }

  @override
  Future<void> start() async {
    running = true;
    notifyListeners();
  }

  @override
  Future<void> restart() async {
    restarts++;
    inputAvailable = inputPermissionGranted == true;
    notifyListeners();
  }

  @override
  Future<void> command(String command, {String? peer, String? address}) async {
    commands.add(command);
    if (command == 'requestInputPermission') permissionRequests++;
    if (command == 'cancelPairing') pairing = null;
    if (command == 'pair') {
      pairing = {
        'type': 'linkpad-pairing',
        'version': 1,
        'address': this.address,
        'fingerprint': 'a' * 64,
        'secret': 'b' * 64,
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 2))
            .toIso8601String(),
      };
    }
    notifyListeners();
  }

  @override
  Future<void> completeSetup({required bool tested}) async {
    completedTest = tested;
    if (settingsDirectory != null) {
      await super.completeSetup(tested: tested);
    } else {
      setupCompleted = true;
      setupTested = tested;
      notifyListeners();
    }
  }
}

class SetupPlatform extends DesktopPlatform {
  SetupPlatform(
    super.server, {
    this.mac = true,
    this.diskImage = false,
    this.windows = false,
  });
  final bool windows;
  final bool mac, diskImage;
  int settingsOpened = 0, loginChanges = 0;
  @override
  bool get isMacOS => mac;
  @override
  bool get isWindows => windows;
  @override
  bool get launchedFromDiskImage => diskImage;
  @override
  Future<void> openPermissions() async {
    settingsOpened++;
  }

  @override
  Future<void> setLogin(bool enabled) async {
    loginChanges++;
    loginEnabled = enabled;
    notifyListeners();
  }
}

void main() {
  test(
    'Mac installation guard covers disk images and translocated downloads',
    () {
      expect(
        macInstallationNeedsMove(
          '/Volumes/Linkpad/Linkpad.app/Contents/MacOS/Linkpad',
        ),
        isTrue,
      );
      expect(
        macInstallationNeedsMove(
          '/private/var/folders/example/AppTranslocation/id/d/Linkpad.app/Contents/MacOS/Linkpad',
        ),
        isTrue,
      );
      expect(
        macInstallationNeedsMove(
          '/Applications/Linkpad.app/Contents/MacOS/Linkpad',
        ),
        isFalse,
      );
      expect(
        macInstallationNeedsMove(
          '/Users/me/Projects/linkpad/build/Linkpad.app/Contents/MacOS/Linkpad',
        ),
        isFalse,
      );
    },
  );
  Future<void> show(
    WidgetTester tester,
    SetupServer server,
    SetupPlatform platform,
  ) async {
    tester.view.physicalSize = const Size(720, 580);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(platform.dispose);
    addTearDown(server.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: linkpadTheme(Brightness.light),
        home: DesktopSetupPage(server: server, platform: platform),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'grant request does not claim success; returning with trust restarts once',
    (tester) async {
      final server = SetupServer()..running = true;
      final platform = SetupPlatform(server);
      await show(tester, server, platform);
      final button = find.text('Open Accessibility settings');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(platform.settingsOpened, 1);
      expect(server.permissionRequests, 1);
      expect(server.restarts, 0);
      expect(find.text('Let your phone control this Mac'), findsOneWidget);
      server.inputPermissionGranted = true;
      platform.onWindowFocus();
      await tester.pumpAndSettle();
      expect(server.restarts, 1);
      expect(find.text('Create pairing code'), findsOneWidget);
      platform.onWindowFocus();
      await tester.pumpAndSettle();
      expect(server.restarts, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Windows input recovery avoids Linux and Mac instructions', (
    tester,
  ) async {
    final server = SetupServer()
      ..running = true
      ..inputError = 'Windows interactive desktop unavailable';
    await show(
      tester,
      server,
      SetupPlatform(server, mac: false, windows: true),
    );
    expect(find.text('Open Linkpad in your Windows session'), findsOneWidget);
    expect(find.textContaining('UAC prompts'), findsOneWidget);
    expect(find.textContaining('X11'), findsNothing);
    expect(find.text('Open Accessibility settings'), findsNothing);
  });

  testWidgets('Linux Wayland recovery never displays Mac permission actions', (
    tester,
  ) async {
    final server = SetupServer()
      ..running = true
      ..inputError = 'Wayland input is not supported';
    await show(tester, server, SetupPlatform(server, mac: false));
    expect(find.text('An X11 session is needed'), findsOneWidget);
    expect(find.text('Open Accessibility settings'), findsNothing);
    expect(find.text('Create pairing code'), findsNothing);
  });

  testWidgets(
    'disk-image launches ask to install before requesting permissions',
    (tester) async {
      final server = SetupServer()
        ..running = true
        ..inputAvailable = true;
      await show(tester, server, SetupPlatform(server, diskImage: true));
      expect(find.text('Install Linkpad in Applications'), findsOneWidget);
      expect(find.text('Create pairing code'), findsNothing);
      expect(server.permissionRequests, 0);
    },
  );

  testWidgets(
    'pairing is explicit and expired codes are replaced without losing trust',
    (tester) async {
      final server = SetupServer()
        ..running = true
        ..inputAvailable = true
        ..address = 'wss://192.168.1.202:4747/ws';
      await show(tester, server, SetupPlatform(server, mac: false));
      expect(server.commands, isEmpty);
      await tester.ensureVisible(find.text('Create pairing code'));
      await tester.tap(find.text('Create pairing code'));
      await tester.pumpAndSettle();
      expect(server.commands, ['pair']);
      server.update(() {
        server.pairing!['expiresAt'] = DateTime.now()
            .subtract(const Duration(seconds: 1))
            .toIso8601String();
      });
      await tester.pumpAndSettle();
      expect(find.text('Create new code'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a local click cannot complete setup; remote input and confirmation can',
    (tester) async {
      final server = SetupServer()
        ..running = true
        ..inputAvailable = true
        ..peers = [DesktopPeer('a' * 64, true)];
      final platform = SetupPlatform(server);
      await show(tester, server, platform);
      await tester.ensureVisible(find.text('Click here using your phone'));
      await tester.tap(find.text('Click here using your phone'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Yes, it works · Finish'),
            )
            .onPressed,
        isNull,
      );
      server.update(() => server.inputCount++);
      await tester.pumpAndSettle();
      final finish = find.text('Yes, it works · Finish');
      await tester.ensureVisible(finish);
      await tester.tap(finish);
      await tester.pumpAndSettle();
      expect(server.completedTest, isTrue);
      expect(platform.loginChanges, 0);
      expect(platform.loginEnabled, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'test later persists a deferred test and leaves login startup off',
    (tester) async {
      final server = SetupServer()
        ..running = true
        ..inputAvailable = true
        ..peers = [DesktopPeer('a' * 64, true)];
      final platform = SetupPlatform(server);
      await show(tester, server, platform);
      await tester.ensureVisible(find.text('Test later'));
      await tester.tap(find.text('Test later'));
      await tester.pumpAndSettle();
      expect(server.completedTest, isFalse);
      expect(server.setupCompleted, isTrue);
      expect(platform.loginChanges, 0);
    },
  );

  test(
    'setup completion survives restart without saving pairing secrets',
    () async {
      final dir = await Directory.systemTemp.createTemp('linkpad-setup-');
      addTearDown(() => dir.delete(recursive: true));
      final server = SetupServer(settingsDirectory: dir.path);
      addTearDown(server.dispose);
      await server.initialize();
      expect(server.onboardingLoaded, isTrue);
      expect(server.setupCompleted, isFalse);
      await server.completeSetup(tested: false);
      final saved = jsonDecode(
        await File('${dir.path}/desktop-setup.json').readAsString(),
      );
      expect(saved, {'version': 1, 'completed': true, 'tested': false});
      final reopened = SetupServer(settingsDirectory: dir.path);
      addTearDown(reopened.dispose);
      await reopened.initialize();
      expect(reopened.setupCompleted, isTrue);
      expect(reopened.setupTested, isFalse);
      reopened.reviewSetup();
      expect(reopened.setupCompleted, isFalse);
    },
  );

  test('existing trusted phones bypass fresh-install setup', () async {
    final dir = await Directory.systemTemp.createTemp('linkpad-setup-upgrade-');
    addTearDown(() => dir.delete(recursive: true));
    final server = SetupServer(settingsDirectory: dir.path)
      ..peers = [DesktopPeer('a' * 64, false)];
    addTearDown(server.dispose);
    await server.initialize();
    expect(server.setupCompleted, isTrue);
  });

  test(
    'an interrupted fresh setup resumes even after a phone has paired',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'linkpad-setup-resume-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final fresh = SetupServer(settingsDirectory: dir.path);
      addTearDown(fresh.dispose);
      await fresh.initialize();
      final marker = jsonDecode(
        await File('${dir.path}/desktop-setup.json').readAsString(),
      );
      expect(marker['completed'], isFalse);
      final resumed = SetupServer(settingsDirectory: dir.path)
        ..peers = [DesktopPeer('a' * 64, false)];
      addTearDown(resumed.dispose);
      await resumed.initialize();
      expect(resumed.setupCompleted, isFalse);
      expect(resumed.peers, hasLength(1));
    },
  );

  testWidgets(
    'an already paired phone is asked to reconnect rather than scan again',
    (tester) async {
      final server = SetupServer()
        ..running = true
        ..inputAvailable = true
        ..peers = [DesktopPeer('a' * 64, false)];
      await show(tester, server, SetupPlatform(server));
      expect(find.text('Reconnect your phone'), findsOneWidget);
      expect(find.text('Create pairing code'), findsNothing);
      expect(find.text('Pair another phone'), findsOneWidget);
    },
  );

  testWidgets(
    'camera denial and camera failure have different recovery actions',
    (tester) async {
      var settings = 0, manual = 0;
      Future<void> showRecovery(bool denied) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScannerRecovery(
              denied: denied,
              unsupported: false,
              onSettings: () => settings++,
              onRetry: () {},
              onManual: () => manual++,
            ),
          ),
        ),
      );
      await showRecovery(true);
      await tester.tap(find.text('Open Settings'));
      await tester.tap(find.text('Enter manually'));
      expect(settings, 1);
      expect(manual, 1);
      await showRecovery(false);
      expect(find.text('Open Settings'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.textContaining('The camera could not start'), findsOneWidget);
    },
  );
}
