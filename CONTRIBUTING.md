# Contributing

Thanks for helping Slugline. Small, focused bug fixes and improvements are the
easiest changes for one maintainer to review.

Before opening a pull request:

1. Search existing issues and describe the behavior you intend to change.
2. Keep Rust responsible for document semantics, persistence, pagination and
   PDF output; keep Flutter responsible for input and presentation.
3. Add no network requests, telemetry, account system, font download, database,
   or persisted lock file.
4. Add a one-line entry to `docs/DEPENDENCIES.md` with every new Rust or Dart
   dependency.
5. Follow the [verification policy](AGENTS.md#verification): format changed code
   and run focused tests for the behavior touched. A small fix or PR does not
   need the whole Rust/Flutter/native suite, a release build or a CI watch.
   Prose-only changes need a diff review and `python3 tools/check_docs.py` when
   changing governed docs. Existing useful coverage is enough; add regressions
   for meaningful failures rather than tests for every small edit.

Full development checks run once after a substantial feature/refactor or batch,
or on explicit request. Select the affected side; run both for broad cross-layer
changes. These are a command reference, not the minimum for each contribution.

From the repository root, for a full Rust validation:

```sh
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

From `app/`, for a full Flutter validation:

```sh
dart format --output=none --set-exit-if-changed lib test integration_test test_driver
flutter analyze
flutter test
```

Use version, layering, reference and binding checks when changing their inputs.
Native tests need Xvfb: use `./tools/agent.sh native <suite> [flutter-test-args...]`
for a local change (`native --list` shows the suites);
`./tools/test_linux_integration.sh` runs all files when full native validation is
warranted. Release builds, packaging and GitHub release debugging wait until the
explicitly requested final release task; see [RELEASING.md](docs/RELEASING.md).

Explain the change, relevant checks and material limitations briefly. A separate
evidence report or handoff is not required for ordinary work. Do
not attach private or confidential screenplays to issues, tests, or pull
requests; reduce a reproduction to a minimal invented Fountain file.

By contributing, you agree that your contribution is licensed under the
project's GPL-3.0-or-later license.
