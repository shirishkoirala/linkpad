import 'dart:async';
import 'dart:io';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

class DiscoveredServer {
  const DiscoveredServer(this.fingerprint, this.address);
  final String fingerprint;
  final Uri address;
}

abstract interface class ServerDiscovery {
  Future<List<DiscoveredServer>> find(
    String fingerprint, {
    required Duration timeout,
  });
  Future<void> stop();
}

class NoServerDiscovery implements ServerDiscovery {
  @override
  Future<List<DiscoveredServer>> find(
    String fingerprint, {
    required Duration timeout,
  }) async => [];
  @override
  Future<void> stop() async {}
}

abstract interface class DiscoverySession {
  Stream<BonsoirDiscoveryEvent>? get events;
  Future<void> initialize();
  Future<void> start();
  Future<void> resolve(BonsoirService service);
  Future<void> stop();
}

class _NativeSession implements DiscoverySession {
  final discovery = BonsoirDiscovery(type: '_linkpad._tcp', printLogs: false);
  bool _stopped = false;
  @override
  Stream<BonsoirDiscoveryEvent>? get events => discovery.eventStream;
  @override
  Future<void> initialize() => discovery.initialize();
  @override
  Future<void> start() => discovery.start();
  @override
  Future<void> resolve(BonsoirService service) =>
      discovery.serviceResolver.resolveService(service);
  @override
  Future<void> stop() async {
    if (_stopped || !discovery.isReady) return;
    _stopped = true;
    if (!discovery.isStopped) await discovery.stop();
  }
}

class BonjourServerDiscovery implements ServerDiscovery {
  BonjourServerDiscovery({
    DiscoverySession Function()? sessionFactory,
    Future<List<InternetAddress>> Function(String)? lookup,
  }) : _factory = sessionFactory ?? _NativeSession.new,
       _lookup = lookup ?? InternetAddress.lookup;
  final DiscoverySession Function() _factory;
  final Future<List<InternetAddress>> Function(String) _lookup;
  _Search? _search;
  int _epoch = 0;

  @override
  Future<List<DiscoveredServer>> find(
    String fingerprint, {
    required Duration timeout,
  }) => _collect(fingerprint, timeout: timeout);

  /// Advertisements are hints only; pairing still requires a verified QR/code.
  Future<List<DiscoveredServer>> browse({required Duration timeout}) =>
      _collect(null, timeout: timeout);

  Future<List<DiscoveredServer>> _collect(
    String? fingerprint, {
    required Duration timeout,
  }) async {
    final epoch = ++_epoch;
    final previous = _search;
    _search = null;
    await previous?.close();
    if (epoch != _epoch) return [];
    final search = _Search(_factory());
    _search = search;
    final records = <String, List<DiscoveredServer>>{};
    final revisions = <String, int>{};
    final inFlight = <String>{};
    var sequence = 0;
    final resolving = <String>{};
    final failed = Completer<void>();
    bool active() =>
        identical(_search, search) && !search.cancelled.isCompleted;
    void fail(Object error, StackTrace stack) {
      if (active() && !failed.isCompleted) failed.completeError(error, stack);
    }

    String key(BonsoirService service) => '${service.name}|${service.type}';
    Future<void> add(BonsoirService service) async {
      if (!active() ||
          service.name.length > 128 ||
          records.length >= 8 && !records.containsKey(key(service))) {
        return;
      }
      final attrs = service.attributes;
      if (service.type.replaceFirst(RegExp(r'\.$'), '') != '_linkpad._tcp' ||
          attrs.length > 16 ||
          attrs.entries.any((e) => e.key.length > 32 || e.value.length > 256) ||
          attrs['v'] != '1' ||
          (fingerprint != null && attrs['fp'] != fingerprint) ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(attrs['fp'] ?? '') ||
          service.port < 1 ||
          service.port > 65535) {
        return;
      }
      if (const bool.fromEnvironment('LINKPAD_DIAGNOSTICS')) {
        debugPrint('LP RESOLVED host=${service.host} port=${service.port}');
      }
      final host = service.host;
      if (host == null || host.length > 253 || host.contains('%')) return;
      final id = key(service);
      final literal = InternetAddress.tryParse(host);
      if (literal == null &&
          !host.toLowerCase().endsWith('.local') &&
          !host.toLowerCase().endsWith('.local.')) {
        return;
      }
      if (inFlight.contains(id) ||
          inFlight.length >= 8 ||
          records.length >= 8 && !records.containsKey(id)) {
        return;
      }
      records.putIfAbsent(id, () => []);
      inFlight.add(id);
      final revision = ++sequence;
      revisions[id] = revision;
      List<InternetAddress> addresses;
      try {
        addresses = literal == null ? await _lookup(host) : [literal];
      } catch (_) {
        records.remove(id);
        revisions.remove(id);
        return;
      } finally {
        inFlight.remove(id);
      }
      if (const bool.fromEnvironment('LINKPAD_DIAGNOSTICS')) {
        debugPrint('LP ADDRESSES ${addresses.map((a) => a.address).join(',')}');
      }
      if (!active() || revisions[id] != revision) return;
      records[id] = [
        for (final ip in addresses.where(_lanAddress).take(8))
          DiscoveredServer(
            attrs['fp']!,
            Uri(
              scheme: 'wss',
              host: ip.address,
              port: service.port,
              path: '/ws',
            ),
          ),
      ];
    }

    Future<void> run() async {
      await search.session.initialize();
      search.initialized = true;
      if (!active()) {
        await search.session.stop();
        return;
      }
      search.subscription = search.session.events?.listen((event) {
        if (!active()) return;
        if (const bool.fromEnvironment('LINKPAD_DIAGNOSTICS')) {
          debugPrint('LP BROWSE ${event.runtimeType}');
        }
        if (event is BonsoirDiscoveryServiceFoundEvent) {
          final id = key(event.service);
          if (resolving.length < 16 &&
              event.service.name.length <= 128 &&
              resolving.add(id)) {
            unawaited(
              search.session.resolve(event.service).catchError((Object _) {
                resolving.remove(id);
              }),
            );
          }
        } else if (event is BonsoirDiscoveryServiceResolvedEvent) {
          resolving.remove(key(event.service));
          unawaited(add(event.service));
        } else if (event is BonsoirDiscoveryServiceUpdatedEvent) {
          unawaited(add(event.service));
        } else if (event is BonsoirDiscoveryServiceLostEvent) {
          final id = key(event.service);
          records.remove(id);
          revisions.remove(id);
        }
      }, onError: fail);
      await search.session.start();
      if (!active()) await search.session.stop();
    }

    unawaited(run().catchError(fail));
    try {
      await Future.any<void>([
        Future<void>.delayed(timeout),
        search.cancelled.future,
        failed.future,
      ]);
      if (!active()) return [];
      return records.values.expand((v) => v).fold<List<DiscoveredServer>>([], (
        list,
        item,
      ) {
        if (list.length < 8 &&
            !list.any(
              (e) =>
                  e.fingerprint == item.fingerprint &&
                  (fingerprint == null || e.address == item.address),
            )) {
          list.add(item);
        }
        return list;
      });
    } finally {
      if (identical(_search, search)) _search = null;
      await search.close();
    }
  }

  static bool _lanAddress(InternetAddress ip) {
    if (ip.isLoopback ||
        ip.isMulticast ||
        ip.isLinkLocal ||
        ip.address == '0.0.0.0' ||
        ip.address == '::') {
      return false;
    }
    if (ip.type == InternetAddressType.IPv6) return true;
    final b = ip.rawAddress;
    return b[0] == 10 ||
        b[0] == 172 && b[1] >= 16 && b[1] <= 31 ||
        b[0] == 192 && b[1] == 168;
  }

  @override
  Future<void> stop() async {
    _epoch++;
    final search = _search;
    _search = null;
    await search?.close();
  }
}

class _Search {
  _Search(this.session);
  final DiscoverySession session;
  final cancelled = Completer<void>();
  StreamSubscription<BonsoirDiscoveryEvent>? subscription;
  bool initialized = false;
  Future<void> close() async {
    if (!cancelled.isCompleted) cancelled.complete();
    await subscription?.cancel();
    subscription = null;
    if (initialized) {
      try {
        await session.stop();
      } catch (_) {}
    }
  }
}
