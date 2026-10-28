import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'design_system.dart';
import 'server_discovery.dart';

class NearbyComputers extends StatefulWidget {
  const NearbyComputers({
    super.key,
    required this.savedIds,
    required this.onPair,
    this.discovery,
    this.enabled = true,
  });
  final Set<String> savedIds;
  final ValueChanged<DiscoveredServer> onPair;
  final BonjourServerDiscovery? discovery;
  final bool enabled;

  @override
  State<NearbyComputers> createState() => _NearbyComputersState();
}

class _NearbyComputersState extends State<NearbyComputers>
    with WidgetsBindingObserver {
  late final BonjourServerDiscovery? _discovery =
      widget.discovery ??
      (Platform.isIOS || Platform.isAndroid ? BonjourServerDiscovery() : null);
  List<DiscoveredServer> _servers = [];
  Timer? _refresh;
  bool _scanning = false, _foreground = true;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _scan();
  }

  @override
  void didUpdateWidget(NearbyComputers oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      if (widget.enabled) {
        _scan();
      } else {
        _stop();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _scan();
    } else {
      _stop();
    }
  }

  void _stop() {
    _generation++;
    _refresh?.cancel();
    unawaited(_discovery?.stop());
    _scanning = false;
  }

  Future<void> _scan() async {
    if (!mounted ||
        !_foreground ||
        !widget.enabled ||
        _scanning ||
        _discovery == null) {
      return;
    }
    _refresh?.cancel();
    final generation = ++_generation;
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final servers = await _discovery.browse(
        timeout: const Duration(seconds: 4),
      );
      if (!mounted || generation != _generation) return;
      final seen = <String>{};
      setState(
        () => _servers = servers.where((s) => seen.add(s.fingerprint)).toList(),
      );
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _servers = [];
        _error =
            'Couldn’t search. Allow Local Network access in your phone settings.';
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _scanning = false);
        _refresh = Timer(const Duration(seconds: 8), _scan);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nearby = _servers
        .where((s) => !widget.savedIds.contains(s.fingerprint))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('NEARBY COMPUTERS', style: LinkpadStyle.eyebrow),
            ),
            if (_scanning)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            IconButton(
              tooltip: 'Refresh nearby computers',
              onPressed: _scanning || !widget.enabled ? null : _scan,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (nearby.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error ??
                  (_scanning
                      ? 'Looking for computers…'
                      : 'No new computers found. Open Linkpad on your computer and use the same local network.'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final server in nearby)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.desktop_windows_outlined),
            title: Text(server.address.host),
            subtitle: const Text('Nearby · Ready to pair'),
            trailing: TextButton(
              onPressed: widget.enabled ? () => widget.onPair(server) : null,
              child: const Text('Pair'),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}
