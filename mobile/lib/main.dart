import 'dart:convert';
import 'package:flutter/material.dart';
import 'peer_client.dart';
import 'relative_touchpad.dart';
import 'pairing_invitation.dart';
import 'pairing_scanner.dart';

void main() => runApp(const LinkpadApp());

class LinkpadApp extends StatelessWidget {
  const LinkpadApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Linkpad',
    theme: ThemeData(
      colorSchemeSeed: const Color(0xff256b62),
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    home: const ControllerPage(),
  );
}

class ControllerPage extends StatefulWidget {
  const ControllerPage({super.key});
  @override
  State<ControllerPage> createState() => _ControllerPageState();
}

class _ControllerPageState extends State<ControllerPage>
    with WidgetsBindingObserver {
  final peer = PeerClient();
  final address = TextEditingController();
  final pin = TextEditingController();
  final token = TextEditingController();
  bool _autoRestore = true;
  bool get connecting => peer.busy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    peer.setForeground(
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
    _restore();
  }

  Future<void> _restore() async {
    try {
      final saved = await PeerClient.storage.read(key: 'desktop_v1');
      if (!mounted || saved == null) return;
      final data = jsonDecode(saved) as Map<String, dynamic>;
      if (_autoRestore && address.text.isEmpty && pin.text.isEmpty) {
        address.text = data['address'] as String;
        pin.text = data['pin'] as String;
        await peer.connect(address.text, pin.text, '', token.clear);
      }
    } catch (_) {
      // Manual entry remains available if secure storage cannot be read.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    peer.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    peer.dispose();
    address.dispose();
    pin.dispose();
    token.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    FocusScope.of(context).unfocus();
    _autoRestore = false;
    await peer.connect(address.text, pin.text, token.text, token.clear);
  }

  Future<void> _scanPairing() async {
    FocusScope.of(context).unfocus();
    _autoRestore = false;
    peer.disconnect();
    token.clear();
    final invitation = await Navigator.of(context).push<PairingInvitation>(
      MaterialPageRoute(builder: (_) => const PairingScanner()),
    );
    if (!mounted || invitation == null) return;
    address.text = invitation.address;
    pin.text = invitation.fingerprint;
    token.text = invitation.secret;
    await _connect();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: peer,
    builder: (context, _) => peer.showControls
        ? MousePage(peer: peer)
        : Scaffold(
            appBar: AppBar(title: const Text('Connect to your computer')),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    'Linkpad',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    peer.status,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: connecting ? null : _scanPairing,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan QR to pair'),
                  ),
                  const SizedBox(height: 12),
                  const Text('Or enter the details manually below.'),
                  const SizedBox(height: 24),
                  TextField(
                    controller: address,
                    onChanged: (_) => _autoRestore = false,
                    autocorrect: false,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Desktop address',
                      hintText: 'wss://192.168.1.10:4747/ws',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pin,
                    onChanged: (_) => _autoRestore = false,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Verified desktop fingerprint',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: token,
                    onChanged: (_) => _autoRestore = false,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Pairing secret (first connection only)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'For manual pairing, verify the fingerprint directly on your computer.',
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: connecting ? null : _connect,
                    child: Text(connecting ? 'Connecting…' : 'Connect / pair'),
                  ),
                  if (connecting)
                    TextButton(
                      onPressed: peer.disconnect,
                      child: const Text('Cancel'),
                    ),
                ],
              ),
            ),
          ),
  );
}

class MousePage extends StatelessWidget {
  const MousePage({super.key, required this.peer});
  final PeerClient peer;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) peer.disconnect();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Touchpad'),
        leading: IconButton(
          onPressed: peer.disconnect,
          tooltip: 'Disconnect and return',
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          TextButton(
            onPressed: peer.disconnect,
            child: const Text('Disconnect'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    peer.ready ? Icons.check_circle : Icons.info_outline,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(peer.status)),
                ],
              ),
              if (peer.storageWarning != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(peer.storageWarning!),
                ),
              const SizedBox(height: 16),
              Expanded(
                child: Semantics(
                  label: 'Touchpad. Drag to move the desktop pointer.',
                  enabled: peer.ready,
                  child: RelativeTouchpad(
                    onScroll: peer.canScroll ? peer.scroll : null,
                    onClick: peer.click,
                    enabled: peer.ready,
                    onMove: peer.move,
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.touch_app_outlined, size: 40),
                          const SizedBox(height: 12),
                          Text(
                            peer.ready
                                ? 'Drag to move · tap to click'
                                : 'Waiting for the connection…',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // ponytail: D-pad sends arrow keys via key.v1; no cursor nudging.
              Semantics(
                label: 'D-pad. Tap to press an arrow key on the desktop.',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: peer.canKey
                          ? () => peer.pressKey('left')
                          : null,
                      tooltip: 'Left arrow',
                      icon: const Icon(Icons.arrow_left),
                    ),
                    IconButton(
                      onPressed: peer.canKey ? () => peer.pressKey('up') : null,
                      tooltip: 'Up arrow',
                      icon: const Icon(Icons.arrow_drop_up),
                    ),
                    IconButton(
                      onPressed: peer.canKey
                          ? () => peer.pressKey('down')
                          : null,
                      tooltip: 'Down arrow',
                      icon: const Icon(Icons.arrow_drop_down),
                    ),
                    IconButton(
                      onPressed: peer.canKey
                          ? () => peer.pressKey('right')
                          : null,
                      tooltip: 'Right arrow',
                      icon: const Icon(Icons.arrow_right),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: peer.ready ? () => peer.click('left') : null,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('Left click'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: peer.ready ? () => peer.click('right') : null,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('Right click'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
