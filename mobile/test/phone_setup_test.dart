import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/computer_store.dart';
import 'package:linkpad_controller/controller_page.dart';
import 'package:linkpad_controller/main.dart';
import 'package:linkpad_controller/peer_client.dart';
import 'package:linkpad_controller/phone_permissions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'first phone pairing explains permissions and opens manual entry directly',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = ComputerStore();
      await store.load();
      final peer = PeerClient(computers: store);
      addTearDown(peer.dispose);
      addTearDown(store.dispose);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: linkpadTheme(Brightness.light),
          home: ControllerPage(peer: peer),
        ),
      );
      await tester.pumpAndSettle();
      final pair = find.text('Pair a computer');
      await tester.scrollUntilVisible(pair, 150);
      await tester.tap(pair);
      await tester.pumpAndSettle();
      expect(find.text('Connect to a computer'), findsOneWidget);
      expect(find.textContaining('Allow Camera when you scan'), findsOneWidget);
      expect(find.text('Scan pairing code'), findsNothing);
      await tester.tap(find.text('Enter manually'));
      await tester.pumpAndSettle();
      expect(find.text('Connect to a computer'), findsNothing);
      expect(
        find.widgetWithText(TextField, 'Computer address'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'opening settings forwards the native result without inventing permission state',
    () async {
      const channel = MethodChannel('linkpad/permissions');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'openSettings');
        return false;
      });
      expect(await openPhoneSettings(), isFalse);
      messenger.setMockMethodCallHandler(channel, (_) async => true);
      expect(await openPhoneSettings(), isTrue);
    },
  );
}
