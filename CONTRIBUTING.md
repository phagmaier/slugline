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
5. Run the relevant checks from `AGENTS.md`; at minimum:

   ```sh
   cargo fmt --all --check
   cargo clippy --workspace --all-targets -- -D warnings
   cargo test --workspace
   python3 tools/check_layering.py
   python3 tools/check_version.py
   cd app && flutter analyze && flutter test
   ```

Linux integration tests need Xvfb:

```sh
./tools/test_linux_integration.sh
```

Explain what changed, how it was tested, and any check you could not run. Do
not attach private or confidential screenplays to issues, tests, or pull
requests; reduce a reproduction to a minimal invented Fountain file.

By contributing, you agree that your contribution is licensed under the
project's GPL-3.0-or-later license.
