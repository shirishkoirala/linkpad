import 'package:flutter/material.dart';
import 'dart:io';
import 'controller_page.dart';
import 'desktop/desktop_page.dart';
import 'desktop/desktop_platform.dart';
import 'desktop/server_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS || Platform.isLinux) {
    final server = ServerController();
    final desktop = DesktopPlatform(server);
    runApp(LinkpadApp(desktopServer: server, desktopPlatform: desktop));
    await desktop.initialize();
    await server.initialize();
  } else {
    runApp(const LinkpadApp());
  }
}

class LinkpadApp extends StatelessWidget {
  const LinkpadApp({super.key, this.desktopServer, this.desktopPlatform});
  final ServerController? desktopServer;
  final DesktopPlatform? desktopPlatform;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Linkpad',
    debugShowCheckedModeBanner: false,
    theme: linkpadTheme(Brightness.light),
    darkTheme: linkpadTheme(Brightness.dark),
    home: desktopServer == null
        ? const ControllerPage()
        : DesktopPage(server: desktopServer!, platform: desktopPlatform),
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
