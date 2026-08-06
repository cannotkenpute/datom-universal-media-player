# Datom Universal Media Player

The Datom Universal Media Player is a local-first converter and player for
portable `.datom` media files.

## Product contract

- A converter accepts a source file and an available codec, then emits a
  self-describing `.datom` file.
- The player accepts any valid `.datom` file and selects a decoder available on
  the current device.
- Codec-specific work belongs at the converter and terminal boundaries. Player
  policy remains codec-independent.
- Media bytes, private paths, browser objects, and device capabilities never
  enter persistent datoms or player state.

The current v1 implementation is the first compatibility slice: it wraps MP4
and MP3 payloads without transcoding and delegates decoding to each platform's
native media stack. The format and terminal boundaries are designed to add
codec adapters without changing controller semantics.

## Architecture

- `src/cljc/datomworld/media`: immutable format, controller, view, and event-log
  policy shared across platforms.
- `src/cljd/datomworld/media`: ClojureDart application and capability-owning
  media terminal.
- `lib`: Flutter/Dart source, playback, conversion, file, and fullscreen
  bridges.
- `src/cljc/dao`, `src/cljc/yin`, `src/cljc/yang`: the minimal Datomworld stream,
  PostGraphics, and Yin.VM runtime required by the player.
- `web`, `android`, `ios`, `macos`, `linux`, `windows`: device shells.
- `docs/datmedia-format.md`: Datom Media Container v1 contract.

## Run

```bash
flutter pub get
clojure -M:cljd compile
flutter test
flutter run
```

Focused policy tests:

```bash
clojure -M:test \
  -n datomworld.media.controller-test \
  -n datomworld.media.datom-log-test \
  -n datomworld.media.format-test \
  -n datomworld.media.view-test
```

Android requires API 24 or newer. iOS requires 13 or newer.

## License

GNU General Public License v2. See `LICENSE`.
