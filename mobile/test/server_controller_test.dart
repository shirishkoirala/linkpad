import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/desktop/server_controller.dart';

void main() {
  final binary = Platform.environment['LINKPAD_DESKTOP_TEST_BINARY'];

  test(
    'bundled server status, enrollment, concurrent lifecycle, and listener cleanup',
    () async {
      final state = await Directory.systemTemp.createTemp(
        'linkpad-desktop-test-',
      );
      final server = ServerController(
        executable: binary,
        stateDirectory: state.path,
        listenAddress: '127.0.0.1:0',
      );
      try {
        await server.start();
        expect(server.running, isTrue, reason: server.error);
        expect(server.pairing, isNull);
        expect(server.fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
        await server.command('pair');
        final invitation = server.pairing!;
        expect(invitation['type'], 'linkpad-pairing');
        expect(
          server.diagnostics,
          isNot(contains(invitation['secret'] as String)),
        );
        await server.command('cancelPairing');
        expect(server.pairing, isNull);
        await expectLater(
          server.command('pair', address: 'http://invalid'),
          throwsStateError,
        );
        expect(server.running, isTrue);
        await Future.wait([
          server.stop(),
          server.start(),
          server.stop(),
          server.start(),
        ]);
        expect(server.running, isTrue, reason: server.error);
        final address = Uri.parse(server.address);
        await server.stop();
        expect(server.running, isFalse);
        await expectLater(
          Socket.connect(
            address.host,
            address.port,
            timeout: const Duration(seconds: 1),
          ),
          throwsA(isA<SocketException>()),
        );
      } finally {
        await server.stop();
        server.dispose();
        await state.delete(recursive: true);
      }
    },
    skip: binary == null
        ? 'Set LINKPAD_DESKTOP_TEST_BINARY to a native Go build.'
        : false,
  );

  test(
    'missing helper fails clearly and leaves the controller stopped',
    () async {
      final server = ServerController(
        executable: '/does-not-exist/linkpad-server',
      );
      await server.start();
      expect(server.running, isFalse);
      expect(server.busy, isFalse);
      expect(server.error, contains('Could not start the bundled server'));
      server.dispose();
    },
  );
}
