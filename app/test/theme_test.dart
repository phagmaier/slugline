import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/theme.dart';

/// The luminance step between two surfaces, in the terms the eye reads them in.
double _step(Color a, Color b) =>
    (a.computeLuminance() - b.computeLuminance()).abs();

void main() {
  for (final brightness in Brightness.values) {
    final name = brightness.name;
    final colours = SluglineColors.forBrightness(brightness);

    test('$name: the three surfaces are tellable apart', () {
      // The defect this token set was written for: a sidebar, an editor and a
      // top bar within a couple of luminance points of each other, so that
      // nothing read as a region of its own. A step this small is still small —
      // it has to be, next to a script — but it is a step, and a test is the
      // only thing that keeps it one.
      expect(_step(colours.surfaceRaised, colours.surface), greaterThan(0.004));
      expect(
        _step(colours.surfaceOverlay, colours.surfaceRaised),
        greaterThan(0.004),
      );
      expect(
        _step(colours.surfaceOverlay, colours.surface),
        greaterThan(0.004),
      );

      // Three distinct values, but not a ladder in one direction — and the
      // light theme is why. A raised region on a light canvas goes *darker*
      // than it (a sidebar is a shaded strip beside the page) while an overlay
      // goes whiter (a menu is a card on top of it). In a dark theme both go
      // up. Asserting a monotonic ladder would be asserting the dark theme's
      // habit and calling it a rule.
      expect(
        colours.surfaceRaised.computeLuminance(),
        brightness == Brightness.dark
            ? greaterThan(colours.surface.computeLuminance())
            : lessThan(colours.surface.computeLuminance()),
      );
    });

    test('$name: the hairline is a hairline', () {
      // 8–12% of the foreground: enough to draw an edge, not enough to be a
      // line in its own right. A border that crept up to a visible grey would
      // be a box, which is the other way to lose the regions.
      expect(colours.border.a, greaterThanOrEqualTo(0.08));
      expect(colours.border.a, lessThanOrEqualTo(0.14));
    });

    test(
      '$name: small status and hint text is readable on every chrome surface',
      () {
        for (final background in [
          colours.surface,
          colours.surfaceRaised,
          colours.surfaceOverlay,
        ]) {
          final a = colours.textTertiary.computeLuminance();
          final b = background.computeLuminance();
          final ratio = ((a > b ? a : b) + 0.05) / ((a < b ? a : b) + 0.05);
          expect(ratio, greaterThanOrEqualTo(4.5));
        }
      },
    );

    test('$name: the three text weights descend', () {
      final surface = colours.surface;
      double contrast(Color text) =>
          (text.computeLuminance() - surface.computeLuminance()).abs();
      expect(
        contrast(colours.textPrimary),
        greaterThan(contrast(colours.textSecondary)),
      );
      expect(
        contrast(colours.textSecondary),
        greaterThan(contrast(colours.textTertiary)),
      );
      // Body text against its own background, at WCAG AA for ordinary text.
      // The script is set at 12 point and read for hours; this is the one
      // contrast figure in the set that is not a matter of taste.
      final light =
          colours.textPrimary.computeLuminance() > surface.computeLuminance()
          ? colours.textPrimary
          : surface;
      final dark = identical(light, surface) ? colours.textPrimary : surface;
      final ratio =
          (light.computeLuminance() + 0.05) / (dark.computeLuminance() + 0.05);
      expect(ratio, greaterThan(4.5));
    });

    test('$name: the theme carries its tokens and spends the accent once', () {
      final theme = sluglineTheme(brightness);
      expect(theme.extension<SluglineColors>(), same(colours));

      // The accent reaches Material through `primary` — filled buttons and the
      // things this application marks as selected — and nowhere else. A
      // `TextButton` in a dialog row must not come out wearing it, or the
      // filled button beside it stops being the one thing that does.
      expect(theme.colorScheme.primary, colours.accent);
      expect(
        theme.textButtonTheme.style?.foregroundColor?.resolve({}),
        colours.textPrimary,
      );
      expect(
        theme.filledButtonTheme.style?.backgroundColor?.resolve({}),
        colours.accent,
      );

      // Regions are separated by an edge, not a shadow. Both bars and the
      // overlays say so by having no elevation to cast one with.
      expect(theme.appBarTheme.elevation, 0);
      expect(theme.appBarTheme.scrolledUnderElevation, 0);
      expect(theme.dialogTheme.elevation, 0);
      expect(theme.popupMenuTheme.elevation, 0);
      expect(theme.dividerTheme.color, colours.border);
    });

    testWidgets('$name: context.colours is the set the theme installed', (
      tester,
    ) async {
      late SluglineColors seen;
      await tester.pumpWidget(
        MaterialApp(
          theme: sluglineTheme(brightness),
          home: Builder(
            builder: (context) {
              seen = context.colours;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen, same(colours));
    });
  }

  testWidgets('a widget with no Slugline theme still gets a set', (
    tester,
  ) async {
    // Widget tests that build a bare `ThemeData` are about something else, and
    // must not fail on a null token set. They get the one their brightness
    // implies.
    late SluglineColors seen;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Builder(
          builder: (context) {
            seen = context.colours;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen, same(SluglineColors.dark));
  });
}
