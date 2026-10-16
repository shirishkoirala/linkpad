import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'desktop_platform.dart';
import 'server_controller.dart';

class DesktopPage extends StatefulWidget {
  const DesktopPage({super.key, required this.server, this.platform});
  final ServerController server;
  final DesktopPlatform? platform;
  @override
  State<DesktopPage> createState() => _DesktopPageState();
}

class _DesktopPageState extends State<DesktopPage> {
  bool _commandBusy = false;
  String? _actionError;
  ServerController get server => widget.server;

  Future<void> _act(Future<void> Function() action) async {
    if (_commandBusy) return;
    setState(() {
      _commandBusy = true;
      _actionError = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _actionError = e.toString());
    } finally {
      if (mounted) setState(() => _commandBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      server,
      if (widget.platform != null) widget.platform!,
    ]),
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final busy = server.busy || _commandBusy;
      return Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(36, 30, 36, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.touch_app_rounded,
                            color: colors.onPrimary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Text(
                          'Linkpad',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'DESKTOP',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Copy diagnostics',
                          onPressed: () =>
                              _copy(server.diagnostics, 'Diagnostics copied'),
                          icon: const Icon(Icons.bug_report_outlined),
                        ),
                        if (widget.platform != null)
                          PopupMenuButton<String>(
                            tooltip: 'App menu',
                            onSelected: (v) {
                              if (v == 'quit') _act(widget.platform!.quit);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'quit',
                                child: Text('Quit Linkpad'),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 36),
                    Text(
                      server.running
                          ? 'Your phone. Your controls.'
                          : 'A little closer to your computer.',
                      style: const TextStyle(
                        fontSize: 32,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1.1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'A touchpad, keyboard, and remote — right in your hand.',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _status(busy),
                    if (_actionError ?? server.error ?? widget.platform?.error
                        case final String message) ...[
                      const SizedBox(height: 14),
                      _notice(message),
                    ],
                    const SizedBox(height: 22),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final left = _devices(busy);
                        final right = _pairing(busy);
                        if (constraints.maxWidth < 780) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [right, const SizedBox(height: 20), left],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: left),
                            const SizedBox(width: 24),
                            SizedBox(width: 370, child: right),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    _preferences(),
                    const SizedBox(height: 22),
                    Text(
                      'Local connection · Encrypted pairing · No account needed',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _status(bool busy) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: server.running ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  busy
                      ? 'Updating server…'
                      : server.running
                      ? 'Server is running'
                      : 'Server is stopped',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  server.running
                      ? '${server.peers.where((p) => p.connected).length} connected · ${server.inputAvailable ? "Input ready" : "Input needs attention"}'
                      : 'Start the server to connect your phone.',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: busy
                ? null
                : () => _act(server.running ? server.stop : server.start),
            child: Text(server.running ? 'Stop server' : 'Start server'),
          ),
        ],
      ),
    );
  }

  Widget _devices(bool busy) => _panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Your phones',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text('${server.peers.length} paired'),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Only phones you pair can control this computer.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 22),
        if (server.peers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.devices_other_rounded, size: 42),
                const SizedBox(height: 16),
                Text(
                  server.running
                      ? 'Ready for your first phone'
                      : 'Your devices will appear here',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Open Linkpad on your phone and scan a pairing code.',
                  style: TextStyle(height: 1.5),
                ),
              ],
            ),
          ),
        for (final peer in server.peers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                const Icon(Icons.smartphone_rounded, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.nameOf(peer.id),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        peer.connected ? 'Connected' : 'Offline',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  enabled: !busy,
                  tooltip: 'Manage ${server.nameOf(peer.id)}',
                  onSelected: (value) {
                    if (value == 'rename') {
                      _rename(peer);
                    } else {
                      _revoke(peer);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    const PopupMenuItem(
                      value: 'revoke',
                      child: Text('Revoke access'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        const Divider(height: 32),
        const Text(
          'CONNECTION ADDRESS',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SelectableText(
                server.address.isEmpty
                    ? 'Available when the server starts'
                    : server.address,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            IconButton(
              tooltip: 'Copy connection address',
              onPressed: server.address.isEmpty
                  ? null
                  : () => _copy(server.address, 'Address copied'),
              icon: const Icon(Icons.copy_rounded, size: 18),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _pairing(bool busy) {
    final colors = Theme.of(context).colorScheme;
    final invitation = server.pairing;
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Pair a phone',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Keep both devices on the same network.',
            style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 20),
          if (invitation != null) ...[
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: AspectRatio(
                aspectRatio: 1,
                child: QrImageView(
                  data: jsonEncode(invitation),
                  version: QrVersions.auto,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'On your phone: Computers → Pair another computer',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 8),
            Text(
              _expiry(invitation),
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: busy
                  ? null
                  : () => _act(() => server.command('cancelPairing')),
              child: const Text('Cancel pairing'),
            ),
          ] else ...[
            Container(
              height: 164,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Icon(
                  Icons.qr_code_2_rounded,
                  size: 92,
                  color: colors.primary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: !server.running || busy
                  ? null
                  : () => _act(() => server.command('pair')),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create pairing code'),
            ),
            const SizedBox(height: 12),
            Text(
              'A single-use code. Expires in two minutes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
          ],
          if (server.running)
            TextButton(
              onPressed: busy ? null : _customAddress,
              child: const Text('Use a different network address'),
            ),
        ],
      ),
    );
  }

  String _expiry(Map<String, dynamic> invite) {
    final end = DateTime.tryParse(invite['expiresAt'] as String? ?? '');
    if (end == null) return 'Expires in two minutes';
    final seconds = end.difference(DateTime.now()).inSeconds.clamp(0, 120);
    return 'Code expires in ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _preferences() {
    final platform = widget.platform;
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (server.running && !server.inputAvailable) ...[
            const Text(
              'Allow desktop control',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              Platform.isMacOS
                  ? 'Enable Linkpad in System Settings → Privacy & Security → Accessibility. Then restart the server here.'
                  : server.inputError,
              style: const TextStyle(height: 1.5),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (Platform.isMacOS && platform != null)
                  OutlinedButton(
                    onPressed: () => _act(platform.openPermissions),
                    child: const Text('Open Accessibility settings'),
                  ),
                OutlinedButton(
                  onPressed: server.busy ? null : () => _act(server.restart),
                  child: const Text('Restart server'),
                ),
              ],
            ),
            const Divider(height: 32),
          ],
          if (platform != null)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Start at login'),
              subtitle: const Text('Keep Linkpad ready when you sign in.'),
              value: platform.loginEnabled,
              onChanged: platform.loginBusy
                  ? null
                  : (value) => _act(() => platform.setLogin(value)),
            ),
          Text(
            platform?.trayReady == true
                ? 'Closing this window keeps Linkpad running in the tray or menu bar. Use Quit Linkpad to stop it.'
                : 'Use the tray menu or minimize this window to keep the server running. Closing this window quits Linkpad.',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel({required Widget child}) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(22),
    ),
    child: child,
  );
  Widget _notice(String message) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
    ),
  );

  Future<void> _copy(String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<String?> _input(String title, String initial, String label) async {
    return showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(title: title, initial: initial, label: label),
    );
  }

  Future<void> _rename(DesktopPeer peer) async {
    final value = await _input(
      'Rename phone',
      server.nameOf(peer.id),
      'Phone name',
    );
    if (value != null && mounted) {
      await _act(() => server.rename(peer.id, value));
    }
  }

  Future<void> _customAddress() async {
    final value = await _input(
      'Pair using another address',
      server.address,
      'wss://LAN-IP:4747/ws',
    );
    if (value != null && mounted) {
      await _act(() => server.command('pair', address: value));
    }
  }

  Future<void> _revoke(DesktopPeer peer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Revoke ${server.nameOf(peer.id)}?'),
        content: const Text(
          'This phone will disconnect and must scan a new pairing code to control this computer again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke access'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _act(() => server.command('revoke', peer: peer.id));
    }
  }
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.initial,
    required this.label,
  });
  final String title, initial, label;
  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: TextField(
        controller: controller,
        autofocus: true,
        maxLength: widget.label == 'Phone name' ? 60 : 256,
        decoration: InputDecoration(labelText: widget.label),
        onChanged: (_) => setState(() {}),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: controller.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, controller.text.trim()),
        child: const Text('Save'),
      ),
    ],
  );
}
