import 'package:flutter/material.dart';
import 'design_system.dart';
import 'peer_client.dart';
import 'control_mode.dart';
export 'control_mode.dart';

/// Shared chrome keeps navigation in the same place across all control modes.
class MobileControlScaffold extends StatelessWidget {
  const MobileControlScaffold({
    super.key,
    required this.peer,
    required this.mode,
    required this.onModeChanged,
    required this.onComputers,
    required this.onSettings,
    required this.bodyBuilder,
  });
  final PeerClient peer;
  final MobileControlMode mode;
  final ValueChanged<MobileControlMode> onModeChanged;
  final VoidCallback onComputers, onSettings;
  final Widget Function(BuildContext, BoxConstraints) bodyBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: onComputers,
                    tooltip: 'Computers',
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          peer.desktopName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LinkpadStyle.cardTitle,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          peer.connectionSummary,
                          maxLines: 2,
                          style: LinkpadStyle.caption.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: peer.connectionDetails,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        peer.connected ? Icons.wifi : Icons.wifi_off,
                        size: 20,
                        color: colors.primary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => showControlGestures(context),
                    tooltip: 'Gestures',
                    icon: const Icon(Icons.help_outline),
                  ),
                  IconButton(
                    onPressed: onSettings,
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(child: LayoutBuilder(builder: bodyBuilder)),
              const SizedBox(height: 12),
              Divider(height: 1, color: colors.outlineVariant),
              const SizedBox(height: 6),
              Row(
                children: [
                  _destination(
                    context,
                    Icons.mouse_outlined,
                    'Touchpad',
                    mode == MobileControlMode.touchpad,
                    () => onModeChanged(MobileControlMode.touchpad),
                  ),
                  _destination(
                    context,
                    Icons.gamepad_outlined,
                    'Remote',
                    mode == MobileControlMode.remote,
                    () => onModeChanged(MobileControlMode.remote),
                  ),
                  _destination(
                    context,
                    Icons.keyboard_outlined,
                    'Keyboard',
                    mode == MobileControlMode.keyboard,
                    () => onModeChanged(MobileControlMode.keyboard),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _destination(
    BuildContext context,
    IconData icon,
    String label,
    bool selected,
    VoidCallback action,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Semantics(
        selected: selected,
        child: TextButton(
          onPressed: action,
          style: TextButton.styleFrom(
            foregroundColor: selected
                ? colors.primary
                : colors.onSurfaceVariant,
            backgroundColor: selected ? colors.surfaceContainerHighest : null,
            padding: const EdgeInsets.symmetric(vertical: 8),
            shape: const RoundedRectangleBorder(
              borderRadius: LinkpadStyle.keyRadius,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 21),
              const SizedBox(height: 5),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

class MobileControlNotice extends StatelessWidget {
  const MobileControlNotice({
    super.key,
    required this.peer,
    this.keyboardRequired = false,
  });
  final PeerClient peer;
  final bool keyboardRequired;
  @override
  Widget build(BuildContext context) {
    final inputReady = keyboardRequired
        ? peer.canKeyboard || peer.canKey
        : peer.ready;
    final message =
        peer.storageWarning ??
        (peer.waitingForResponse
            ? 'Connection is slow. Waiting for your computer to respond…'
            : !peer.connected
            ? 'Controls paused while we reconnect.'
            : !inputReady
            ? 'Desktop input unavailable. Check the desktop server permissions.'
            : keyboardRequired && !peer.supportsKeyboard
            ? 'Update your desktop server to enable Enter and shortcuts.'
            : null);
    return message == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: LinkpadNotice(message: message),
          );
  }
}

/// The touchpad and D-pad share one input-workspace treatment.
class TouchpadHint extends StatelessWidget {
  const TouchpadHint({super.key, required this.ready, this.showDetails = true});
  final bool ready, showDetails;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        color: colors.surface,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDetails) ...[
              Icon(Icons.fingerprint, size: 32, color: colors.primary),
              const SizedBox(height: 14),
            ],
            Text(
              ready ? 'Room to move.' : 'Waiting for computer…',
              style: const TextStyle(fontSize: 16),
            ),
            if (showDetails) ...[
              const SizedBox(height: 10),
              Text(
                'One finger moves · Tap to click\nTwo fingers scroll · Tap for right click',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.8,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MobileControlSurface extends StatelessWidget {
  const MobileControlSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: LinkpadStyle.touchpadRadius,
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: CustomPaint(
        painter: _ControlDots(colors.outlineVariant),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _ControlDots extends CustomPainter {
  _ControlDots(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double x = 12; x < size.width; x += 18) {
      for (double y = 12; y < size.height; y += 18) {
        canvas.drawCircle(Offset(x, y), .8, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_ControlDots oldDelegate) => oldDelegate.color != color;
}

Future<void> showControlGestures(
  BuildContext context,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (context) => const SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Make yourself comfortable.', style: LinkpadStyle.sectionTitle),
          SizedBox(height: 20),
          ListTile(
            leading: Icon(Icons.swipe),
            title: Text('One finger moves the pointer'),
          ),
          ListTile(
            leading: Icon(Icons.touch_app),
            title: Text('Tap to left click'),
          ),
          ListTile(
            leading: Icon(Icons.pan_tool_alt),
            title: Text('Two fingers scroll'),
          ),
          ListTile(
            leading: Icon(Icons.mouse_outlined),
            title: Text('Two-finger tap to right click'),
          ),
          ListTile(
            leading: Icon(Icons.open_with),
            title: Text('Hold Left click and move on the touchpad to drag'),
            subtitle: Text(
              'Release Left click to drop. Requires an updated desktop server.',
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Modifiers apply to the next key only. Super is Command on Mac and the Windows key on Linux.',
          ),
        ],
      ),
    ),
  ),
);
