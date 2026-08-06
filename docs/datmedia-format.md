# Datom Media Container v1

`.datom` is a local-first media container. It places a canonical d5 manifest
before an unchanged MP4 or MP3 payload. It is not a codec, encryption, DRM,
transcoding, or re-encoding system.

## Binary layout

| Offset | Size | Value |
| --- | ---: | --- |
| 0 | 8 bytes | UTF-8 magic `DATOM1\r\n` |
| 8 | 4 bytes | Unsigned little-endian manifest byte length |
| 12 | variable | UTF-8 EDN vector of canonical five-tuple datoms |
| 12 + manifest length | remaining bytes | Original MP4 or MP3 payload |

The manifest is limited to 1 MiB. Readers reject unknown magic, unknown
versions, oversized or truncated manifests, non-canonical datoms, disallowed
attributes, kind/MIME conflicts, invalid payload signatures, or a payload
length different from `:datom.media/payload-bytes`.

## Required manifest

```clojure
[[-1025 :datom.media/version 1 1 1]
 [-1025 :datom.media/kind :video 1 1]
 [-1025 :datom.media/codec-mode :native-payload 1 1]
 [-1025 :datom.media/original-name "example.mp4" 1 1]
 [-1025 :datom.media/original-mime "video/mp4" 1 1]
 [-1025 :datom.media/payload-bytes 12345678 1 1]]
```

- `:datom.media/kind` is exactly `:video` or `:audio`.
- Version 1 accepts MP4 (`video/mp4`) and MP3 (`audio/mpeg`).
- `:native-payload` means the original media bytes and codec are unchanged.
- Playback support is still determined by the platform's native codecs.
- Parsing dispatches on magic bytes, not the filename extension. Renaming a raw
  MP4 or MP3 to `.datom` does not create a valid container.

## Legacy import

Readers recognize `DATMOV1\n` and `DATMUS1\n`. Legacy `:movie` and `:music`
facts are normalized to `:video` and `:audio` at the source terminal. Legacy
files play without being rewritten and can be converted to `.datom`. New
exports never produce `.datmov` or `.datmus`.

## Local conversion and playback

Conversion writes the fixed header, EDN manifest, and original payload as a
stream. On web, the host composes and slices browser Blobs. On Android and iOS,
the host streams through bounded file I/O and supplies a temporary `.mp4` or
`.mp3` payload path to the decoder. Media bytes, browser objects, object URLs,
and private paths never enter Yin state, DaoDB, settings, diagnostics, or
ordinary DaoStreams.

The app performs no uploads and has no remote media API. Anyone implementing
this documented parser can extract the native payload.

## Run locally

```bash
flutter pub get
mise exec -- clj -M:cljd compile
flutter test
flutter run -d chrome
flutter run -d android
flutter run -d ios
flutter build web
flutter build apk
```

Android requires API 24 or newer. iOS requires 13 or newer.
