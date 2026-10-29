import 'accessibility_restart_prompt.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../design_system.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'desktop_platform.dart';
import 'server_controller.dart';

/// Live prerequisites drive setup; only the final decision is persisted.
class DesktopSetupPage extends StatefulWidget {
  const DesktopSetupPage({
    super.key,
    required this.server,
    required this.platform,
  });
  final ServerController server;
  final DesktopPlatform platform;
  @override
  State<DesktopSetupPage> createState() => _DesktopSetupPageState();
}

class _DesktopSetupPageState extends State<DesktopSetupPage> {
  Timer? _clock;
  bool _busy = false, _clicked = false, _login = false;
  int? _testBaseline;
  DateTime? _lastCodeExpiry;
  String? _error;
  ServerController get server => widget.server;
  DesktopPlatform get platform => widget.platform;

  @override
  void initState() {
    super.initState();
    _login = platform.loginEnabled;
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && server.pairing != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish(bool tested) => _act(() async {
    if (!server.running ||
        !server.inputAvailable ||
        !server.peers.any((p) => p.connected)) {
      throw StateError(
        'Connect your phone and enable desktop control before finishing.',
      );
    }
    if (_login != platform.loginEnabled) {
      await platform.setLogin(_login);
      if (platform.loginEnabled != _login) {
        throw StateError(
          platform.error ?? 'The login preference could not be saved.',
        );
      }
    }
    if (server.pairing != null) await server.command('cancelPairing');
    await server.completeSetup(tested: tested);
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([server, platform]),
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final connected = server.peers.any((p) => p.connected);
      final step =
          !server.running ||
              !server.inputAvailable ||
              platform.launchedFromDiskImage
          ? 0
          : !connected
          ? 1
          : 2;
      if (step != 2) {
        _testBaseline = null;
        _clicked = false;
      } else if (_testBaseline == null || server.inputCount < _testBaseline!) {
        _testBaseline = server.inputCount;
        _clicked = false;
      }
      final busy =
          _busy ||
          server.busy ||
          platform.permissionCheckBusy ||
          platform.restartBusy;
      final verified =
          _clicked && server.inputCount > (_testBaseline ?? server.inputCount);
      final labels = ['Enable control', 'Connect phone', 'Try it'];
      return Scaffold(
        appBar: AppBar(
          title: const LinkpadBrand(label: 'SETUP'),
          actions: [
            TextButton(
              onPressed: busy ? null : () => _act(platform.quit),
              child: const Text('Quit'),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: LinkpadStyle.pagePadding,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your phone. Your computer. Connected.',
                      style: LinkpadStyle.pageTitle,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'A few steps to make your phone a touchpad and keyboard.',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 20,
                      runSpacing: 12,
                      children: [
                        for (var i = 0; i < labels.length; i++)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: i == step
                                    ? colors.primary
                                    : colors.surfaceContainerHighest,
                                foregroundColor: i == step
                                    ? colors.onPrimary
                                    : colors.onSurface,
                                child: i < step
                                    ? const Icon(Icons.check, size: 17)
                                    : Text(
                                        '${i + 1}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                labels[i],
                                style: TextStyle(
                                  fontWeight: i == step
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    if (_error ?? platform.error ?? server.error
                        case final String message) ...[
                      LinkpadNotice(message: message, error: true),
                      const SizedBox(height: 16),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: LinkpadPanel(
                        child: switch (step) {
                          0 => _control(busy),
                          1 => _pair(busy),
                          _ => _test(busy, verified),
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
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

  Widget _heading(IconData icon, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(title, style: LinkpadStyle.sectionTitle),
      ],
    ),
  );

  Widget _control(bool busy) {
    final mac = platform.isMacOS;
    final wayland = !mac && server.inputError.toLowerCase().contains('wayland');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (platform.launchedFromDiskImage) ...[
          _heading(Icons.folder_open, 'Install Linkpad in Applications'),
          const Text(
            'Move Linkpad into Applications. Quit this copy and open the installed app before granting access. Eject the installation disk image if it is mounted.',
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy ? null : () => _act(platform.openApplications),
            child: const Text('Open Applications'),
          ),
        ] else if (!server.running) ...[
          _heading(Icons.computer, 'Start desktop control'),
          Text(
            server.error ??
                'Linkpad is checking its bundled server. If it does not start, try again.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : () => _act(platform.checkInput),
            child: const Text('Try again'),
          ),
        ] else if (mac) ...[
          _heading(Icons.mouse_outlined, 'Let your phone control this Mac'),
          const Text(
            'Accessibility access lets Linkpad move the pointer, click, and type.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Open Privacy & Security → Accessibility, turn on Linkpad (or its linkpad-server helper), then return here. Linkpad will check access automatically.',
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: busy
                    ? null
                    : () => _act(platform.requestInputPermission),
                child: const Text('Open Accessibility settings'),
              ),
              OutlinedButton(
                onPressed: busy ? null : () => _act(platform.checkInput),
                child: const Text('Check again'),
              ),
            ],
          ),
          AccessibilityRestartPrompt(platform: platform, busy: busy),
        ] else ...[
          _heading(
            Icons.desktop_windows_outlined,
            wayland
                ? 'An X11 session is needed'
                : 'Open Linkpad from your desktop session',
          ),
          Text(
            wayland
                ? 'This session uses Wayland. Sign out and choose an X11 or Xorg session at login, if your distribution offers one. Then reopen Linkpad.'
                : 'Linkpad needs access to your logged-in X11 desktop. Open it from the application menu as your regular user.',
          ),
          const SizedBox(height: 14),
          Text(server.inputError),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: busy ? null : () => _act(platform.checkInput),
            child: const Text('Check again'),
          ),
        ],
      ],
    );
  }

  Widget _pair(bool busy) {
    final reconnecting = server.peers.isNotEmpty;
    final invite = server.pairing;
    final expires = DateTime.tryParse(invite?['expiresAt'] as String? ?? '');
    if (expires != null) _lastCodeExpiry = expires;
    final expired =
        _lastCodeExpiry != null && !_lastCodeExpiry!.isAfter(DateTime.now());
    final seconds = expires?.difference(DateTime.now()).inSeconds ?? 0;
    final active = invite != null && seconds > 0;
    final uri = Uri.tryParse(server.address);
    final validAddress =
        uri != null &&
        uri.scheme == 'wss' &&
        uri.host.isNotEmpty &&
        uri.host != '0.0.0.0' &&
        uri.host != '::' &&
        server.addressError.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          Icons.qr_code_scanner,
          reconnecting ? 'Reconnect your phone' : 'Connect your phone',
        ),
        Text(
          reconnecting
              ? 'Your phone is already paired. Open Linkpad on your phone, choose this computer, and tap Connect. You do not need a new code. Keep both devices on the same reachable local network.'
              : 'Open Linkpad on your phone and choose Pair a computer. Both devices need to be on the same reachable local network. Your computer can use Ethernet.',
        ),
        const SizedBox(height: 18),
        if (!validAddress) ...[
          Text(
            server.addressError.isNotEmpty
                ? server.addressError
                : 'No reachable local network address was found. Connect this computer to your network, then try again.',
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: busy ? null : () => _act(server.restart),
            child: const Text('Check network again'),
          ),
        ] else if (active) ...[
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: 220,
              height: 220,
              child: QrImageView(
                data: jsonEncode(invite),
                padding: EdgeInsets.zero,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Expires in ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')} · Single use',
          ),
          const SizedBox(height: 8),
          const Text(
            'Allow Camera to scan the code. When your phone asks, allow Local Network access so it can reach this computer.',
          ),
          ExpansionTile(
            title: const Text('Can’t scan? Enter manually'),
            tilePadding: EdgeInsets.zero,
            children: [
              for (final key in ['address', 'fingerprint', 'secret'])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText('$key: ${invite[key]}'),
                  ),
                ),
            ],
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => _act(() => server.command('cancelPairing')),
            child: const Text('Cancel pairing'),
          ),
        ] else ...[
          if (expired)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'That code has expired. Create a new one to continue.',
              ),
            ),
          FilledButton.icon(
            onPressed: busy ? null : () => _act(() => server.command('pair')),
            icon: const Icon(Icons.qr_code),
            label: Text(
              reconnecting && invite == null
                  ? 'Pair another phone'
                  : invite == null
                  ? 'Create pairing code'
                  : 'Create new code',
            ),
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'Only scan this code with a phone you want to allow to control this computer.',
        ),
      ],
    );
  }

  Widget _test(bool busy, bool verified) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(Icons.touch_app_outlined, 'Try your touchpad'),
      const Text(
        'Move the pointer with your phone, then tap this target. Confirm that you can see and control the pointer.',
      ),
      const SizedBox(height: 18),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => setState(() => _clicked = true),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              verified
                  ? 'Remote input received · Does it feel right?'
                  : 'Click here using your phone',
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Semantics(
        liveRegion: true,
        child: Text(
          server.inputCount > (_testBaseline ?? server.inputCount)
              ? 'Remote input received'
              : 'Waiting for input from your phone',
        ),
      ),
      const SizedBox(height: 16),
      const TextField(
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(labelText: 'Try typing here (optional)'),
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Start Linkpad when I sign in'),
        subtitle: Text(
          platform.trayReady
              ? 'Keep it ready in the menu bar or system tray.'
              : 'Optional. You can change this later.',
        ),
        value: _login,
        onChanged: busy ? null : (value) => setState(() => _login = value),
      ),
      Text(
        platform.trayReady
            ? 'Closing the window keeps Linkpad running. Choose Quit Linkpad in the menu bar or tray to stop it.'
            : 'The system tray is unavailable. Keep this window open or minimized; closing it quits Linkpad.',
      ),
      const SizedBox(height: 20),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton(
            onPressed: busy || !verified ? null : () => _finish(true),
            child: const Text('Yes, it works · Finish'),
          ),
          TextButton(
            onPressed: busy ? null : () => _finish(false),
            child: const Text('Test later'),
          ),
        ],
      ),
    ],
  );
}
