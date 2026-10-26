import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/peer_client.dart';

Future<void> waitFor(
  PeerClient peer,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
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
  Duration ackDelay = Duration.zero;
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
    ackDelay = Duration.zero;
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
          if (ackDelay == Duration.zero) {
            socket.add(jsonEncode({'version': 1, 'type': 'ack'}));
          } else {
            Future<void>.delayed(ackDelay, () {
              if (socket.readyState == WebSocket.open) {
                try {
                  socket.add(jsonEncode({'version': 1, 'type': 'ack'}));
                } on StateError {
                  /* The test may have closed the sink. */
                }
              }
            });
          }
        }
      });
    });
    peer = PeerClient(
      timing: const PeerTiming(
        maxMotionInFlight: 1,
        responseTimeout: Duration(milliseconds: 500),
        inputPauseAfter: Duration(milliseconds: 150),
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
    'standalone Super requires explicit server capability and resets on reconnect',
    () async {
      capabilities = ['pointer.v1', 'keyboard.v1', 'keyboard.super.v1'];
      await peer.connect(
        'wss://127.0.0.1:${server.port}/ws',
        fingerprint,
        '',
        () {},
      );
      await waitFor(peer, () => peer.canKeyboard);
      expect(peer.supportsStandaloneSuper, isTrue);
      expect(peer.keyboardKey('super'), isTrue);
      await waitFor(peer, () => received.length == 2);
      expect(received.last['key'], 'super');
      peer.disconnect();
      expect(peer.supportsStandaloneSuper, isFalse);
      capabilities = ['pointer.v1', 'keyboard.v1'];
      await peer.connect(
        'wss://127.0.0.1:${server.port}/ws',
        fingerprint,
        '',
        () {},
      );
      await waitFor(peer, () => peer.canKeyboard);
      expect(peer.keyboardKey('super'), isFalse);
      expect(peer.keyboardKey('e', modifiers: {'super'}), isTrue);
      await waitFor(peer, () => received.length == 4);
      expect(received.last['key'], 'e');
    },
  );

  test(
    'switching between verified computers closes the old drag and preserves both pairings',
    () async {
      capabilities = ['pointer.v1', 'drag.v1'];
      await peer.connect(
        'wss://127.0.0.1:${server.port}/ws',
        fingerprint,
        'first-secret',
        () {},
      );
      await waitFor(
        peer,
        () => peer.ready && peer.computers.find(fingerprint) != null,
      );
      await peer.computers.rename(fingerprint, 'Linux PC');
      peer.startDrag();
      await waitFor(peer, () => received.any((m) => m['action'] == 'start'));
      final firstSocket = sockets.first;
      final other = jsonDecode(generateIdentity()) as Map<String, dynamic>;
      final cert = other['cert'] as String;
      final der = base64Decode(
        cert
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && !l.startsWith('-----'))
            .join(),
      );
      final otherPin = sha256.convert(der).toString();
      final context = SecurityContext(withTrustedRoots: false)
        ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3
        ..useCertificateChainBytes(utf8.encode(cert))
        ..usePrivateKeyBytes(utf8.encode(other['key'] as String))
        ..setTrustedCertificatesBytes(utf8.encode(clientCertificate));
      final otherServer = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
        requestClientCertificate: true,
      );
      final otherSockets = <WebSocket>[],
          otherMessages = <Map<String, dynamic>>[];
      otherServer.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        otherSockets.add(socket);
        var first = true;
        socket.listen((data) {
          final message = jsonDecode(data as String) as Map<String, dynamic>;
          otherMessages.add(message);
          socket.add(
            jsonEncode(
              first
                  ? {
                      'version': 1,
                      'type': 'ready',
                      'capabilities': ['pointer.v1'],
                    }
                  : {'version': 1, 'type': 'ack'},
            ),
          );
          first = false;
        });
      });
      try {
        await peer.connect(
          'wss://127.0.0.1:${otherServer.port}/ws',
          otherPin,
          'second-secret',
          () {},
        );
        await waitFor(
          peer,
          () =>
              peer.ready &&
              peer.computers.find(otherPin) != null &&
              firstSocket.readyState == WebSocket.closed,
        );
        expect(peer.dragging, isFalse);
        expect(peer.canDrag, isFalse);
        expect(peer.computers.computers.length, 2);
        expect(peer.computers.find(fingerprint)!.name, 'Linux PC');
        peer.move(15, 5);
        await waitFor(
          peer,
          () => otherMessages.any((m) => m['type'] == 'pointer'),
        );
        await peer.connect(
          'wss://127.0.0.1:${server.port}/ws',
          fingerprint,
          '',
          () {},
        );
        await waitFor(
          peer,
          () =>
              peer.ready &&
              peer.canDrag &&
              otherSockets.first.readyState == WebSocket.closed,
        );
        expect(peer.desktopName, 'Linux PC');
        expect(peer.dragging, isFalse);
        expect(peer.computers.computers.length, 2);
        final raw = await PeerClient.storage.read(key: 'computers_v1');
        expect(raw, isNot(contains('first-secret')));
        expect(raw, isNot(contains('second-secret')));
      } finally {
        peer.disconnect();
        for (final socket in otherSockets) {
          await socket.close();
        }
        await otherServer.close(force: true);
      }
    },
  );

  test(
    'drag press, movement, keepalive and release are acknowledged in order',
    () async {
      capabilities = ['pointer.v1', 'drag.v1'];
      await peer.connect(
        'wss://127.0.0.1:${server.port}/ws',
        fingerprint,
        '',
        () {},
      );
      await waitFor(peer, () => peer.canDrag);
      expect(peer.startDrag(), isTrue);
      await waitFor(peer, () => received.any((m) => m['action'] == 'start'));
      peer.move(20, 10);
      await waitFor(peer, () => received.any((m) => m['action'] == 'move'));
      await waitFor(peer, () => received.any((m) => m['action'] == 'hold'));
      peer.endDrag();
      await waitFor(peer, () => received.any((m) => m['action'] == 'end'));
      expect(
        received.where((m) => m['type'] == 'drag').map((m) => m['action']),
        ['start', 'move', 'hold', 'end'],
      );
      expect(peer.dragging, isFalse);
      expect(received.any((m) => m['button'] == 'left'), isFalse);
    },
  );

  test('very quick clicks work and cancelled contacts do not click', () async {
    capabilities = ['pointer.v1', 'drag.v1'];
    await peer.connect(
      'wss://127.0.0.1:${server.port}/ws',
      fingerprint,
      '',
      () {},
    );
    await waitFor(peer, () => peer.canDrag);
    peer.startDrag();
    peer.endDrag();
    await waitFor(peer, () => received.any((m) => m['button'] == 'left'));
    expect(received.any((m) => m['type'] == 'drag'), isFalse);
    received.clear();
    peer.startDrag();
    peer.cancelDrag();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(received, isEmpty);
  });

  test('stalled drag cancels and never resumes after reconnect', () async {
    capabilities = ['pointer.v1', 'drag.v1'];
    await peer.connect(
      'wss://127.0.0.1:${server.port}/ws',
      fingerprint,
      '',
      () {},
    );
    await waitFor(peer, () => peer.canDrag);
    peer.startDrag();
    await waitFor(peer, () => received.any((m) => m['action'] == 'start'));
    acknowledge = false;
    peer.move(20, 0);
    await waitFor(peer, () => !peer.dragging);
    expect(peer.canDrag, isFalse);
    acknowledge = true;
    await waitFor(peer, () => sockets.length >= 2 && peer.ready);
    expect(peer.dragging, isFalse);
    expect(received.where((m) => m['action'] == 'start').length, 1);
  });

  test(
    'full keyboard queue rejects new input visibly and resumes after draining',
    () async {
      capabilities = ['pointer.v1', 'keyboard.v1'];
      acknowledge = false;
      await peer.connect(
        'wss://127.0.0.1:${server.port}/ws',
        fingerprint,
        '',
        () {},
      );
      await waitFor(peer, () => peer.canKeyboard);
      for (var i = 0; i < 64; i++) {
        expect(peer.typeText('$i'), isTrue);
      }
      expect(peer.inputQueueFull, isTrue);
      expect(peer.canKeyboard, isFalse);
      expect(peer.typeText('overflow'), isFalse);
      await waitFor(
        peer,
        () => received.where((m) => m['type'] == 'keyboard').length == 1,
      );
      expect(peer.inputQueueFull, isFalse);
      expect(peer.canKeyboard, isTrue);
      acknowledge = true;
      sockets.last.add(jsonEncode({'version': 1, 'type': 'ack'}));
      await waitFor(
        peer,
        () => received.where((m) => m['type'] == 'keyboard').length == 64,
      );
      expect(
        received.where((m) => m['type'] == 'keyboard').map((m) => m['text']),
        List.generate(64, (i) => '$i'),
      );
    },
  );

  test(
    'focus click survives keyboard backlog while stale motion expires',
    () async {
      capabilities = ['pointer.v1', 'keyboard.v1'];
      acknowledge = false;
      await peer.connect(
        'wss://127.0.0.1:${server.port}/ws',
        fingerprint,
        '',
        () {},
      );
      await waitFor(peer, () => peer.canKeyboard);
      peer.typeText('a');
      await waitFor(peer, () => received.length == 2);
      peer.move(20, 0);
      peer.click('left');
      peer.typeText('b');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      acknowledge = true;
      sockets.last.add(jsonEncode({'version': 1, 'type': 'ack'}));
      await waitFor(peer, () => received.length == 4);
      expect(received[2]['button'], 'left');
      expect(received[3]['text'], 'b');
      expect(received.where((m) => m['dx'] == 20), isEmpty);
    },
  );

  test(
    'keyboard ordering never converts held drag movement into a pointer click path',
    () async {
      capabilities = ['pointer.v1', 'keyboard.v1', 'drag.v1'];
      await peer.connect(
        'wss://127.0.0.1:${server.port}/ws',
        fingerprint,
        '',
        () {},
      );
      await waitFor(peer, () => peer.canDrag);
      peer.startDrag();
      await waitFor(peer, () => received.length == 2);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      acknowledge = false;
      peer.typeText('a');
      await waitFor(peer, () => received.length == 3);
      peer.move(10, 0);
      peer.typeText('b');
      peer.endDrag();
      acknowledge = true;
      sockets.last.add(jsonEncode({'version': 1, 'type': 'ack'}));
      await waitFor(peer, () => received.length == 6);
      expect(received[3]['type'], 'drag');
      expect(received[3]['action'], 'move');
      expect(received[4]['action'], 'end');
      expect(received[5]['text'], 'b');
    },
  );

  test('accepted keyboard backlog survives more than three seconds', () async {
    capabilities = ['pointer.v1', 'keyboard.v1'];
    ackDelay = const Duration(milliseconds: 200);
    await peer.connect(
      'wss://127.0.0.1:${server.port}/ws',
      fingerprint,
      '',
      () {},
    );
    await waitFor(peer, () => peer.canKeyboard);
    for (var i = 0; i < 20; i++) {
      expect(peer.typeText('$i'), isTrue);
    }
    await waitFor(
      peer,
      () => received.where((m) => m['type'] == 'keyboard').length == 20,
      timeout: const Duration(seconds: 10),
    );
    expect(
      received.where((m) => m['type'] == 'keyboard').map((m) => m['text']),
      List.generate(20, (i) => '$i'),
    );
  });

  test('click precedes a later keyboard press before the next frame', () async {
    capabilities = ['pointer.v1', 'keyboard.v1'];
    await peer.connect(
      'wss://127.0.0.1:${server.port}/ws',
      fingerprint,
      '',
      () {},
    );
    await waitFor(peer, () => peer.canKeyboard);
    peer.click('left');
    peer.typeText('a');
    await waitFor(peer, () => received.length == 3);
    expect(received.skip(1).map((m) => m['type']), ['pointer', 'keyboard']);
  });

  test(
    'queued keyboard presses survive slow acknowledgements in order',
    () async {
      capabilities = ['pointer.v1', 'keyboard.v1'];
      acknowledge = false;
      await peer.connect(
        'wss://127.0.0.1:${server.port}/ws',
        fingerprint,
        '',
        () {},
      );
      await waitFor(peer, () => peer.canKeyboard);
      expect(peer.typeText('h'), isTrue);
      expect(peer.typeText('i'), isTrue);
      expect(peer.keyboardKey('backspace'), isTrue);
      expect(peer.typeText('!'), isTrue);
      for (var count = 1; count <= 4; count++) {
        await waitFor(
          peer,
          () => received.where((m) => m['type'] == 'keyboard').length == count,
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        sockets.last.add(jsonEncode({'version': 1, 'type': 'ack'}));
      }
      final events = received.where((m) => m['type'] == 'keyboard').toList();
      expect(events.map((m) => m['text'] ?? m['key']), [
        'h',
        'i',
        'backspace',
        '!',
      ]);
      expect(events, hasLength(4));
    },
  );

  test('disconnect discards queued keyboard presses', () async {
    capabilities = ['pointer.v1', 'keyboard.v1'];
    acknowledge = false;
    await peer.connect(
      'wss://127.0.0.1:${server.port}/ws',
      fingerprint,
      '',
      () {},
    );
    await waitFor(peer, () => peer.canKeyboard);
    peer.typeText('a');
    peer.typeText('b');
    await waitFor(
      peer,
      () => received.where((m) => m['type'] == 'keyboard').length == 1,
    );
    peer.disconnect();
    acknowledge = true;
    await peer.connect(
      'wss://127.0.0.1:${server.port}/ws',
      fingerprint,
      '',
      () {},
    );
    await waitFor(peer, () => peer.canKeyboard);
    peer.typeText('c');
    await waitFor(
      peer,
      () => received.where((m) => m['type'] == 'keyboard').length == 2,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(
      received.where((m) => m['type'] == 'keyboard').map((m) => m['text']),
      ['a', 'c'],
    );
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
      await waitFor(peer, () => peer.computers.find(fingerprint) != null);
      final saved = await PeerClient.storage.read(key: 'computers_v1');
      expect(
        (jsonDecode(saved!)['computers'] as List).single['pin'],
        fingerprint,
      );
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

  test(
    'late acknowledgement flushes coalesced fresh motion without another frame wait',
    () async {
      peer.dispose();
      peer = PeerClient(
        timing: const PeerTiming(
          maxMotionInFlight: 1,
          frameInterval: Duration(milliseconds: 400),
          inputMaxAge: Duration(seconds: 3),
          inputPauseAfter: Duration(seconds: 3),
          responseTimeout: Duration(seconds: 5),
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
      peer.move(1, 1);
      await waitFor(peer, () => received.length == 2);
      peer.move(3, 2);
      peer.move(4, 1);
      peer.click('left');
      peer.move(-2, 0);
      // A deliberately delayed response consumes the entire cadence interval.
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(
        received.length,
        2,
        reason: 'Only one message may be unacknowledged.',
      );
      final afterAck = Stopwatch()..start();
      sockets.last.add(jsonEncode({'version': 1, 'type': 'ack'}));
      await waitFor(peer, () => received.length == 3);
      expect(afterAck.elapsed, lessThan(const Duration(milliseconds: 200)));
      expect(received.last['dx'], 7);
      expect(received.last['dy'], 3);
      expect(received.last['button'], isNull);
      expect(
        peer.roundTripTime,
        greaterThanOrEqualTo(const Duration(milliseconds: 400)),
      );
      expect(peer.connectionSummary, contains(' ms'));
      sockets.last.add(jsonEncode({'version': 1, 'type': 'ack'}));
      await waitFor(peer, () => received.length == 4);
      expect(received.last['button'], 'left');
      sockets.last.add(jsonEncode({'version': 1, 'type': 'ack'}));
      await waitFor(peer, () => received.length == 5);
      expect(received.last['dx'], -2);
      expect(received.last['button'], isNull);
      peer.disconnect();
      expect(peer.roundTripTime, isNull);
      expect(peer.connectionSummary, 'Disconnected');
    },
  );

  test(
    'fast acknowledgements keep the send-rate cap and throttle latency notifications',
    () async {
      peer.dispose();
      peer = PeerClient(
        timing: const PeerTiming(frameInterval: Duration(milliseconds: 120)),
      );
      await peer.connect(
        'wss://127.0.0.1:${server.port}/ws',
        fingerprint,
        '',
        () {},
      );
      await waitFor(peer, () => peer.ready);
      var notifications = 0;
      peer.addListener(() => notifications++);
      peer.move(1, 0);
      await waitFor(peer, () => peer.roundTripTime != null);
      final initialNotifications = notifications;
      final sinceFirst = Stopwatch()..start();
      peer.move(2, 0);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(received.length, 2);
      await waitFor(peer, () => received.length == 3);
      expect(
        sinceFirst.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 85)),
      );
      // Wait for this ack to be handled, without causing another status rebuild.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(notifications, initialNotifications);
    },
  );

  test(
    'a temporary response stall recovers on the same socket without replaying input',
    () async {
      peer.dispose();
      peer =
          PeerClient(); // Exercise the production pause and reconnect thresholds.
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
      expect(peer.connected, isTrue);
      expect(peer.connectionSummary, 'Connection slow • input paused');
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      expect(
        peer.connected,
        isTrue,
        reason: 'A brief stall should not tear down TLS.',
      );
      expect(sockets.length, 1);
      expect(peer.reconnectCount, 0);
      peer.move(100, 100); // Input remains paused during the stall.
      acknowledge = true;
      sockets.last.add(jsonEncode({'version': 1, 'type': 'ack'}));
      await waitFor(peer, () => peer.ready);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(
        received.length,
        2,
        reason: 'Expired motion and clicks must not replay.',
      );
      peer.move(3, 4);
      await waitFor(peer, () => received.length == 3);
      expect(received.last['dx'], 3);
      expect(received.last['dy'], 4);
      expect(peer.lastConnectionIssue, isNull);
    },
  );

  test(
    'a 280ms reply keeps input active, expires old input, and preserves fresh motion',
    () async {
      peer.dispose();
      peer = PeerClient(timing: const PeerTiming(maxMotionInFlight: 1));
      await peer.connect(
        'wss://127.0.0.1:${server.port}/ws',
        fingerprint,
        '',
        () {},
      );
      await waitFor(peer, () => peer.ready);
      acknowledge = false;
      peer.move(1, 0);
      await waitFor(peer, () => received.length == 2);
      peer.move(100, 100);
      peer.click('right');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        peer.ready,
        isTrue,
        reason: 'Response tolerance must be separate from event freshness.',
      );
      // These events are fresh when the held acknowledgement is released.
      peer.move(3, 2);
      peer.move(4, 1);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(peer.ready, isTrue);
      expect(sockets.length, 1);
      sockets.last.add(jsonEncode({'version': 1, 'type': 'ack'}));
      await waitFor(peer, () => received.length == 3);
      expect(received.last['dx'], 7);
      expect(received.last['dy'], 3);
      expect(received.last['button'], isNull);
      expect(
        peer.roundTripTime,
        greaterThanOrEqualTo(const Duration(milliseconds: 250)),
      );
      acknowledge = true;
      sockets.last.add(jsonEncode({'version': 1, 'type': 'ack'}));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        received.length,
        3,
        reason: 'The expired motion and click must not replay.',
      );
      expect(peer.reconnectCount, 0);
    },
  );

  test(
    'movement window is bounded and clicks remain acknowledgement barriers',
    () async {
      peer.dispose();
      peer = PeerClient();
      await peer.connect(
        'wss://127.0.0.1:${server.port}/ws',
        fingerprint,
        '',
        () {},
      );
      await waitFor(peer, () => peer.ready);
      acknowledge = false;
      for (var i = 0; i < 4; i++) {
        peer.move(i + 1, 0);
        await waitFor(peer, () => received.length == i + 2);
      }
      peer.move(5, 0);
      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(
        received.length,
        5,
        reason: 'At most four movements may be outstanding.',
      );
      sockets.last.add(jsonEncode({'version': 1, 'type': 'ack'}));
      await waitFor(peer, () => received.length == 6);
      expect(received.last['dx'], 5);
      peer.click('left');
      peer.move(6, 0);
      for (var i = 0; i < 3; i++) {
        sockets.last.add(jsonEncode({'version': 1, 'type': 'ack'}));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(
        received.length,
        6,
        reason: 'The click waits for all movement replies.',
      );
      sockets.last.add(jsonEncode({'version': 1, 'type': 'ack'}));
      await waitFor(peer, () => received.length == 7);
      expect(received.last['button'], 'left');
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(
        received.length,
        7,
        reason: 'Movement cannot pass a pending click.',
      );
      sockets.last.add(jsonEncode({'version': 1, 'type': 'ack'}));
      await waitFor(peer, () => received.length == 8);
      expect(received.last['dx'], 6);
      acknowledge = true;
      sockets.last.add(jsonEncode({'version': 1, 'type': 'ack'}));
    },
  );

  test('a stalled movement window drains before fresh input resumes', () async {
    peer.dispose();
    peer = PeerClient(
      timing: const PeerTiming(inputPauseAfter: Duration(milliseconds: 120)),
    );
    await peer.connect(
      'wss://127.0.0.1:${server.port}/ws',
      fingerprint,
      '',
      () {},
    );
    await waitFor(peer, () => peer.ready);
    acknowledge = false;
    for (var i = 0; i < 4; i++) {
      peer.move(1, 0);
      await waitFor(peer, () => received.length == i + 2);
    }
    peer.move(99, 99);
    await waitFor(peer, () => peer.waitingForResponse);
    for (var i = 0; i < 3; i++) {
      sockets.last.add(jsonEncode({'version': 1, 'type': 'ack'}));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(peer.ready, isFalse);
    }
    acknowledge = true;
    sockets.last.add(jsonEncode({'version': 1, 'type': 'ack'}));
    await waitFor(peer, () => peer.ready);
    expect(
      received.length,
      5,
      reason: 'Buffered movement must not replay after a stall.',
    );
    peer.move(2, 3);
    await waitFor(peer, () => received.length == 6);
    expect(received.last['dx'], 2);
    expect(sockets.length, 1);
  });

  test('pause budget adapts to a measured slow round trip', () async {
    peer.dispose();
    peer = PeerClient();
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
    await Future<void>.delayed(const Duration(milliseconds: 250));
    sockets.last.add(jsonEncode({'version': 1, 'type': 'ack'}));
    await waitFor(peer, () => peer.roundTripTime != null);
    peer.click('right');
    await waitFor(peer, () => received.length == 3);
    await Future<void>.delayed(const Duration(milliseconds: 550));
    expect(
      peer.ready,
      isTrue,
      reason: 'Known latency allows more than the baseline 500ms.',
    );
    await waitFor(peer, () => peer.waitingForResponse);
    expect(sockets.length, 1);
    acknowledge = true;
    sockets.last.add(jsonEncode({'version': 1, 'type': 'ack'}));
    await waitFor(peer, () => peer.ready);
  });

  test(
    'later movement sends cannot postpone the oldest response timeout',
    () async {
      peer.dispose();
      peer = PeerClient(
        timing: const PeerTiming(
          inputPauseAfter: Duration(milliseconds: 180),
          responseTimeout: Duration(milliseconds: 350),
          retryBase: Duration(milliseconds: 20),
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
      final elapsed = Stopwatch()..start();
      for (var i = 0; i < 3; i++) {
        peer.move(1, 0);
        await waitFor(peer, () => received.length == i + 2);
        await Future<void>.delayed(const Duration(milliseconds: 55));
      }
      await waitFor(peer, () => peer.waitingForResponse);
      expect(elapsed.elapsed, lessThan(const Duration(milliseconds: 280)));
      await waitFor(peer, () => peer.reconnectCount == 1);
      expect(elapsed.elapsed, lessThan(const Duration(milliseconds: 450)));
      await waitFor(peer, () => peer.ready && sockets.length == 2);
      expect(
        received.where((message) => message['type'] == 'pointer').length,
        3,
      );
    },
  );

  test(
    'diagnostics separate server processing and reset on disconnect',
    () async {
      peer.dispose();
      peer = PeerClient();
      await peer.connect(
        'wss://127.0.0.1:${server.port}/ws',
        fingerprint,
        '',
        () {},
      );
      await waitFor(peer, () => peer.ready);
      expect(peer.serverProcessingTime, isNull);
      expect(peer.connectionDetails, contains('Desktop timing unavailable'));
      acknowledge = false;
      peer.click('left');
      await waitFor(peer, () => received.length == 2);
      await Future<void>.delayed(const Duration(milliseconds: 280));
      sockets.last.add(
        jsonEncode({
          'version': 1,
          'type': 'ack',
          'server_processing_us': 20000,
        }),
      );
      await waitFor(peer, () => peer.serverProcessingTime != null);
      expect(peer.serverProcessingTime, const Duration(milliseconds: 20));
      expect(
        peer.remainingResponseDelay,
        greaterThanOrEqualTo(const Duration(milliseconds: 260)),
      );
      expect(peer.connectionDetails, contains('Slow replies (≥250 ms): 1 / 1'));
      expect(peer.connectionDetails, contains('20.0 ms (smoothed)'));
      expect(peer.connectionDetails, contains('network + queues'));
      for (final invalid in [-1, 'wrong', 1.5, 999999999]) {
        peer.click('right');
        final count = received.length;
        await waitFor(peer, () => received.length > count);
        sockets.last.add(
          jsonEncode({
            'version': 1,
            'type': 'ack',
            'server_processing_us': invalid,
          }),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(peer.ready, isTrue);
        expect(peer.serverProcessingTime, const Duration(milliseconds: 20));
      }
      peer.disconnect();
      expect(peer.serverProcessingTime, isNull);
      expect(peer.remainingResponseDelay, isNull);
      expect(peer.connectionDetails, contains('Slow replies (≥250 ms): 0 / 0'));
    },
  );

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
    expect(peer.lastConnectionIssue, 'Desktop stopped responding.');
    expect(peer.reconnectCount, 1);
    expect(
      peer.connectionDetails,
      contains('Last interruption: Desktop stopped responding.'),
    );
    peer.disconnect();
    expect(peer.lastConnectionIssue, isNull);
    expect(peer.reconnectCount, 0);
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
