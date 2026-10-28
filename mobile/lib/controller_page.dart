import 'package:flutter/material.dart';
import 'design_system.dart';
import 'computer_store.dart';
import 'peer_client.dart';
import 'control_deck.dart';
import 'cursor_settings.dart';
import 'settings_page.dart';
import 'pairing_invitation.dart';
import 'pairing_scanner.dart';
import 'phone_permissions.dart';
import 'screen_awake.dart';
import 'nearby_computers.dart';
import 'server_discovery.dart';

class ControllerPage extends StatefulWidget {
  const ControllerPage({super.key, this.peer, this.nearbyDiscovery});
  final PeerClient? peer;
  final BonjourServerDiscovery? nearbyDiscovery;
  @override
  State<ControllerPage> createState() => _ControllerPageState();
}

class _ControllerPageState extends State<ControllerPage>
    with WidgetsBindingObserver {
  late final PeerClient peer;
  late final ScreenAwakeController _screenAwake;
  final settings = CursorSettings();
  final address = TextEditingController(),
      pin = TextEditingController(),
      token = TextEditingController();
  ComputerStore get computers => peer.computers;
  String? selectedId;
  bool _settingsReady = false;
  bool _requestingPairing = false;
  final _manualDetails = ExpansibleController();

  @override
  void initState() {
    super.initState();
    peer = widget.peer ?? PeerClient();
    WidgetsBinding.instance.addObserver(this);
    peer.setForeground(
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
    _screenAwake = ScreenAwakeController(
      settings: settings,
      peer: peer,
      foreground:
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
    computers.load();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await settings.load();
    if (mounted) setState(() => _settingsReady = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    _screenAwake.setForeground(foreground);
    peer.setForeground(foreground);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _screenAwake.dispose();
    if (widget.peer == null) peer.dispose();
    settings.dispose();
    address.dispose();
    pin.dispose();
    token.dispose();
    _manualDetails.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    FocusScope.of(context).unfocus();
    setState(() => selectedId = pin.text.trim().toLowerCase());
    await peer.connect(address.text, pin.text, token.text, token.clear);
  }

  Future<void> _connectSaved(SavedComputer computer) async {
    address.text = computer.address;
    pin.text = computer.fingerprint;
    token.clear();
    await _connect();
  }

  Future<void> _pair({DiscoveredServer? nearby}) async {
    if (_requestingPairing) return;
    FocusScope.of(context).unfocus();
    peer.disconnect();
    token.clear();
    var requested = false;
    if (nearby != null) {
      setState(() => _requestingPairing = true);
      requested = await peer.requestPairingDisplay(nearby);
      if (!mounted) return;
      setState(() => _requestingPairing = false);
      address.text = nearby.address.toString();
      pin.text = nearby.fingerprint;
    }
    if (computers.computers.isEmpty || nearby != null) {
      final scan = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Connect to a computer'),
          content: Text(
            requested
                ? 'Look for the QR code on your computer and scan it. If it doesn’t appear, open Linkpad and click Create pairing code.'
                : 'Open Linkpad on your computer and create a pairing code. Keep both devices on the same local network.\n\nAllow Camera when you scan. If iPhone asks for Local Network access while connecting, choose Allow.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Enter manually'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Scan code'),
            ),
          ],
        ),
      );
      if (!mounted || scan == null) return;
      if (!scan) {
        _manualDetails.expand();
        return;
      }
    }
    final result = await Navigator.of(
      context,
    ).push<Object>(MaterialPageRoute(builder: (_) => const PairingScanner()));
    if (!mounted) return;
    if (result == PairingScannerAction.enterManually) {
      _manualDetails.expand();
      return;
    }
    if (result is! PairingInvitation) return;
    final invitation = result;
    if (nearby != null && invitation.fingerprint != nearby.fingerprint) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This code belongs to a different computer. Scan the code on the selected computer.',
          ),
        ),
      );
      return;
    }
    address.text = invitation.address;
    pin.text = invitation.fingerprint;
    token.text = invitation.secret;
    await _connect();
  }

  Future<void> _connectionHelp() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Connect to your computer'),
      content: const SingleChildScrollView(
        child: Text(
          'Check that Linkpad is running on the computer and both devices are on the same reachable local network.\n\nOn iPhone, open Settings → Apps → Linkpad and allow Local Network access. A connection timeout can also be caused by the network, a sleeping computer, or a firewall.\n\nIf a pairing code expired, create a new code on the computer.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            final opened = await openPhoneSettings();
            if (!opened && mounted) {
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Text('Open your phone settings and select Linkpad.'),
                ),
              );
            }
          },
          child: const Text('Open Settings'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );

  Future<void> _rename(SavedComputer computer) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(name: computer.name),
    );
    if (!mounted || name == null) return;
    await computers.rename(computer.id, name);
  }

  Future<void> _forget(SavedComputer computer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Forget ${computer.name}?'),
        content: const Text(
          'Removes this saved computer from your phone. This does not revoke access on the computer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    if (peer.activeComputerId == computer.id) peer.disconnect();
    if (pin.text.trim().toLowerCase() == computer.id) {
      address.clear();
      pin.clear();
      token.clear();
    }
    await computers.forget(computer.id);
  }

  String _lastUsed(SavedComputer computer) {
    final used = computer.lastUsed?.toLocal();
    if (used == null) return 'Previously paired';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day),
        day = DateTime(used.year, used.month, used.day);
    if (day == today) return 'Last used today';
    if (day == today.subtract(const Duration(days: 1))) {
      return 'Last used yesterday';
    }
    return 'Last used ${used.day}/${used.month}/${used.year}';
  }

  Widget _computer(SavedComputer computer, ColorScheme colors) {
    final connecting = peer.busy && selectedId == computer.id;
    return LinkpadPanel(
      key: ValueKey(computer.id),
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: LinkpadStyle.controlRadius,
                ),
                child: const Icon(Icons.desktop_windows_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      computer.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LinkpadStyle.cardTitle,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _lastUsed(computer),
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Manage ${computer.name}',
                onSelected: (action) {
                  if (action == 'rename') {
                    _rename(computer);
                  } else {
                    _forget(computer);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'forget', child: Text('Forget')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            Uri.parse(computer.address).host,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: connecting ? null : () => _connectSaved(computer),
            icon: Icon(connecting ? Icons.sync : Icons.north_east, size: 18),
            label: Text(connecting ? 'Connecting…' : 'Connect'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: peer,
    builder: (context, _) {
      if (peer.showControls) {
        if (!_settingsReady) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return ControlDeck(peer: peer, settings: settings);
      }
      final colors = Theme.of(context).colorScheme;
      final saved = computers.computers;
      return Scaffold(
        body: SafeArea(
          child: ListView(
            padding: LinkpadStyle.pagePadding,
            children: [
              Row(
                children: [
                  const Expanded(child: LinkpadBrand()),
                  IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SettingsPage(settings: settings),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                'PHONE MEETS DESKTOP',
                style: LinkpadStyle.eyebrow.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                saved.isEmpty
                    ? 'A little closer.\nFrom anywhere\nin the room.'
                    : 'Your computers.\nOne remote.',
                style: const TextStyle(
                  fontSize: 34,
                  height: 1.12,
                  letterSpacing: -1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                saved.isEmpty
                    ? 'Your computer, comfortably in hand.'
                    : 'Choose a computer to control.',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              if (!computers.loaded) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
                const Text('Loading saved computers…'),
                const SizedBox(height: 20),
              ],
              if (computers.warning != null) ...[
                LinkpadNotice(message: computers.warning!, error: true),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () async {
                      await computers.retryLoad();
                      await computers.retrySave();
                    },
                    child: const Text('Try again'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (saved.isNotEmpty) ...[
                const Text('SAVED COMPUTERS', style: LinkpadStyle.eyebrow),
                const SizedBox(height: 12),
                for (final computer in saved) _computer(computer, colors),
              ],
              if (peer.state != PeerState.disconnected) ...[
                LinkpadNotice(
                  message: peer.status,
                  error: peer.state == PeerState.failed,
                ),
                const SizedBox(height: 12),
              ],
              if (peer.busy)
                TextButton(
                  onPressed: peer.disconnect,
                  child: const Text('Cancel connection'),
                ),
              if (_requestingPairing) const LinearProgressIndicator(),
              NearbyComputers(
                discovery: widget.nearbyDiscovery,
                savedIds: saved.map((c) => c.id).toSet(),
                enabled: !peer.busy && !_requestingPairing,
                onPair: (server) => _pair(nearby: server),
              ),
              OutlinedButton.icon(
                onPressed: peer.busy || _requestingPairing ? null : _pair,
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(
                  saved.isEmpty ? 'Pair a computer' : 'Pair another computer',
                ),
              ),
              const SizedBox(height: 12),
              if (peer.state == PeerState.failed)
                TextButton(
                  onPressed: _connectionHelp,
                  child: const Text('Connection help'),
                ),
              ExpansionTile(
                controller: _manualDetails,
                title: const Text(
                  'Enter pairing details',
                  style: TextStyle(fontSize: 13),
                ),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  TextField(
                    controller: address,
                    autocorrect: false,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Computer address',
                      hintText: 'wss://192.168.1.202:4747/ws',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pin,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Verified computer fingerprint',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: token,
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
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: peer.busy ? null : _connect,
                      child: const Text('Connect / pair'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 13,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Direct connection. No account needed.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.name});
  final String name;
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  bool get validName =>
      name.text.trim().isNotEmpty && name.text.trim().length <= 60;
  late final TextEditingController name = TextEditingController(
    text: widget.name,
  );
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename computer'),
    content: TextField(
      controller: name,
      autofocus: true,
      maxLength: 60,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(
        labelText: 'Computer name',
        errorText: name.text.trim().length > 60 ? 'Use a shorter name.' : null,
      ),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) {
        if (validName) {
          Navigator.pop(context, name.text.trim());
        }
      },
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: validName
            ? () => Navigator.pop(context, name.text.trim())
            : null,
        child: const Text('Save'),
      ),
    ],
  );
}
