import 'dart:io';
import 'dart:async';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/server_discovery.dart';

class FakeSession implements DiscoverySession {
  final controller = StreamController<BonsoirDiscoveryEvent>.broadcast();
  final initialized = Completer<void>();
  bool delayed = false;
  int starts = 0, stops = 0;
  @override
  Stream<BonsoirDiscoveryEvent> get events => controller.stream;
  @override
  Future<void> initialize() async {
    if (delayed) await initialized.future;
  }

  @override
  Future<void> start() async {
    starts++;
  }

  @override
  Future<void> stop() async {
    if (stops == 0) stops++;
  }

  @override
  Future<void> resolve(BonsoirService service) async {}
}

void main() {
  final pin = List.filled(64, 'a').join();
  BonsoirService service({
    String name = 'computer',
    String host = '192.168.1.203',
    int port = 4747,
    String? fingerprint,
  }) => BonsoirService(
    name: name,
    type: '_linkpad._tcp',
    host: host,
    port: port,
    attributes: {'v': '1', 'fp': fingerprint ?? pin},
  );
  for (final mode in ['saved', 'nearby']) {
    test(
      '$mode discovery keeps LAN addresses after many unusable IPv6 results',
      () async {
        final session = FakeSession();
        final browser = BonjourServerDiscovery(
          sessionFactory: () => session,
          lookup: (_) async => [
            for (var i = 1; i <= 11; i++) InternetAddress('fe80::$i'),
            InternetAddress('192.168.1.116'),
          ],
        );
        final result = mode == 'saved'
            ? browser.find(pin, timeout: const Duration(milliseconds: 80))
            : browser.browse(timeout: const Duration(milliseconds: 80));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        session.controller.add(
          BonsoirDiscoveryServiceResolvedEvent(
            service: service(host: 'computer.local.'),
          ),
        );
        final found = await result;
        expect(found.map((s) => s.address.toString()).toList(), [
          'wss://192.168.1.116:4747/ws',
        ]);
        await session.controller.close();
      },
    );
  }

  test(
    'browse counts computers rather than addresses toward its result limit',
    () async {
      final session = FakeSession();
      final browser = BonjourServerDiscovery(
        sessionFactory: () => session,
        lookup: (_) async =>
            List.generate(8, (i) => InternetAddress('192.168.1.${i + 10}')),
      );
      final result = browser.browse(timeout: const Duration(milliseconds: 80));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      session.controller.add(
        BonsoirDiscoveryServiceResolvedEvent(
          service: service(host: 'mac.local'),
        ),
      );
      session.controller.add(
        BonsoirDiscoveryServiceResolvedEvent(
          service: service(
            name: 'other',
            fingerprint: List.filled(64, 'b').join(),
          ),
        ),
      );
      final found = await result;
      expect(found.map((s) => s.fingerprint).toSet(), {
        pin,
        List.filled(64, 'b').join(),
      });
      await session.controller.close();
    },
  );

  test(
    'browse returns distinct unpaired identities and rejects invalid metadata',
    () async {
      final session = FakeSession();
      final browser = BonjourServerDiscovery(sessionFactory: () => session);
      final result = browser.browse(timeout: const Duration(milliseconds: 80));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      for (final s in [
        service(),
        service(name: 'second', fingerprint: List.filled(64, 'b').join()),
        service(fingerprint: 'forged'),
      ]) {
        session.controller.add(
          BonsoirDiscoveryServiceResolvedEvent(service: s),
        );
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      final found = await result;
      expect(found.map((s) => s.fingerprint).toSet(), {
        pin,
        List.filled(64, 'b').join(),
      });
      await session.controller.close();
    },
  );

  test(
    'discovery validates metadata and builds only LAN websocket endpoints',
    () async {
      final session = FakeSession();
      final browser = BonjourServerDiscovery(sessionFactory: () => session);
      final result = browser.find(
        pin,
        timeout: const Duration(milliseconds: 80),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      for (final s in [
        service(fingerprint: 'forged'),
        service(host: '127.0.0.1'),
        service(host: '8.8.8.8'),
        service(port: 0),
        service(),
      ]) {
        session.controller.add(
          BonsoirDiscoveryServiceResolvedEvent(service: s),
        );
      }
      final found = await result;
      expect(found.map((s) => s.address.toString()), [
        'wss://192.168.1.203:4747/ws',
      ]);
      expect(session.stops, 1);
      await session.controller.close();
    },
  );
  test(
    'cancellation completes lookup and rejects late initialization',
    () async {
      final session = FakeSession()..delayed = true;
      final browser = BonjourServerDiscovery(sessionFactory: () => session);
      final result = browser.find(pin, timeout: const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await browser.stop();
      expect(await result, isEmpty);
      session.initialized.complete();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(session.starts, 0);
      expect(session.stops, 1);
      await session.controller.close();
    },
  );
  test('withdrawn service is removed before returning candidates', () async {
    final session = FakeSession();
    final browser = BonjourServerDiscovery(sessionFactory: () => session);
    final result = browser.find(pin, timeout: const Duration(milliseconds: 70));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    session.controller.add(
      BonsoirDiscoveryServiceResolvedEvent(service: service()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    session.controller.add(
      BonsoirDiscoveryServiceLostEvent(service: service()),
    );
    expect(await result, isEmpty);
    await session.controller.close();
  });
  test('resolved service flood cannot start unbounded DNS lookups', () async {
    final session = FakeSession();
    final pending = Completer<List<InternetAddress>>();
    var lookups = 0;
    final browser = BonjourServerDiscovery(
      sessionFactory: () => session,
      lookup: (host) {
        lookups++;
        return pending.future;
      },
    );
    final result = browser.find(
      pin,
      timeout: const Duration(milliseconds: 120),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    for (var i = 0; i < 100; i++) {
      final s = BonsoirService(
        name: 'candidate$i',
        type: '_linkpad._tcp',
        host: 'computer$i.local',
        port: 4747,
        attributes: {'v': '1', 'fp': pin},
      );
      session.controller.add(BonsoirDiscoveryServiceResolvedEvent(service: s));
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final count = lookups;
    pending.complete([InternetAddress('192.168.1.203')]);
    await result;
    await session.controller.close();
    expect(count, lessThanOrEqualTo(8));
  });
  test(
    'immediate cancellation cannot start a browse after stop returns',
    () async {
      final session = FakeSession();
      final browser = BonjourServerDiscovery(sessionFactory: () => session);
      final result = browser.find(pin, timeout: const Duration(seconds: 5));
      await browser.stop();
      expect(await result.timeout(const Duration(milliseconds: 100)), isEmpty);
      expect(session.starts, 0);
      await session.controller.close();
    },
  );
}
