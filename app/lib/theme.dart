import 'package:flutter/material.dart';

import 'package:slugline/typography.dart';

/// Every colour in the application, and the one place they are decided.
///
/// `typography.dart` settled the two type systems; this is the same split for
/// colour. Before it, each widget reached into Material's generated palette for
/// whichever `surfaceContainer*` role sounded closest — and because the palette
/// came from `ColorScheme.fromSeed`, those roles were seven shades of the same
/// near-black. The sidebar, the editor and the top bar all landed within a
/// couple of luminance points of each other, so nothing on screen read as a
/// distinct region.
///
/// The fix is not more shades. It is a small set of *named* ones, each with a
/// job, so that "which grey" stops being a judgement call at the call site:
///
/// * [surface] — the application's background, and the editor's canvas.
/// * [surfaceRaised] — regions that sit on it: the sidebar, the top bar, the
///   status bar.
/// * [surfaceOverlay] — things that float above both: menus, dialogs, the
///   command palette, the find bar, the autocomplete popup.
/// * [border] — the hairline that separates two regions. One pixel, ~10% of
///   the foreground. Regions are told apart by an edge and a surface step, not
///   by a shadow: a drop shadow under a docked panel is a lie about depth, and
///   in a dark theme it is invisible besides.
/// * [textPrimary], [textSecondary], [textTertiary] — the three weights of
///   saying something. Body and titles; labels and metadata; the things that
///   are only there when looked for.
/// * [accent] — the one saturated colour. **One thing at a time**: the selected
///   state, and the primary button in a group. An accent that marks four
///   different things marks nothing.
///
/// The rest of the fields are the specific surfaces this application has that a
/// general token set does not cover — the editor's sheet, the preview's printed
/// paper — and are here rather than at their call sites for the same reason as
/// the others.
///
/// Read them with `context.colours`. They are also mapped onto Material's own
/// [ColorScheme] roles in [sluglineTheme], so every widget this project does not
/// paint itself — dialogs, buttons, text fields, menus, the snackbar — comes out
/// of the same set without being asked.
@immutable
class SluglineColors extends ThemeExtension<SluglineColors> {
  const SluglineColors({
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceOverlay,
    required this.sheet,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.onAccent,
    required this.accentSubtle,
    required this.danger,
    required this.scrim,
    required this.paper,
    required this.onPaper,
    required this.paperEdge,
  });

  /// The application's background, and the editor's canvas.
  final Color surface;

  /// Docked regions: the navigator, the top bar, the status bar.
  final Color surfaceRaised;

  /// Things that float: menus, dialogs, the palette, the find bar, popups.
  final Color surfaceOverlay;

  /// The editor's page-view sheet.
  ///
  /// Not [paper]: the editor is a place to write, not a picture of a printed
  /// page, so its sheet follows the theme — white on a light background, one
  /// step out of the dark on a dark one. [paper] is the other decision and is
  /// deliberately not this one.
  final Color sheet;

  /// The hairline between two regions. Always one physical pixel.
  final Color border;

  /// Body text, titles, the script itself.
  final Color textPrimary;

  /// Labels, metadata, the status line's detail.
  final Color textSecondary;

  /// Present but quiet: shortcut hints, counts, disabled controls.
  final Color textTertiary;

  /// The one saturated colour: selected state and primary buttons, nothing else.
  final Color accent;

  /// Text and icons on top of [accent].
  final Color onAccent;

  /// [accent] at the strength a filled *region* wants rather than a filled
  /// control: a selected row, a highlighted candidate, the editor's selection.
  ///
  /// Translucent on purpose, so that one value works over any of the surfaces
  /// above without a second token per surface.
  final Color accentSubtle;

  /// Errors, refusals and the destructive action in a dialog.
  final Color danger;

  /// What dims the application behind a modal.
  final Color scrim;

  /// The preview's printed page. White in both themes — a preview is a picture
  /// of a sheet of paper, and a dark one would be a picture of something else.
  final Color paper;

  /// Ink on [paper].
  final Color onPaper;

  /// The preview sheet's edge, against whatever it is floating over.
  final Color paperEdge;

  static const SluglineColors dark = SluglineColors(
    surface: Color(0xFF0F1115),
    surfaceRaised: Color(0xFF161920),
    surfaceOverlay: Color(0xFF1D212A),
    // Lifted enough to read as a sheet against `surface`: ~1.7:1 rather than
    // the ~1.3:1 the previous step gave, so pages do not blur together.
    sheet: Color(0xFF1E232E),
    // ~10% white: enough to draw an edge on a near-black, not enough to read as
    // a line in its own right.
    border: Color(0x1AFFFFFF),
    textPrimary: Color(0xFFE6E9EF),
    textSecondary: Color(0xFFA2AAB8),
    // ~4.6:1 on `surfaceRaised`: 11px navigator subtitles and 10px section
    // headers need the full 4.5:1, which the previous tertiary missed.
    textTertiary: Color(0xFF9AA3B2),
    accent: Color(0xFF6F9FD2),
    onAccent: Color(0xFF07121D),
    accentSubtle: Color(0x2E6F9FD2),
    danger: Color(0xFFEF7A76),
    scrim: Color(0x99000000),
    paper: Color(0xFFFFFFFF),
    onPaper: Color(0xFF101010),
    paperEdge: Color(0x33FFFFFF),
  );

  static const SluglineColors light = SluglineColors(
    surface: Color(0xFFF5F5F3),
    surfaceRaised: Color(0xFFEBEBE8),
    surfaceOverlay: Color(0xFFFFFFFF),
    sheet: Color(0xFFFFFFFF),
    // ~12% black. A light theme needs a shade more than a dark one to read as
    // the same hairline.
    border: Color(0x1F000000),
    textPrimary: Color(0xFF1A1C20),
    textSecondary: Color(0xFF53585F),
    textTertiary: Color(0xFF636870),
    accent: Color(0xFF3B6EA5),
    onAccent: Color(0xFFFFFFFF),
    accentSubtle: Color(0x243B6EA5),
    danger: Color(0xFFB3261E),
    scrim: Color(0x66000000),
    paper: Color(0xFFFFFFFF),
    onPaper: Color(0xFF101010),
    paperEdge: Color(0x33000000),
  );

  static SluglineColors forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// The set in force, for the widgets that paint themselves.
  ///
  /// [sluglineTheme] always installs one, so the fallback below is only ever
  /// reached by a widget test that built its own bare `ThemeData` — and a
  /// sensible answer there beats a null assertion in a test that is about
  /// something else entirely.
  static SluglineColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<SluglineColors>() ?? forBrightness(theme.brightness);
  }

  @override
  SluglineColors copyWith({
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceOverlay,
    Color? sheet,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? onAccent,
    Color? accentSubtle,
    Color? danger,
    Color? scrim,
    Color? paper,
    Color? onPaper,
    Color? paperEdge,
  }) => SluglineColors(
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
    sheet: sheet ?? this.sheet,
    border: border ?? this.border,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textTertiary: textTertiary ?? this.textTertiary,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    accentSubtle: accentSubtle ?? this.accentSubtle,
    danger: danger ?? this.danger,
    scrim: scrim ?? this.scrim,
    paper: paper ?? this.paper,
    onPaper: onPaper ?? this.onPaper,
    paperEdge: paperEdge ?? this.paperEdge,
  );

  @override
  SluglineColors lerp(covariant SluglineColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return SluglineColors(
      surface: mix(surface, other.surface),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      surfaceOverlay: mix(surfaceOverlay, other.surfaceOverlay),
      sheet: mix(sheet, other.sheet),
      border: mix(border, other.border),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textTertiary: mix(textTertiary, other.textTertiary),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      accentSubtle: mix(accentSubtle, other.accentSubtle),
      danger: mix(danger, other.danger),
      scrim: mix(scrim, other.scrim),
      paper: mix(paper, other.paper),
      onPaper: mix(onPaper, other.onPaper),
      paperEdge: mix(paperEdge, other.paperEdge),
    );
  }
}

/// `context.colours` — the tokens, at a call site that is already deep in a
/// `build`.
extension SluglineColorsOf on BuildContext {
  SluglineColors get colours => SluglineColors.of(this);
}

/// One physical pixel of [SluglineColors.border]. The separator between two
/// regions, everywhere.
BorderSide hairline(SluglineColors colours) =>
    BorderSide(color: colours.border, width: 1);

/// The application's theme, in one place for both windows.
///
/// The two [MaterialApp]s in `app.dart` — the editor and the storage-unavailable
/// screen — used to spell out four `ThemeData`s between them, which is four
/// chances for the chrome in one window to stop matching the chrome in the
/// other. The type scale in particular has to be one decision: `typography.dart`
/// is where the chrome's sans and its 13-point body are settled, and this is the
/// only thing that applies them.
///
/// The palette is [SluglineColors], written out rather than generated. A seeded
/// `ColorScheme` decides thirty roles from one hue, which is the right trade for
/// an application that wants a colour scheme and the wrong one for an
/// application that wants seven specific greys; the mapping below is that set
/// spread back over Material's roles so the widgets this project does not paint
/// itself land on the same values.
ThemeData sluglineTheme(Brightness brightness) {
  final colours = SluglineColors.forBrightness(brightness);
  final scheme = _schemeFrom(colours, brightness);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final line = hairline(colours);

  return base.copyWith(
    extensions: [colours],
    textTheme: _chromeText(chromeTextTheme(base.textTheme), colours),
    scaffoldBackgroundColor: colours.surface,
    canvasColor: colours.surface,
    dividerColor: colours.border,
    // Read as "the third weight of text", which is what the call sites that
    // reach for it want: a count, a keycap hint, a control that is off.
    disabledColor: colours.textTertiary,
    // A region, so: its own surface, and an edge rather than a shadow. The
    // scrolled-under elevation is off for the same reason — the bar must not
    // change colour when the script moves under it.
    appBarTheme: AppBarTheme(
      backgroundColor: colours.surfaceRaised,
      foregroundColor: colours.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: line),
      titleTextStyle: base.textTheme.titleMedium?.copyWith(
        color: colours.textPrimary,
        fontSize: chromeTitleFontSize,
      ),
      actionsIconTheme: IconThemeData(color: colours.textSecondary, size: 20),
      iconTheme: IconThemeData(color: colours.textSecondary, size: 20),
    ),
    dividerTheme: DividerThemeData(
      color: colours.border,
      thickness: 1,
      space: 1,
    ),
    iconTheme: IconThemeData(color: colours.textSecondary),
    // Overlays: one step further out than a region, a hairline of their own, and
    // no shadow. What separates a menu from what is under it is that it is
    // lighter and has an edge.
    popupMenuTheme: PopupMenuThemeData(
      color: colours.surfaceOverlay,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: line,
      ),
      textStyle: base.textTheme.bodyMedium?.copyWith(
        color: colours.textPrimary,
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colours.surfaceOverlay),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: line,
          ),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colours.surfaceOverlay,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: line,
      ),
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: colours.textPrimary,
      ),
      contentTextStyle: base.textTheme.bodyMedium?.copyWith(
        color: colours.textPrimary,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colours.surfaceOverlay,
        borderRadius: BorderRadius.circular(6),
        border: Border.fromBorderSide(line),
      ),
      textStyle: TextStyle(
        color: colours.textPrimary,
        fontSize: chromeSmallFontSize,
      ),
      waitDuration: const Duration(milliseconds: 500),
    ),
    // No `selectedTileColor`: the two lists that have a selected row paint the
    // fill themselves, and a tile that painted a second one over it would put
    // the accent down twice at twice the strength.
    listTileTheme: ListTileThemeData(
      textColor: colours.textPrimary,
      iconColor: colours.textSecondary,
      selectedColor: colours.accent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderSide: BorderSide(color: colours.border)),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colours.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colours.accent),
      ),
      hintStyle: TextStyle(color: colours.textTertiary),
      labelStyle: TextStyle(color: colours.textSecondary),
      prefixIconColor: colours.textTertiary,
      suffixIconColor: colours.textTertiary,
    ),
    // The accent's other half of its one job. Everything else in a button row
    // stays text-coloured, so that the filled one is the only thing in the
    // dialog wearing the colour.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colours.accent,
        foregroundColor: colours.onAccent,
        disabledBackgroundColor: colours.border,
        disabledForegroundColor: colours.textTertiary,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colours.textPrimary,
        disabledForegroundColor: colours.textTertiary,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colours.textPrimary,
        disabledForegroundColor: colours.textTertiary,
        side: line,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      // A raw ButtonStyle rather than `styleFrom`: `styleFrom` takes a plain
      // `BorderSide` and freezes it across states, while the focus ring below
      // has to exist in exactly one state.
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colours.textTertiary
              : colours.textSecondary,
        ),
        // Keyboard focus gets its own outline rather than sharing hover's
        // colour: a writer tabbing through the chrome with no mouse moving
        // must be able to tell focused from merely hoverable. Hover stays a
        // colour change, decided per button; focus adds the ring.
        side: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? BorderSide(color: colours.accent, width: 1.5)
              : BorderSide.none,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colours.surfaceOverlay,
      contentTextStyle: TextStyle(
        color: colours.textPrimary,
        fontSize: chromeFontSize,
      ),
      actionTextColor: colours.accent,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: line,
      ),
    ),
    // The editor's scrollbar is always visible, so it is a thing on screen the
    // whole time a script is being written: the third weight of text at rest,
    // the second under the pointer. Not the hairline — a scrollbar has to be
    // grabbable, and a border is not something you aim at.
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered)
            ? colours.textSecondary
            : colours.textTertiary,
      ),
    ),
  );
}

/// The chrome's type scale, given the three text weights.
///
/// [chromeTextTheme] owns the sizes; this owns nothing but which of
/// [SluglineColors.textPrimary], [SluglineColors.textSecondary] and
/// [SluglineColors.textTertiary] each style carries, so that the great majority
/// of call sites can go on writing `theme.textTheme.bodySmall` and get the right
/// weight of grey without saying so.
TextTheme _chromeText(TextTheme base, SluglineColors colours) => base
    .apply(bodyColor: colours.textPrimary, displayColor: colours.textPrimary)
    .copyWith(
      // Metadata and captions: the second weight, by default and everywhere.
      bodySmall: base.bodySmall?.copyWith(color: colours.textSecondary),
      labelSmall: base.labelSmall?.copyWith(color: colours.textTertiary),
    );

/// [SluglineColors] spread over Material's roles.
///
/// Every `surfaceContainer*` role collapses onto one of the three surfaces
/// above rather than onto a shade of its own: the roles are a ladder of
/// elevation, this application has three rungs, and a widget that asks for the
/// fourth should get the third rather than a colour nobody chose.
ColorScheme _schemeFrom(SluglineColors colours, Brightness brightness) =>
    ColorScheme(
      brightness: brightness,
      primary: colours.accent,
      onPrimary: colours.onAccent,
      primaryContainer: colours.accentSubtle,
      onPrimaryContainer: colours.textPrimary,
      secondary: colours.accent,
      onSecondary: colours.onAccent,
      secondaryContainer: colours.accentSubtle,
      onSecondaryContainer: colours.textPrimary,
      tertiary: colours.accent,
      onTertiary: colours.onAccent,
      tertiaryContainer: colours.accentSubtle,
      onTertiaryContainer: colours.textPrimary,
      error: colours.danger,
      onError: colours.onAccent,
      errorContainer: colours.danger.withValues(alpha: 0.18),
      onErrorContainer: colours.textPrimary,
      surface: colours.surface,
      onSurface: colours.textPrimary,
      surfaceDim: colours.surface,
      surfaceBright: colours.surfaceOverlay,
      surfaceContainerLowest: colours.surface,
      surfaceContainerLow: colours.surface,
      surfaceContainer: colours.surfaceRaised,
      surfaceContainerHigh: colours.surfaceOverlay,
      surfaceContainerHighest: colours.surfaceOverlay,
      onSurfaceVariant: colours.textSecondary,
      outline: colours.textTertiary,
      outlineVariant: colours.border,
      shadow: const Color(0xFF000000),
      scrim: colours.scrim,
      inverseSurface: colours.textPrimary,
      onInverseSurface: colours.surface,
      inversePrimary: colours.accent,
      // Material's tint-by-elevation is the other way of saying "raised", and
      // this application says it with a surface step and a hairline. Two
      // answers to one question is how the regions stopped being tellable
      // apart in the first place.
      surfaceTint: Colors.transparent,
    );
