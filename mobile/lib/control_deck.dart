import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'design_system.dart';
import 'mobile_controls.dart';
import 'peer_client.dart';
import 'relative_touchpad.dart';
import 'cursor_settings.dart';
import 'settings_page.dart';
import 'hold_click_button.dart';
import 'remote_page.dart';

class ControlDeck extends StatefulWidget {
  const ControlDeck({super.key, required this.peer, required this.settings});
  final PeerClient peer;
  final CursorSettings settings;
  @override
  State<ControlDeck> createState() => _ControlDeckState();
}

class _ControlDeckState extends State<ControlDeck> {
  bool keyboard = false, arrows = true, shift = false, symbols = false;
  final modifiers = <String>{};
  bool _remoteOpen = false, _restoringRemote = false;
  PeerClient get peer => widget.peer;
  ColorScheme get colors => Theme.of(context).colorScheme;
  @override
  void initState() {
    super.initState();
    keyboard = widget.settings.lastControlMode == MobileControlMode.keyboard;
    _restoringRemote =
        widget.settings.lastControlMode == MobileControlMode.remote;
    if (_restoringRemote) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _restoringRemote = false);
        _openRemote(restoring: true);
      });
    }
  }

  void _rememberMode(MobileControlMode mode) {
    widget.settings.setLastControlMode(mode);
    widget.settings.save();
  }

  Future<void> _openRemote({bool restoring = false}) async {
    if (_remoteOpen) return;
    _remoteOpen = true;
    peer.cancelDrag();
    if (!restoring) _rememberMode(MobileControlMode.remote);
    final RemoteSelection? selection;
    try {
      selection = await Navigator.of(context).push<RemoteSelection>(
        PageRouteBuilder<RemoteSelection>(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => RemotePage(
            peer: peer,
            settings: widget.settings,
            onSettings: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsPage(settings: widget.settings),
              ),
            ),
          ),
        ),
      );
    } finally {
      _remoteOpen = false;
    }
    if (!mounted) return;
    if (selection == null) {
      // Disconnecting from Remote should preserve it for the next connection.
      // A system Back on an active session returns to the underlying mode.
      if (peer.connected || peer.showControls) {
        _rememberMode(
          keyboard ? MobileControlMode.keyboard : MobileControlMode.touchpad,
        );
      }
      return;
    }
    final selected = selection;
    final next = selected.mode == 'keyboard'
        ? MobileControlMode.keyboard
        : MobileControlMode.touchpad;
    _rememberMode(next);
    setState(() {
      keyboard = next == MobileControlMode.keyboard;
      modifiers
        ..clear()
        ..addAll(
          keyboard ? selected.modifiers.where((m) => m != 'shift') : <String>[],
        );
      shift = keyboard && selected.modifiers.contains('shift');
    });
  }

  void _key(String key) {
    if (peer.keyboardKey(key, modifiers: {...modifiers, if (shift) 'shift'})) {
      setState(() {
        modifiers.clear();
        shift = false;
      });
    }
  }

  void _letter(String letter) {
    if (modifiers.isNotEmpty) {
      _key(letter);
      return;
    }
    if (peer.typeText(shift ? letter.toUpperCase() : letter)) {
      setState(() => shift = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.settings,
    builder: (context, _) => _buildDeck(context),
  );

  Widget _buildDeck(BuildContext context) {
    if (_restoringRemote) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!peer.canKeyboard) {
      modifiers.clear();
      shift = false;
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (keyboard) {
            _selectMode(MobileControlMode.touchpad);
          } else {
            peer.disconnect();
          }
        }
      },
      child: MobileControlScaffold(
        peer: peer,
        mode: keyboard
            ? MobileControlMode.keyboard
            : MobileControlMode.touchpad,
        onModeChanged: _selectMode,
        onBack: peer.disconnect,
        backTooltip: 'Disconnect and return to computers',
        onComputers: peer.disconnect,
        onSettings: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SettingsPage(settings: widget.settings),
          ),
        ),
        bodyBuilder: (context, constraints) {
          final height = math.max(
            constraints.maxHeight,
          keyboard ? 600.0 : 360.0,
          );
          return SingleChildScrollView(
            physics: height > constraints.maxHeight
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            child: SizedBox(
              height: height,
              child: Column(
                children: [
                  MobileControlNotice(peer: peer),
                  Expanded(
                    key: const ValueKey('control-deck-touchpad'),
                    child: Semantics(
                      label:
                          'Touchpad. Drag to move, tap to click, two fingers to scroll or right click.',
                      enabled: peer.ready,
                      child: RawGestureDetector(
                        behavior: HitTestBehavior.opaque,
                        gestures: {
                          EagerGestureRecognizer:
                              GestureRecognizerFactoryWithHandlers<
                                EagerGestureRecognizer
                              >(() => EagerGestureRecognizer(), (_) {}),
                        },
                        child: RelativeTouchpad(
                          enabled: peer.ready,
                          onMove: (dx, dy) => peer.move(
                            dx * widget.settings.sensitivity,
                            dy * widget.settings.sensitivity,
                          ),
                          onClick: peer.click,
                          onScroll: peer.canScroll ? peer.scroll : null,
                          child: MobileControlSurface(
                            child: TouchpadHint(
                              ready: peer.ready,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: HoldClickButton(
                          enabled: peer.ready,
                          supportsDrag: peer.supportsDrag,
                          holding: peer.dragging,
                          onStart: peer.startDrag,
                          onEnd: peer.endDrag,
                          onCancel: peer.cancelDrag,
                          onClick: () => peer.click('left'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _button(
                          'Right click',
                          () => peer.click('right'),
                          enabled: peer.ready,
                        ),
                      ),
                    ],
                  ),
                  if (arrows && !keyboard) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (final item in [
                          (Icons.arrow_back, 'left'),
                          (Icons.arrow_upward, 'up'),
                          (Icons.arrow_downward, 'down'),
                          (Icons.arrow_forward, 'right'),
                        ])
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: IconButton.filledTonal(
                                onPressed: peer.canKey
                                    ? () => peer.pressKey(item.$2)
                                    : null,
                                tooltip: '${item.$2} arrow',
                                icon: Icon(item.$1),
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(44, 50),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (keyboard) ...[
                    const SizedBox(height: 12),
                    if (!peer.supportsKeyboard)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          peer.connected
                              ? 'Update your desktop server to enable the keyboard.'
                              : 'Keyboard paused until the connection returns.',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ),
                    _keyboard(),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _selectMode(MobileControlMode mode) {
    if (mode == MobileControlMode.remote) {
      _openRemote();
      return;
    }
    final next = mode == MobileControlMode.keyboard;
    if (keyboard == next) return;
    peer.cancelDrag();
    _rememberMode(mode);
    setState(() {
      keyboard = next;
      modifiers.clear();
      shift = false;
    });
  }

  Widget _button(
    String label,
    VoidCallback action, {
    bool enabled = true,
    bool selected = false,
  }) => FilledButton.tonal(
    onPressed: enabled ? action : null,
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      backgroundColor: selected
          ? colors.primary
          : colors.surfaceContainerHighest,
      foregroundColor: selected ? colors.onPrimary : colors.onSurface,
      shape: RoundedRectangleBorder(borderRadius: LinkpadStyle.keyRadius),
    ),
    child: Text(label, maxLines: 1, style: const TextStyle(fontSize: 13)),
  );
  Widget _keyboard() {
    final rows = symbols
        ? ['1234567890', '@#\$%&*()-', '!?/:;.,']
        : ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
    Widget key(
      String label,
      VoidCallback action, {
      bool selected = false,
      int flex = 1,
    }) => Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Semantics(
          toggled: selected,
          child: _button(
            label,
            action,
            enabled: peer.canKeyboard,
            selected: selected,
          ),
        ),
      ),
    );
    return Column(
      children: [
        Row(
          children: [
            key('Esc', () => _key('escape')),
            key('Tab', () => _key('tab')),
            for (final mod in ['ctrl', 'alt', 'super'])
              key(
                mod == 'super'
                    ? 'Win / Cmd'
                    : mod == 'ctrl'
                    ? 'Ctrl'
                    : 'Alt',
                () => setState(() {
                  modifiers.contains(mod)
                      ? modifiers.remove(mod)
                      : modifiers.add(mod);
                }),
                selected: modifiers.contains(mod),
              ),
          ],
        ),
        for (var i = 0; i < rows.length; i++)
          Row(
            children: [
              if (i == 2)
                key('⇧', () => setState(() => shift = !shift), selected: shift),
              for (final char in rows[i].split(''))
                key(shift ? char.toUpperCase() : char, () => _letter(char)),
              if (i == 2)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: IconButton.filledTonal(
                      onPressed: peer.canKeyboard
                          ? () => _key('backspace')
                          : null,
                      tooltip: 'Backspace',
                      icon: const Icon(Icons.backspace_outlined, size: 17),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: LinkpadStyle.keyRadius,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        Row(
          children: [
            key(
              symbols ? 'ABC' : '123',
              () => setState(() => symbols = !symbols),
            ),
            key('space', () => _key('space'), flex: 4),
            key('return', () => _key('enter'), flex: 2),
          ],
        ),
      ],
    );
  }
}
