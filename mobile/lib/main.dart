import 'dart:convert';
import 'package:flutter/material.dart';
import 'peer_client.dart';
import 'control_deck.dart';
import 'pairing_invitation.dart';
import 'pairing_scanner.dart';

void main() => runApp(const LinkpadApp());

class LinkpadApp extends StatelessWidget {
  const LinkpadApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Linkpad',
    debugShowCheckedModeBanner: false,
    theme: linkpadTheme(Brightness.light),
    darkTheme: linkpadTheme(Brightness.dark),
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
  bool _saved = false;
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
        setState(() => _saved = true);
        await peer.connect(address.text, pin.text, '', _paired);
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
    await peer.connect(address.text, pin.text, token.text, _paired);
  }

  void _paired() {
    token.clear();
    if (mounted) setState(() => _saved = true);
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
        ? ControlDeck(peer: peer)
        : Scaffold(
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    'linkpad',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 44),
                  Text(
                    'PHONE MEETS DESKTOP',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.8,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'A little closer.\nFrom anywhere\nin the room.',
                    style: TextStyle(
                      fontSize: 36,
                      height: 1.12,
                      letterSpacing: -1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Your computer, comfortably in hand.'),
                  const SizedBox(height: 32),
                  if (_saved) ...[
                    const Text(
                      'SAVED COMPUTER',
                      style: TextStyle(fontSize: 11, letterSpacing: 1.8),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.desktop_windows_outlined),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  Uri.tryParse(address.text)?.host ??
                                      'Your computer',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          FilledButton.icon(
                            onPressed: connecting
                                ? null
                                : () {
                                    token.clear();
                                    _connect();
                                  },
                            icon: const Icon(Icons.north_east, size: 18),
                            label: Text(
                              connecting
                                  ? 'Connecting…'
                                  : 'Connect to computer',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (peer.state != PeerState.disconnected)
                    Text(
                      peer.status,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: connecting ? null : _scanPairing,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Pair a computer'),
                  ),
                  const SizedBox(height: 12),
                  ExpansionTile(
                    title: const Text(
                      'Enter pairing details',
                      style: TextStyle(fontSize: 13),
                    ),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.symmetric(vertical: 16),
                    children: [
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
                        child: Text(
                          connecting ? 'Connecting…' : 'Connect / pair',
                        ),
                      ),
                      if (connecting)
                        TextButton(
                          onPressed: peer.disconnect,
                          child: const Text('Cancel'),
                        ),
                    ],
                  ),
                  if (connecting)
                    TextButton(
                      onPressed: peer.disconnect,
                      child: const Text('Cancel connection'),
                    ),
                  const SizedBox(height: 32),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline, size: 13),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Direct connection. No account needed.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
  );
}

ThemeData linkpadTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xff244f39),
        brightness: brightness,
      ).copyWith(
        primary: Color(dark ? 0xffb6df9b : 0xff244f39),
        onPrimary: Color(dark ? 0xff182b1d : 0xffffffff),
        surface: Color(dark ? 0xff111b17 : 0xfff7f8f3),
        onSurface: Color(dark ? 0xffedf5ef : 0xff182822),
        onSurfaceVariant: Color(dark ? 0xffa2b4a7 : 0xff5d6e63),
        surfaceContainerHighest: Color(dark ? 0xff1b2922 : 0xffe9eee5),
        outlineVariant: Color(dark ? 0xff314038 : 0xffd8dfd4),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      scrolledUnderElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 52),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
