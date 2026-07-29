import 'package:flutter/material.dart';

/// The two type systems, and the line between them.
///
/// A screenwriting app has two kinds of text in it and they are not the same
/// kind of thing. The **script** is typewriter output: a fixed monospace grid
/// (§5.1) where the face and its advance are part of the format, and where what
/// is on screen has to be what comes out of the printer. The **chrome** — menus,
/// dialogs, status lines, the navigator — is an application talking about the
/// script, and it belongs in the sans the rest of the desktop is set in.
///
/// The two used to be mixed: chrome borrowed the script's monospace for paths
/// and keycaps, and the script borrowed the system's monospace because nothing
/// was bundled. Each direction costs something. This file is the split.
///
/// **Script:** [scriptFontFamily], sized by [ScreenplayMetrics] so that sixty
/// characters span the six-inch measure exactly. Never a fixed pixel size.
///
/// **Chrome:** the platform sans at [chromeFontSize], through
/// [chromeTextTheme]. Never Courier, and never sized off the script's grid.

/// The face the script is set in, on screen and on paper alike.
///
/// Bundled from `crates/render_pdf/fonts/` rather than resolved from the system
/// (see `pubspec.yaml`): a fallback face has different advances and a different
/// colour, so "what you see" would only approximately be "what you get". The
/// weights and styles declared there are what `fontWeight` and `fontStyle` pick
/// between — emphasis in the editor is the same emphasis the PDF prints.
const String scriptFontFamily = 'Courier Prime';

/// The size the chrome is set at.
///
/// One size for body text and controls, a step down for secondary labels, a
/// step up for the few things that are genuinely headings. Material's own scale
/// runs larger than a desktop editor wants — its 16 px body and 22 px titles are
/// a phone's — and next to a script column that is deliberately small, chrome at
/// those sizes reads as the loudest thing on screen.
const double chromeFontSize = 13;

/// Secondary chrome: captions, hints, the status line's detail.
const double chromeSmallFontSize = 12;

/// Chrome that has to be read before the thing beside it: a dialog's title, a
/// section heading in preferences.
const double chromeTitleFontSize = 15;

/// The chrome's type scale, applied to both themes in `app.dart`.
///
/// [base] is the platform's own text theme, which is where the face comes from:
/// this project bundles no sans and asks for none by name, so the chrome is set
/// in whatever the desktop sets everything else in. Only the sizes are ours, and
/// they are stated once here rather than at three hundred call sites.
TextTheme chromeTextTheme(TextTheme base) => base.copyWith(
  // Body and labels — the great majority of the chrome.
  bodyLarge: base.bodyLarge?.copyWith(fontSize: chromeFontSize + 1),
  bodyMedium: base.bodyMedium?.copyWith(fontSize: chromeFontSize),
  bodySmall: base.bodySmall?.copyWith(fontSize: chromeSmallFontSize),
  labelLarge: base.labelLarge?.copyWith(fontSize: chromeFontSize),
  labelMedium: base.labelMedium?.copyWith(fontSize: chromeSmallFontSize),
  labelSmall: base.labelSmall?.copyWith(fontSize: chromeSmallFontSize - 1),
  // Titles — a step up, and no further. A dialog heading is a heading because
  // of its weight and its position, not because it is half again as tall.
  titleLarge: base.titleLarge?.copyWith(
    fontSize: chromeTitleFontSize + 2,
    fontWeight: FontWeight.w600,
  ),
  titleMedium: base.titleMedium?.copyWith(
    fontSize: chromeTitleFontSize,
    fontWeight: FontWeight.w600,
  ),
  titleSmall: base.titleSmall?.copyWith(
    fontSize: chromeFontSize,
    fontWeight: FontWeight.w600,
  ),
  // The one place the chrome is allowed to be large: the storage-unavailable
  // screen, which is the whole window and has nothing to compete with.
  headlineSmall: base.headlineSmall?.copyWith(fontSize: 20),
);

/// The chrome style for text a painter draws itself.
///
/// The canvas has no [Theme] to ask, so the two places that paint chrome onto
/// the editor surface — the page-break numbers — come here instead of reaching
/// for the script's [scriptFontFamily].
TextStyle chromeLabelStyle(Color colour) => TextStyle(
  fontSize: chromeSmallFontSize,
  color: colour,
  height: 1,
);
