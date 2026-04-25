# Web build assets for Drift

Two files in this directory are required for the web build to talk
to SQLite:

- `sqlite3.wasm` — the SQLite WASM binary (from
  https://github.com/simolus3/sqlite3.dart/releases — match the
  sqlite3 Dart package version pinned in pubspec.yaml).
- `drift_worker.js` — compiled JS worker that lets the database
  run off the main thread.

To regenerate after a Drift bump:

```
# Compile the worker (drift_worker.dart lives inside the drift
# package's web/ folder — copy + compile, then remove the source).
cp ~/.pub-cache/hosted/pub.dev/drift-<version>/web/drift_worker.dart \
   web/drift_worker.dart
dart compile js web/drift_worker.dart -o web/drift_worker.js -O4
rm web/drift_worker.dart

# Re-download sqlite3.wasm matching the sqlite3 package version
# pinned in pubspec.yaml:
curl -sL -o web/sqlite3.wasm \
  https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-<version>/sqlite3.wasm
```

Both files are committed to the repo so the web build is hermetic
— no post-pub-get download needed.
