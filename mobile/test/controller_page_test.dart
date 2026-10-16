import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/computer_store.dart';
import 'package:linkpad_controller/controller_page.dart';
import 'package:linkpad_controller/main.dart';
import 'package:linkpad_controller/peer_client.dart';

class ChooserPeer extends PeerClient {
  ChooserPeer(ComputerStore store) : super(computers: store);
  final attempts = <String>[];
  bool controls = false;
  @override
  bool get showControls => controls;
  @override
  bool get ready => connected;
  @override
  String get desktopName =>
      computers.find(attempts.lastOrNull)?.name ?? 'Your computer';
  @override
  String? get activeComputerId => attempts.lastOrNull;
  @override
  Future<void> connect(
    String address,
    String fingerprint,
    String token,
    void Function() onPaired,
  ) async {
    disconnect();
    attempts.add(fingerprint);
    controls = true;
    state = PeerState.connected;
    onPaired();
    notifyListeners();
    await computers.saveVerified(address, fingerprint);
  }

  @override
  void disconnect() {
    controls = false;
    super.disconnect();
  }
}

void main() {
  final a = List.filled(64, 'a').join(), b = List.filled(64, 'b').join();
  late ComputerStore store;
  late ChooserPeer peer;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    store = ComputerStore();
    await store.saveVerified('wss://linux:4747/ws', a);
    await store.rename(a, 'Linux PC');
    await store.saveVerified('wss://mac:4747/ws', b);
    await store.rename(b, 'MacBook');
    peer = ChooserPeer(store);
  });
  tearDown(() {
    peer.dispose();
    store.dispose();
  });
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: linkpadTheme(Brightness.light),
        home: ControllerPage(peer: peer),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder connect(String id) => find.descendant(
    of: find.byKey(ValueKey(id)),
    matching: find.text('Connect'),
  );
  testWidgets('chooser switches between computers without replacing pairings', (
    tester,
  ) async {
    await pump(tester);
    expect(peer.attempts, isEmpty);
    await tester.ensureVisible(connect(a));
    await tester.pumpAndSettle();
    await tester.tap(connect(a));
    await tester.pumpAndSettle();
    expect(peer.attempts, [a]);
    expect(find.text('Linux PC'), findsOneWidget);
    await tester.tap(find.text('Computers'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(connect(b));
    await tester.pumpAndSettle();
    await tester.tap(connect(b));
    await tester.pumpAndSettle();
    expect(peer.attempts, [a, b]);
    expect(store.computers.length, 2);
    expect(find.text('MacBook'), findsOneWidget);
  });
  testWidgets('rename and forget persist without touching another computer', (
    tester,
  ) async {
    await pump(tester);
    await tester.ensureVisible(find.byTooltip('Manage Linux PC'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Manage Linux PC'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      'Linux PC',
    );
    await tester.enterText(find.byType(TextField).last, 'Office Linux');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 20 && store.find(a)!.name != 'Office Linux'; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }
    expect(store.find(a)!.name, 'Office Linux');
    await tester.ensureVisible(find.byTooltip('Manage MacBook'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Manage MacBook'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forget'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Forget'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 20 && store.find(b) != null; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }
    expect(store.computers.single.name, 'Office Linux');
    final restored = ComputerStore();
    await restored.load();
    expect(restored.computers.single.name, 'Office Linux');
    restored.dispose();
    expect(tester.takeException(), isNull);
  });
  testWidgets('saved-computer cards fit a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pump(tester);
    await tester.ensureVisible(connect(a));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
