import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'peer_client.dart';

typedef RemoteSelection = ({String mode, Set<String> modifiers});

class RemotePage extends StatefulWidget {
  const RemotePage({super.key, required this.peer, required this.onSettings});
  final PeerClient peer;
  final VoidCallback onSettings;
  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> {
  final modifiers = <String>{};
  String? lastKey;
  PeerClient get peer => widget.peer;
  bool get arrowsEnabled => peer.canKey || peer.canKeyboard;
  static const labels = {
    'ctrl': 'Ctrl',
    'alt': 'Alt',
    'shift': 'Shift',
    'super': 'Win / Command',
  };

  void _send(String key, {Set<String> extra = const {}}) {
    final mods = {...modifiers, ...extra};
    bool sent;
    if (peer.canKeyboard) {
      sent = peer.keyboardKey(key, modifiers: mods);
    } else if (peer.canKey &&
        mods.isEmpty &&
        {'left', 'right', 'up', 'down'}.contains(key)) {
      peer.pressKey(key);
      sent = true;
    } else {
      return;
    }
    if (sent) {
      setState(() {
        lastKey = [
          ...mods.map((m) => labels[m]!),
          switch (key) {
            'enter' => 'Enter / Return',
            'escape' => 'Esc',
            'pageup' => 'Page up',
            'pagedown' => 'Page down',
            _ => key[0].toUpperCase() + key.substring(1),
          },
        ].join(' + ');
        modifiers.clear();
      });
    }
  }

  void _switchMode(String mode) =>
      Navigator.pop(context, (mode: mode, modifiers: {...modifiers}));

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: peer,
    builder: (context, _) {
      if (!peer.canKeyboard) modifiers.clear();
      final colors = Theme.of(context).colorScheme;
      return Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Back to touchpad',
                            onPressed: () => _switchMode('touchpad'),
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
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  peer.status,
                                  maxLines: 2,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Settings',
                            onPressed: widget.onSettings,
                            icon: const Icon(Icons.settings_outlined),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Find your way.',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'A familiar remote for your computer.',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          style: SegmentedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            textStyle: Theme.of(context).textTheme.labelMedium,
                          ),
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: 'touchpad',
                              label: Text('Touchpad'),
                              icon: Icon(Icons.mouse_outlined, size: 16),
                            ),
                            ButtonSegment(
                              value: 'remote',
                              label: Text('Remote'),
                              icon: Icon(Icons.gamepad_outlined, size: 16),
                            ),
                            ButtonSegment(
                              value: 'keyboard',
                              label: Text('Keyboard'),
                              icon: Icon(Icons.keyboard_outlined, size: 16),
                            ),
                          ],
                          selected: const {'remote'},
                          onSelectionChanged: (value) {
                            if (value.single != 'remote') {
                              _switchMode(value.single);
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          for (final mod in ['ctrl', 'alt', 'shift', 'super'])
                            Expanded(
                              flex: mod == 'super' ? 2 : 1,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                child: TextButton(
                                  onPressed: peer.canKeyboard
                                      ? () => setState(() {
                                          modifiers.contains(mod)
                                              ? modifiers.remove(mod)
                                              : modifiers.add(mod);
                                        })
                                      : null,
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(0, 44),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                    ),
                                    foregroundColor: modifiers.contains(mod)
                                        ? colors.onPrimary
                                        : colors.onSurface,
                                    backgroundColor: modifiers.contains(mod)
                                        ? colors.primary
                                        : colors.surfaceContainerHighest,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Semantics(
                                    toggled: modifiers.contains(mod),
                                    child: Text(
                                      mod == 'super'
                                          ? 'Win / Cmd'
                                          : labels[mod]!,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        modifiers.isEmpty
                            ? 'Windows key on Linux · Command on Mac'
                            : 'Applies to the next key · Tap again to cancel',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (!peer.supportsKeyboard)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            peer.connected
                                ? 'Update the desktop server to enable Enter and shortcuts.'
                                : 'Controls paused while reconnecting.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: (constraints.maxWidth - 142).clamp(
                          178.0,
                          260.0,
                        ),
                        child: LayoutBuilder(
                          builder: (context, space) {
                            final diameter = math
                                .min(space.maxWidth - 102, space.maxHeight)
                                .clamp(140.0, 260.0);
                            Widget side(
                              String label,
                              String key,
                              IconData? icon,
                            ) => _RemoteKey(
                              label: label,
                              icon: icon,
                              enabled: peer.canKeyboard,
                              onPressed: () => _send(key),
                              repeat: true,
                            );
                            Widget arrow(IconData icon, String key) =>
                                _RemoteKey(
                                  label: 'Arrow $key',
                                  icon: icon,
                                  enabled: arrowsEnabled,
                                  onPressed: () => _send(key),
                                  repeat: true,
                                  transparent: true,
                                );
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 44,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      side('Esc', 'escape', null),
                                      const SizedBox(height: 10),
                                      side(
                                        'Backspace',
                                        'backspace',
                                        Icons.backspace_outlined,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Semantics(
                                  label:
                                      'D-pad. Arrow keys with Enter in the center.',
                                  child: SizedBox(
                                    width: diameter,
                                    height: diameter,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: colors.surfaceContainerHighest,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: colors.outlineVariant,
                                        ),
                                      ),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Positioned(
                                            top: 4,
                                            left: diameter / 2 - 24,
                                            child: SizedBox(
                                              width: 48,
                                              height: 48,
                                              child: arrow(
                                                Icons.keyboard_arrow_up,
                                                'up',
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            bottom: 4,
                                            left: diameter / 2 - 24,
                                            child: SizedBox(
                                              width: 48,
                                              height: 48,
                                              child: arrow(
                                                Icons.keyboard_arrow_down,
                                                'down',
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            left: 4,
                                            top: diameter / 2 - 24,
                                            child: SizedBox(
                                              width: 48,
                                              height: 48,
                                              child: arrow(
                                                Icons.keyboard_arrow_left,
                                                'left',
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            right: 4,
                                            top: diameter / 2 - 24,
                                            child: SizedBox(
                                              width: 48,
                                              height: 48,
                                              child: arrow(
                                                Icons.keyboard_arrow_right,
                                                'right',
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: diameter * .36,
                                            height: diameter * .36,
                                            child: FilledButton(
                                              onPressed: peer.canKeyboard
                                                  ? () => _send('enter')
                                                  : null,
                                              style: FilledButton.styleFrom(
                                                padding: EdgeInsets.zero,
                                                shape: const CircleBorder(),
                                              ),
                                              child: const Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.keyboard_return,
                                                    size: 19,
                                                  ),
                                                  SizedBox(height: 4),
                                                  Text(
                                                    'Enter',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 7),
                                SizedBox(
                                  width: 44,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      side(
                                        'Page up',
                                        'pageup',
                                        Icons.keyboard_double_arrow_up,
                                      ),
                                      const SizedBox(height: 10),
                                      side(
                                        'Page down',
                                        'pagedown',
                                        Icons.keyboard_double_arrow_down,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          lastKey ?? 'Arrows navigate. Center confirms.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          for (final shortcut in [
                            (Icons.first_page, 'Previous', 'tab'),
                            (Icons.space_bar, 'Space', 'space'),
                            (Icons.last_page, 'Next', 'tab'),
                          ])
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: FilledButton.tonal(
                                  onPressed: peer.canKeyboard
                                      ? () => _send(
                                          shortcut.$3,
                                          extra: shortcut.$2 == 'Previous'
                                              ? {'shift'}
                                              : {},
                                        )
                                      : null,
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(shortcut.$1, size: 21),
                                      const SizedBox(height: 7),
                                      Text(
                                        shortcut.$2,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Hold an arrow to keep moving.\nTap Enter to open, confirm or select.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.6,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Divider(height: 1, color: colors.outlineVariant),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton.icon(
                              onPressed: () {
                                peer.disconnect();
                                Navigator.pop(context);
                              },
                              icon: const Icon(
                                Icons.desktop_windows_outlined,
                                size: 18,
                              ),
                              label: const Text(
                                'Computers',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                          Expanded(
                            child: TextButton.icon(
                              onPressed: () => _switchMode('touchpad'),
                              icon: const Icon(Icons.mouse_outlined, size: 18),
                              label: const Text(
                                'Touchpad',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                          Expanded(
                            child: TextButton.icon(
                              onPressed: widget.onSettings,
                              icon: const Icon(
                                Icons.settings_outlined,
                                size: 18,
                              ),
                              label: const Text(
                                'Settings',
                                style: TextStyle(fontSize: 11),
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
          ),
        ),
      );
    },
  );
}

class _RemoteKey extends StatefulWidget {
  const _RemoteKey({
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.icon,
    this.repeat = false,
    this.transparent = false,
  });
  final String label;
  final bool enabled, repeat, transparent;
  final VoidCallback onPressed;
  final IconData? icon;
  @override
  State<_RemoteKey> createState() => _RemoteKeyState();
}

class _RemoteKeyState extends State<_RemoteKey> {
  Timer? timer;
  void stop() {
    timer?.cancel();
    timer = null;
  }

  @override
  void didUpdateWidget(_RemoteKey old) {
    super.didUpdateWidget(old);
    if (!widget.enabled) stop();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onLongPressStart: widget.enabled && widget.repeat
          ? (_) {
              widget.onPressed();
              timer = Timer.periodic(const Duration(milliseconds: 110), (_) {
                if (widget.enabled) {
                  widget.onPressed();
                } else {
                  stop();
                }
              });
            }
          : null,
      onLongPressEnd: (_) => stop(),
      onLongPressCancel: stop,
      child: TextButton(
        onPressed: widget.enabled ? widget.onPressed : null,
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 48),
          padding: EdgeInsets.zero,
          backgroundColor: widget.transparent
              ? Colors.transparent
              : colors.surfaceContainerHighest,
          foregroundColor: colors.onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
        child: widget.icon == null
            ? Text(widget.label, style: const TextStyle(fontSize: 12))
            : Semantics(
                label: widget.label,
                child: Icon(widget.icon, size: 23),
              ),
      ),
    );
  }
}
