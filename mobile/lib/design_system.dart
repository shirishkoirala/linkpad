import 'package:flutter/material.dart';

/// Shared visual roles for the controller, desktop, settings, and setup flows.
abstract final class LinkpadStyle {
  static const pagePadding = EdgeInsets.all(24);
  static const panelPadding = EdgeInsets.all(24);
  static const panelRadius = BorderRadius.all(Radius.circular(22));
  static const controlRadius = BorderRadius.all(Radius.circular(14));
  static const keyRadius = BorderRadius.all(Radius.circular(12));
  static const touchpadRadius = BorderRadius.all(Radius.circular(24));
  static const pageTitle = TextStyle(
    fontSize: 32,
    height: 1.15,
    fontWeight: FontWeight.w600,
    letterSpacing: -1,
  );
  static const sectionTitle = TextStyle(
    fontSize: 22,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -.3,
  );
  static const cardTitle = TextStyle(
    fontSize: 17,
    height: 1.35,
    fontWeight: FontWeight.w600,
  );
  static const body = TextStyle(fontSize: 14, height: 1.5);
  static const caption = TextStyle(fontSize: 12, height: 1.5);
  static const eyebrow = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.6,
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
        surfaceContainerLowest: Color(dark ? 0xff16221c : 0xffffffff),
        surfaceContainerLow: Color(dark ? 0xff17251e : 0xfff0f3ec),
        surfaceContainerHighest: Color(dark ? 0xff1b2922 : 0xffe9eee5),
        outlineVariant: Color(dark ? 0xff314038 : 0xffd8dfd4),
      );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final shape = RoundedRectangleBorder(
    borderRadius: LinkpadStyle.controlRadius,
  );
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: base.textTheme
        .copyWith(
          headlineLarge: LinkpadStyle.pageTitle,
          headlineMedium: LinkpadStyle.pageTitle.copyWith(fontSize: 28),
          titleLarge: LinkpadStyle.sectionTitle,
          titleMedium: LinkpadStyle.cardTitle,
          titleSmall: LinkpadStyle.cardTitle.copyWith(fontSize: 15),
          bodyLarge: LinkpadStyle.body.copyWith(fontSize: 15),
          bodyMedium: LinkpadStyle.body,
          bodySmall: LinkpadStyle.caption,
          labelLarge: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          labelSmall: LinkpadStyle.eyebrow,
        )
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      scrolledUnderElevation: 0,
      titleTextStyle: LinkpadStyle.cardTitle.copyWith(color: scheme.onSurface),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        side: BorderSide(color: scheme.outlineVariant),
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: shape,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: shape,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(borderRadius: LinkpadStyle.controlRadius),
      enabledBorder: OutlineInputBorder(
        borderRadius: LinkpadStyle.controlRadius,
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: LinkpadStyle.panelRadius,
      ),
      titleTextStyle: LinkpadStyle.sectionTitle.copyWith(
        color: scheme.onSurface,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
  );
}

class LinkpadPanel extends StatelessWidget {
  const LinkpadPanel({
    super.key,
    required this.child,
    this.padding = LinkpadStyle.panelPadding,
    this.margin = EdgeInsets.zero,
  });
  final Widget child;
  final EdgeInsetsGeometry padding, margin;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: margin,
      child: Material(
        color: colors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: LinkpadStyle.panelRadius,
          side: BorderSide(color: colors.outlineVariant),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class LinkpadBrand extends StatelessWidget {
  const LinkpadBrand({super.key, this.label});
  final String? label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: LinkpadStyle.keyRadius,
        child: Image.asset(
          'assets/branding/linkpad-icon-source.png',
          width: 40,
          height: 40,
        ),
      ),
      const SizedBox(width: 12),
      Text(
        'Linkpad',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: -.8,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      if (label != null) ...[
        const SizedBox(width: 12),
        Text(
          label!,
          style: LinkpadStyle.eyebrow.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ],
  );
}

class LinkpadNotice extends StatelessWidget {
  const LinkpadNotice({super.key, required this.message, this.error = false});
  final String message;
  final bool error;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = error ? colors.onErrorContainer : colors.onSurface;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: error ? colors.errorContainer : colors.surfaceContainerHighest,
        borderRadius: LinkpadStyle.controlRadius,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                error ? Icons.error_outline : Icons.info_outline,
                size: 20,
                color: foreground,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: LinkpadStyle.body.copyWith(color: foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
