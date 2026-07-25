# Editor spike — throwaway code, kept as evidence

Three prototypes of the multi-block editing surface, built during Phase 0 to
decide how text editing gets implemented. **None of this ships.** It is kept
because it is the evidence behind ADR 0005 in `docs/DECISIONS.md`, and because
Prototype B is the fallback if the IME gate at the end of Phase 3 fails.

| File | Prototype |
| --- | --- |
| `lib/prototype_a.dart` | One `EditableText` per paragraph in a `ListView.builder` |
| `lib/prototype_b.dart` | `super_editor` with `blockType` metadata per screenplay element |
| `lib/prototype_c.dart` | A single `TextInputClient` with our own layout and painting |

All three implement `lib/surface.dart`, so `lib/main.dart` drives them with one
identical benchmark script and the numbers compare.

## Running

```sh
# Interactive — type, arrow around, extend a selection with shift+arrows
flutter run -d linux --dart-define=P=c

# Benchmark: runs the scripted workload, prints a table, exits
flutter build linux --release --dart-define=P=c --dart-define=BENCH=true
./build/linux/x64/release/bundle/spike
```

`P` is `a`, `b`, or `c`. `BLOCKS` overrides the 3,000-paragraph document size.

## Reading the output

Wall-clock rows are vsync-quantised — 16.7 ms means "one frame at 60 Hz", which
is the floor, not a cost. The row that matters is **frame build time by phase**:
§1.3 allows 16 ms from keystroke to glyph, and a build longer than that cannot
keep up regardless of what the wall clock says.

This project is not in the Rust workspace and is not built by CI. It has a
dependency (`super_editor`) that the application deliberately does not.
