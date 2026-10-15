import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/peer_client.dart';

Future<void> waitFor(PeerClient peer, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out; client status: ${peer.status}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late PeerClient peer;
  late String fingerprint;
  late String clientCertificate;
  final received = <Map<String, dynamic>>[];
  final sockets = <WebSocket>[];
  bool provedIdentity = false;
  bool acknowledge = true;
  bool omitCapabilities = false;
  var capabilities = ['pointer.v1'];
  String? rejectReason;

  setUp(() async {
    // Exercise actual loopback TLS instead of Flutter's default HTTP mock.
    HttpOverrides.global = null;
    final clientIdentity = generateIdentity();
    final client = jsonDecode(clientIdentity) as Map<String, dynamic>;
    clientCertificate = client['cert'] as String;
    FlutterSecureStorage.setMockInitialValues({
      'peer_identity_v1': clientIdentity,
    });
    final desktop = jsonDecode(generateIdentity()) as Map<String, dynamic>;
    final cert = desktop['cert'] as String;
    final der = base64Decode(
      cert
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty && !line.startsWith('-----'))
          .join(),
    );
    fingerprint = sha256.convert(der).toString();
    final context = SecurityContext(withTrustedRoots: false)
      ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3
      ..useCertificateChainBytes(utf8.encode(cert))
      ..usePrivateKeyBytes(utf8.encode(desktop['key'] as String))
      ..setTrustedCertificatesBytes(utf8.encode(clientCertificate));
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
      requestClientCertificate: true,
    );
    received.clear();
    acknowledge = true;
    omitCapabilities = false;
    capabilities = ['pointer.v1'];
    rejectReason = null;
    sockets.clear();
    provedIdentity = false;
    server.listen((request) async {
      provedIdentity =
          request.certificate?.pem.replaceAll(RegExp(r'\s'), '') ==
          clientCertificate.replaceAll(RegExp(r'\s'), '');
      if (!provedIdentity) {
        request.response.statusCode = 403;
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      var first = true;
      socket.listen((data) {
        final message = jsonDecode(data as String) as Map<String, dynamic>;
        received.add(message);
        if (first) {
          first = false;
          socket.add(
            jsonEncode({
              'version': 1,
              'type': rejectReason == null ? 'ready' : 'error',
              if (rejectReason != null) 'error': rejectReason,
              if (!omitCapabilities && rejectReason == null)
                'capabilities': capabilities,
            }),
          );
        } else if (acknowledge) {
          socket.add(jsonEncode({'version': 1, 'type': 'ack'}));
        }
      });
    });
    peer = PeerClient(
      timing: const PeerTiming(
        responseTimeout: Duration(milliseconds: 500),
        retryBase: Duration(milliseconds: 40),
        retryMax: Duration(milliseconds: 100),
      ),
    );
  });

  tearDown(() async {
    peer.dispose();
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
  });

  test(
    'keyboard input is queued in order until each acknowledgement',
    () async {
      capabilities = ['pointer.v1', 'keyboard.v1'];
      await peer.connect(
        'wss://127.0.0.1:${server.port}/ws',
        fingerprint,
        '',
        () {},
      );
      await waitFor(peer, () => peer.canKeyboard);
      expect(peer.typeText('h'), isTrue);
      expect(peer.typeText('i'), isTrue);
      expect(peer.keyboardKey('c', modifiers: {'super'}), isTrue);
      await waitFor(
        peer,
        () => received.where((m) => m['type'] == 'keyboard').length == 3,
      );
      final events = received.where((m) => m['type'] == 'keyboard').toList();
      expect(events.map((m) => m['text'] ?? m['key']), ['h', 'i', 'c']);
      expect(events.last['modifiers'], ['super']);
      peer.disconnect();
      expect(peer.typeText('x'), isFalse);
    },
  );

  test(
    'mutual TLS, exact pin, pairing and acknowledged pointer input',
    () async {
      var paired = false;
      await peer.connect(
        'wss://127.0.0.1:${server.port}/ws',
        fingerprint,
        'one-time-secret',
        () => paired = true,
      );
      await waitFor(peer, () => peer.ready);
      expect(provedIdentity, isTrue);
      expect(paired, isTrue);
      expect(received.first['type'], 'pair');
      expect(received.first['token'], 'one-time-secret');
      peer.click('left');
      peer.click('right'); // Both clicks survive acknowledgement backpressure.
      await waitFor(peer, () => received.length == 3);
      expect(received[1]['button'], 'left');
      expect(received[2]['button'], 'right');
      final saved = await PeerClient.storage.read(key: 'desktop_v1');
      expect(jsonDecode(saved!)['pin'], fingerprint);
      expect(saved, isNot(contains('one-time-secret')));
    },
  );

  test('d-pad sends arrow keys only when negotiated', () async {
    capabilities = ['pointer.v1', 'key.v1'];
    await peer.connect(
      'wss://127.0.0.1:${server.port}/ws',
      fingerprint,
      '',
      () {},
    );
    await waitFor(peer, () => peer.canKey);
    peer.pressKey('left');
    await waitFor(peer, () => received.length == 2);
    expect(received[1], {'version': 1, 'type': 'key', 'key': 'left'});
  });

  test(
    'fractional movements are combined without dropping a second stroke',
    () async {
      await peer.connect(
        'wss://127.0.0.1:${server.port}/ws',
        fingerprint,
        '',
        () {},
      );
      await waitFor(peer, () => peer.ready);
      for (var i = 0; i < 10; i++) {
        peer.move(0.5, 0.5);
      }
      await waitFor(peer, () => received.length == 2);
      for (var i = 0; i < 10; i++) {
        peer.move(0.5, -0.5);
      }
      await waitFor(peer, () => received.length == 3);
      expect(received[1]['dx'], 5);
      expect(received[1]['dy'], 5);
      expect(received[2]['dx'], 5);
      expect(received[2]['dy'], -5);
    },
  );

  test('wrong pin prevents application handshake', () async {
    await peer.connect(
      'wss://127.0.0.1:${server.port}/ws',
      List.filled(64, '0').join(),
      'secret',
      () => fail('Must not pair'),
    );
    expect(peer.ready, isFalse);
    expect(peer.status, contains('fingerprint'));
    expect(peer.state, PeerState.failed);
    expect(received, isEmpty);
  });

  test('reconnect sends hello using the persisted device identity', () async {
    await peer.connect(
      'wss://127.0.0.1:${server.port}/ws',
      fingerprint,
      '',
      () {},
    );
    await waitFor(peer, () => peer.ready);
    expect(provedIdentity, isTrue);
    expect(received.first['type'], 'hello');
    expect(received.first.containsKey('token'), isFalse);
  });
  test(
    'dropped connection reconnects with hello, never the pairing secret',
    () async {
      var pairedCount = 0;
      await peer.connect(
        'wss://127.0.0.1:${server.port}/ws',
        fingerprint,
        'one-use-secret',
        () => pairedCount++,
      );
      await waitFor(peer, () => peer.ready);
      await sockets.first.close();
      await waitFor(peer, () => sockets.length == 2 && peer.ready);
      expect(received[0]['type'], 'pair');
      expect(received[1]['type'], 'hello');
      expect(received[1].containsKey('token'), isFalse);
      expect(pairedCount, 1);
    },
  );

  test('capabilities are renegotiated after reconnect', () async {
    await peer.connect(
      'wss://127.0.0.1:${server.port}/ws',
      fingerprint,
      '',
      () {},
    );
    await waitFor(peer, () => peer.ready);
    omitCapabilities = true;
    await sockets.first.close();
    await waitFor(peer, () => sockets.length == 2 && peer.connected);
    expect(peer.ready, isFalse);
    expect(peer.showControls, isTrue);
    expect(peer.status, contains('desktop input unavailable'));
  });

  test('slow acknowledgements discard buffered motion and clicks', () async {
    await peer.connect(
      'wss://127.0.0.1:${server.port}/ws',
      fingerprint,
      '',
      () {},
    );
    await waitFor(peer, () => peer.ready);
    acknowledge = false;
    peer.click('left');
    await waitFor(peer, () => received.length == 2);
    peer.move(100, 100);
    peer.click('right');
    await waitFor(peer, () => !peer.ready);
    expect(peer.status, contains('input paused'));
    peer.click('left'); // Input is disabled while the connection is stalled.
    acknowledge = true;
    sockets.last.add(jsonEncode({'version': 1, 'type': 'ack'}));
    await waitFor(peer, () => peer.ready);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(received.length, 2);
    peer.move(3, 4);
    await waitFor(peer, () => received.length == 3);
    expect(received.last['dx'], 3);
    expect(received.last.containsKey('button'), isFalse);
  });

  test('timeout reconnect never replays old clicks', () async {
    await peer.connect(
      'wss://127.0.0.1:${server.port}/ws',
      fingerprint,
      '',
      () {},
    );
    await waitFor(peer, () => peer.ready);
    acknowledge = false;
    peer.click('left');
    await waitFor(peer, () => received.length == 2);
    peer.click('right');
    peer.move(20, 20);
    await waitFor(peer, () => sockets.length == 2 && peer.ready);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(received.map((m) => m['type']).toList(), [
      'hello',
      'pointer',
      'hello',
    ]);
  });

  test(
    'background closes the connection; resume reconnects without old input',
    () async {
      await peer.connect(
        'wss://127.0.0.1:${server.port}/ws',
        fingerprint,
        '',
        () {},
      );
      await waitFor(peer, () => peer.ready);
      peer.click('left');
      peer.move(20, 20);
      peer.setForeground(false);
      expect(peer.state, PeerState.suspended);
      expect(peer.ready, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(sockets.length, 1);
      peer.setForeground(true);
      await waitFor(peer, () => sockets.length == 2 && peer.ready);
      expect(received.map((m) => m['type']).toList(), ['hello', 'hello']);
    },
  );

  test('manual disconnect cancels retries and foreground resume', () async {
    await peer.connect(
      'wss://127.0.0.1:${server.port}/ws',
      fingerprint,
      '',
      () {},
    );
    await waitFor(peer, () => peer.ready);
    await sockets.first.close();
    await waitFor(peer, () => peer.state == PeerState.reconnecting);
    peer.disconnect();
    peer.setForeground(false);
    peer.setForeground(true);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(sockets.length, 1);
    expect(peer.state, PeerState.disconnected);
  });

  test('unpaired devices stop retries with actionable error', () async {
    rejectReason = 'unpaired device';
    await peer.connect(
      'wss://127.0.0.1:${server.port}/ws',
      fingerprint,
      '',
      () {},
    );
    await waitFor(peer, () => peer.state == PeerState.failed);
    expect(peer.status, contains('not paired'));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(sockets.length, 1);
  });

  test('expired secret is reported and never automatically retried', () async {
    rejectReason = 'pairing rejected';
    await peer.connect(
      'wss://127.0.0.1:${server.port}/ws',
      fingerprint,
      'expired',
      () {},
    );
    await waitFor(peer, () => peer.state == PeerState.failed);
    expect(peer.status, contains('expired'));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(sockets.length, 1);
  });

  test(
    'repeated foreground cycles keep the same identity and one active session',
    () async {
      await peer.connect(
        'wss://127.0.0.1:${server.port}/ws',
        fingerprint,
        '',
        () {},
      );
      await waitFor(peer, () => peer.ready);
      for (var i = 0; i < 5; i++) {
        peer.setForeground(false);
        peer.setForeground(true);
        await waitFor(peer, () => sockets.length == i + 2 && peer.ready);
        expect(provedIdentity, isTrue);
      }
      expect(
        received.every((m) => m['type'] == 'hello' && !m.containsKey('token')),
        isTrue,
      );
    },
  );
  test(
    'certificate changes on reconnect stop retries without sending credentials',
    () async {
      await peer.connect(
        'wss://127.0.0.1:${server.port}/ws',
        fingerprint,
        '',
        () {},
      );
      await waitFor(peer, () => peer.ready);
      final port = server.port;
      await server.close(force: true);
      final replacement =
          jsonDecode(generateIdentity()) as Map<String, dynamic>;
      final context = SecurityContext(withTrustedRoots: false)
        ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3
        ..useCertificateChainBytes(utf8.encode(replacement['cert'] as String))
        ..usePrivateKeyBytes(utf8.encode(replacement['key'] as String));
      server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        port,
        context,
      );
      var requests = 0;
      server.listen((request) {
        requests++;
        request.response.close();
      });
      await sockets.first.close();
      await waitFor(peer, () => peer.state == PeerState.failed);
      expect(peer.status, contains('fingerprint changed'));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(requests, 0);
      expect(received.length, 1);
    },
  );

  test('malformed responses stop retries', () async {
    await peer.connect(
      'wss://127.0.0.1:${server.port}/ws',
      fingerprint,
      '',
      () {},
    );
    await waitFor(peer, () => peer.ready);
    sockets.last.add('{not json');
    await waitFor(peer, () => peer.state == PeerState.failed);
    expect(peer.status, contains('Invalid desktop response'));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(sockets.length, 1);
  });

  test('idle heartbeat timeout reconnects without user input', () async {
    peer.dispose();
    peer = PeerClient(
      timing: const PeerTiming(
        heartbeat: Duration(milliseconds: 200),
        responseTimeout: Duration(milliseconds: 300),
        retryBase: Duration(milliseconds: 20),
        retryMax: Duration(milliseconds: 100),
      ),
    );
    await peer.connect(
      'wss://127.0.0.1:${server.port}/ws',
      fingerprint,
      '',
      () {},
    );
    await waitFor(peer, () => peer.ready);
    acknowledge = false;
    await waitFor(peer, () => sockets.length == 2 && peer.ready);
    expect(received.every((message) => message['type'] == 'hello'), isTrue);
  });
}
