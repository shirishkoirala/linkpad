import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'cursor_settings.dart';
import 'design_system.dart';
import 'mobile_controls.dart';
import 'peer_client.dart';
import 'relative_touchpad.dart';

typedef RemoteSelection = ({String mode, Set<String> modifiers});

class RemotePage extends StatefulWidget {
  const RemotePage({
    super.key,
    required this.peer,
    required this.onSettings,
    this.settings,
  });
  final PeerClient peer;
  final VoidCallback onSettings;
  final CursorSettings? settings;
  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> {
  final modifiers = <String>{};
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
        modifiers.clear();
      });
    }
  }

  void _switchMode(String mode) =>
      Navigator.pop(context, (mode: mode, modifiers: {...modifiers}));

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([peer, widget.settings]),
    builder: (context, _) {
      if (!peer.canKeyboard) modifiers.clear();
      final colors = Theme.of(context).colorScheme;
      return MobileControlScaffold(
        peer: peer,
        mode: MobileControlMode.remote,
        onModeChanged: (mode) {
          if (mode != MobileControlMode.remote) _switchMode(mode.name);
        },
        onComputers: () {
          peer.disconnect();
          Navigator.pop(context);
        },
        onSettings: widget.onSettings,
        bodyBuilder: (context, constraints) => Column(
          children: [
            MobileControlNotice(peer: peer, keyboardRequired: true),
            Expanded(
              child: LayoutBuilder(
                builder: (context, space) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: space.maxHeight),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _touchpad(colors),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: _modifiers(colors),
                          ),
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (context, size) =>
                                _directionPad(size.maxWidth),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _shortcuts(),
          ],
        ),
      );
    },
  );

  Widget _touchpad(ColorScheme colors) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 192),
    child: Semantics(
      label:
          'Remote touchpad. Drag to move, tap to click, two fingers to scroll or right click.',
      enabled: peer.ready,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          EagerGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                () => EagerGestureRecognizer(),
                (_) {},
              ),
        },
        child: RelativeTouchpad(
          key: const ValueKey('remote-touchpad'),
          enabled: peer.ready,
          onMove: (dx, dy) {
            final sensitivity = widget.settings?.sensitivity ?? 1;
            peer.move(dx * sensitivity, dy * sensitivity);
          },
          onClick: peer.click,
          onScroll: peer.canScroll ? peer.scroll : null,
          child: MobileControlSurface(child: TouchpadHint(ready: peer.ready)),
        ),
      ),
    ),
  );

  Widget _modifiers(ColorScheme colors) => Row(
    children: [
      for (final mod in ['ctrl', 'alt', 'shift', 'super'])
        Expanded(
          flex: mod == 'super' ? 2 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: FilledButton.tonal(
              onPressed: peer.canKeyboard
                  ? () => setState(() {
                      modifiers.contains(mod)
                          ? modifiers.remove(mod)
                          : modifiers.add(mod);
                    })
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                foregroundColor: modifiers.contains(mod)
                    ? colors.onPrimary
                    : colors.onSurface,
                backgroundColor: modifiers.contains(mod)
                    ? colors.primary
                    : colors.surfaceContainerHighest,
                shape: const RoundedRectangleBorder(
                  borderRadius: LinkpadStyle.keyRadius,
                ),
              ),
              child: Semantics(
                toggled: modifiers.contains(mod),
                child: Text(
                  mod == 'super' ? 'Win / Cmd' : labels[mod]!,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _shortcuts() => Row(
    children: [
      for (final shortcut in [
        (Icons.first_page, 'Previous', 'tab'),
        (Icons.space_bar, 'Space', 'space'),
        (Icons.last_page, 'Next', 'tab'),
      ])
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilledButton.tonal(
              onPressed: peer.canKeyboard
                  ? () => _send(
                      shortcut.$3,
                      extra: shortcut.$2 == 'Previous' ? {'shift'} : {},
                    )
                  : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: const RoundedRectangleBorder(
                  borderRadius: LinkpadStyle.keyRadius,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(shortcut.$1, size: 21),
                  const SizedBox(height: 7),
                  Text(shortcut.$2, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
    ],
  );

  Widget _directionPad(double width) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: (width - 102).clamp(178.0, 260.0),
      child: LayoutBuilder(
        builder: (context, space) {
          final diameter = math
              .min(space.maxWidth - 102, space.maxHeight)
              .clamp(140.0, 260.0);
          Widget side(String label, String key, IconData? icon) => _RemoteKey(
            label: label,
            icon: icon,
            enabled: peer.canKeyboard,
            onPressed: () => _send(key),
            repeat: true,
          );
          Widget arrow(IconData icon, String key) => _RemoteKey(
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
                    side('Backspace', 'backspace', Icons.backspace_outlined),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Semantics(
                label: 'D-pad. Arrow keys with Enter in the center.',
                child: SizedBox(
                  width: diameter,
                  height: diameter,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.outlineVariant),
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
                            child: arrow(Icons.keyboard_arrow_up, 'up'),
                          ),
                        ),
                        Positioned(
                          bottom: 4,
                          left: diameter / 2 - 24,
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: arrow(Icons.keyboard_arrow_down, 'down'),
                          ),
                        ),
                        Positioned(
                          left: 4,
                          top: diameter / 2 - 24,
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: arrow(Icons.keyboard_arrow_left, 'left'),
                          ),
                        ),
                        Positioned(
                          right: 4,
                          top: diameter / 2 - 24,
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: arrow(Icons.keyboard_arrow_right, 'right'),
                          ),
                        ),
                        SizedBox(
                          width: math.max(72.0, diameter * .36),
                          height: math.max(72.0, diameter * .36),
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
                                Icon(Icons.keyboard_return, size: 19),
                                SizedBox(height: 4),
                                Text('Enter', style: TextStyle(fontSize: 14)),
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
                    side('Page up', 'pageup', Icons.keyboard_double_arrow_up),
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
    );
  }
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
          shape: RoundedRectangleBorder(borderRadius: LinkpadStyle.keyRadius),
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
