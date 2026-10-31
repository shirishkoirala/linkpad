// Run from mobile/: flutter test tool/store_screenshots_test.dart --concurrency=1
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkpad_controller/control_deck.dart';
import 'package:linkpad_controller/cursor_settings.dart';
import 'package:linkpad_controller/design_system.dart';
import 'package:linkpad_controller/settings_page.dart';

import '../test/control_deck_test.dart' show FakePeer;

class ScreenshotPeer extends FakePeer {
  @override
  String get desktopName => 'Living room';
  @override
  Duration get roundTripTime => const Duration(milliseconds: 18);
  @override
  bool get canScroll => true;
  @override
  bool get canDrag => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final sdk = Platform.environment['FLUTTER_ROOT'];
    if (sdk == null) throw StateError('Run through flutter test.');
    final fonts = '$sdk/bin/cache/artifacts/material_fonts';
    final loader = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(
        File(
          '$fonts/Roboto-$weight.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        File(
          '$fonts/MaterialIcons-Regular.otf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    await icons.load();
    if (Platform.isMacOS) {
      for (final family in ['.SF Pro Text', '.SF Pro Display']) {
        final font = FontLoader(family)
          ..addFont(
            File(
              '/System/Library/Fonts/SFNS.ttf',
            ).readAsBytes().then(ByteData.sublistView),
          );
        await font.load();
      }
    }
  });

  for (final profile in ['android', 'iOS', 'iPad']) {
    final platform = profile == 'android'
        ? TargetPlatform.android
        : TargetPlatform.iOS;
    for (final screen in ['touchpad', 'remote', 'keyboard', 'settings']) {
      testWidgets('$profile $screen store capture', (tester) async {
        final ios = platform == TargetPlatform.iOS;
        final tablet = profile == 'iPad';
        final ratio = tablet ? 2.0 : 3.0;
        final size = tablet
            ? const Size(1032, 1376)
            : ios
            ? const Size(430, 932)
            : const Size(360, 800);
        tester.view.physicalSize = size * ratio;
        tester.view.devicePixelRatio = ratio;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final peer = ScreenshotPeer();
        final settings = CursorSettings();
        addTearDown(peer.dispose);
        addTearDown(settings.dispose);
        final key = GlobalKey();
        final font = ios && Platform.isMacOS ? '.SF Pro Text' : 'Roboto';
        final theme = linkpadTheme(Brightness.light);
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme.copyWith(
                platform: platform,
                textTheme: theme.textTheme.apply(fontFamily: font),
                primaryTextTheme: theme.primaryTextTheme.apply(
                  fontFamily: font,
                ),
                appBarTheme: theme.appBarTheme.copyWith(
                  titleTextStyle:
                      (theme.appBarTheme.titleTextStyle ??
                              theme.textTheme.titleLarge!)
                          .copyWith(fontFamily: font),
                ),
              ),
              home: screen == 'settings'
                  ? SettingsPage(settings: settings)
                  : ControlDeck(peer: peer, settings: settings),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (screen == 'remote' || screen == 'keyboard') {
          await tester.tap(
            find.text(screen == 'remote' ? 'Remote' : 'Keyboard'),
          );
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: ratio);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final folder = Directory('../assets/release/screenshots/$profile');
          await folder.create(recursive: true);
          await File(
            '${folder.path}/$screen.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      });
    }
  }
}
