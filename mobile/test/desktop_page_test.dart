import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/desktop/desktop_page.dart';
import 'package:linkpad_controller/desktop/server_controller.dart';
import 'package:linkpad_controller/main.dart';

class FakeServer extends ServerController {
  final List<String> commands = [];
  @override
  Future<void> command(String command, {String? peer, String? address}) async {
    commands.add('$command:${peer ?? ""}');
    if (command == 'pair') {
      pairing = {
        'type': 'linkpad-pairing',
        'version': 1,
        'address': this.address,
        'fingerprint': 'a' * 64,
        'secret': 'b' * 64,
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 2))
            .toUtc()
            .toIso8601String(),
      };
    }
    if (command == 'cancelPairing') pairing = null;
    if (command == 'revoke') peers.removeWhere((p) => p.id == peer);
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    running = false;
    pairing = null;
    notifyListeners();
  }

  @override
  Future<void> start() async {
    running = true;
    notifyListeners();
  }
}

void main() {
  Future<void> show(WidgetTester tester, FakeServer server, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: linkpadTheme(Brightness.light),
        home: DesktopPage(server: server),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('pairing is explicit, cancellable, and fits the minimum window', (
    tester,
  ) async {
    final server = FakeServer()
      ..running = true
      ..inputAvailable = true
      ..address = 'wss://192.168.1.202:4747/ws';
    addTearDown(server.dispose);
    await show(tester, server, const Size(720, 580));
    expect(server.commands, isEmpty);
    final pair = find.text('Create pairing code');
    await tester.ensureVisible(pair);
    await tester.pumpAndSettle();
    await tester.tap(pair);
    await tester.pumpAndSettle();
    expect(server.commands, ['pair:']);
    expect(find.text('Cancel pairing'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Cancel pairing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel pairing'));
    await tester.pumpAndSettle();
    expect(server.pairing, isNull);
  });

  testWidgets('revoking requires confirmation and targets the selected phone', (
    tester,
  ) async {
    final id = 'a' * 64;
    final server = FakeServer()
      ..running = true
      ..inputAvailable = true
      ..peers = [DesktopPeer(id, true)]
      ..names = {id: 'My iPhone'};
    addTearDown(server.dispose);
    await show(tester, server, const Size(1100, 800));
    expect(find.text('My iPhone'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    await tester.tap(find.byTooltip('Manage My iPhone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revoke access'));
    await tester.pumpAndSettle();
    expect(server.commands, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Revoke access'));
    await tester.pumpAndSettle();
    expect(server.commands, ['revoke:$id']);
    expect(find.text('My iPhone'), findsNothing);
  });

  testWidgets('stopped state disables enrollment and displays startup errors', (
    tester,
  ) async {
    final server = FakeServer()..error = 'Port 4747 is already in use.';
    addTearDown(server.dispose);
    await show(tester, server, const Size(1020, 740));
    expect(find.text('Port 4747 is already in use.'), findsOneWidget);
    final pair = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create pairing code'),
    );
    expect(pair.onPressed, isNull);
    expect(find.text('Start server'), findsOneWidget);
  });
}
