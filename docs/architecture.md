# Architecture

This document describes how Notch Recorder is put together and why. It covers
what the code does today; the README covers how to build and use it.

## Goals that shaped the design

- A recording that is small and sharp: hardware HEVC at constant quality,
  scaled cleanly, constant frame rate.
- A live transcript of both the microphone and system audio, about a second
  behind the speaker, without sending audio anywhere.
- Close to zero cost when idle: no timers, no polling, no resident web view
  or JavaScript runtime.
- Never lose a long recording or its transcript to a crash, a full disk, a
  sleeping Mac or a quit.

## Where each language goes

Screen capture, hardware encoding, audio mixing and on-device speech
recognition are only available as Apple frameworks (ScreenCaptureKit,
VideoToolbox, AVFoundation, Core ML). Reaching them from a JavaScript runtime
would still need a native module, plus a runtime that stays resident. So the
split is:

| Layer | Language | Reason |
|---|---|---|
| Capture, scaling, encoding, mixing, transcription, database, shortcut, menu bar | Swift (AppKit) | The only way to reach these frameworks at low cost |
| Live transcript window | SwiftUI | Visible for the whole recording; a web view here would hold tens of megabytes for the session |
| Library, transcript viewer, Settings, onboarding | TypeScript (React, Tailwind, Effect) in a WKWebView | The largest UI surface; created when its window opens and torn down when it closes, so WebKit's helper processes exit |

Alternatives that were considered and rejected: Electron (a bundled browser
engine stays resident), Tauri (a third language with no gain for these APIs)
and Electrobun (the runtime stays resident and capture still needs native
code).

The idle path is plain AppKit: a status item and a Carbon hot key. SwiftUI
views and the web view are created only when shown.

## Package layout

```
Sources/
  Common/         paths, logging, file naming, the Me/Others source type
  RecorderKit/    capture, scaling, encoding, mixing, writing
  TranscriptKit/  speech engine, segmentation, live and repeat transcription
  LibraryKit/     SQLite schema and repository (GRDB)
  BridgeKit/      Library window, bridge router, DTOs, URL scheme handlers
  LiveUI/         SwiftUI live transcript window
  NotchRecorder/  the app: lifecycle, saving, recovery, menu, shortcut
  ASRCheck/       command line tool that transcribes a file with the real model
web/
  packages/core/  bridge contract (Effect Schema), errors, transcript formats
  apps/library/   the Library UI
  scripts/        theme generator
theme/            the colour source for both UIs
```

Library targets do not depend on each other except through `Common`
(`BridgeKit` also uses `LibraryKit`). Hardware and system dependencies sit
behind protocols (`ScreenSource`, `SpeechEngine`, `FileOps`, `RecoveryMedia`)
so the logic around them is tested with fakes.

## Recording pipeline

```
ScreenCaptureKit (one display, cursor optional, own app excluded)
  video  BGRA, sRGB, display pixel size
           -> Metal: Lanczos-3 scale, BT.709 limited range, RGB to NV12
           -> VideoToolbox HEVC (hardware)
           -> movie writer
  system audio 48 kHz stereo --+
  microphone ------------------+-> mixer (placed by timestamp) -> AAC -> movie writer
                               |
                               +-> per-source 16 kHz mono -> live transcription
                                                          -> sidecar audio files
```

Capture. One `SCStream` delivers screen frames, system audio and the
microphone, so all three share one host-time clock. The content filter
excludes the app's own windows and the stream excludes its own audio, so the
live window and the Library never appear in a recording. Frames arrive as
8-bit BGRA in sRGB with a queue depth of 4.

Scaling. Three Metal compute passes: horizontal Lanczos-3, vertical
Lanczos-3, then BT.709 limited-range conversion to NV12 with 2x2 chroma
averaging, written straight into a pixel buffer from the encoder's pool. The
shaders are compiled at runtime from source, so the project builds with the
Command Line Tools alone (they ship no Metal compiler).

Output size. A standard display is recorded at a fraction of its pixel size
(0.8 by default, so 5120x2160 becomes 4096x1728). A Retina display is recorded
at a number of output pixels per screen point (4/3 by default, so a 3024x1964
panel becomes 2016x1308), which keeps text crisp without the cost of full
Retina resolution. Dimensions are rounded down to even numbers.

Encoding. A VideoToolbox compression session using Apple's hardware HEVC
encoder: Main profile, constant quality 0.60, no bitrate cap, keyframe every
2 seconds, frame reordering on (B-frames), Rec. 709 colour tags. The property
set matches what OBS uses for its Apple VT HEVC hardware encoder in CRF mode.

Constant frame rate. ScreenCaptureKit only delivers a frame when the screen
changes. `FramePacer` maps host time to frame indices, repeats the last frame
to fill gaps and leaves out time spent paused, so timestamps are always
`n / fps`.

Audio. `AudioTimeline` places each source's buffers by timestamp at 48 kHz.
Buffers stay contiguous through normal jitter and are re-anchored when drift
passes 10 ms, which keeps a USB microphone and system audio in sync over
hours. `AudioMixer` sums the two at unity gain, duplicates a mono microphone
to both channels, and treats a source that has gone quiet as silence so one
stalled source never holds up the other.

Writing. AVAssetWriter does not flush fragments for `.mp4`, so the working
file is a QuickTime movie with a movie fragment every 2 seconds. On stop it is
rewrapped into MP4 without re-encoding. A crash therefore costs at most the
last fragment, and recovery rewraps whatever is on disk.

Sidecars. Each source is also written as 16 kHz mono PCM in a CAF file while
recording (which survives a crash) and compressed to AAC after saving. These
files are what make Transcribe again possible with speakers intact.

Session. `RecordingSession` owns the pipeline on one serial queue. It restarts
capture after a stream error (and fails after more than three restarts within
five seconds), warns when free disk space drops under 5 GB and stops cleanly
under 1 GB.

## Transcription

The engine is the FluidAudio SDK running Parakeet TDT 0.6B v2 and Silero VAD
through Core ML. `SpeechEngine` is the protocol in front of it.

- Two independent streams: the microphone is "Me", system audio is "Others".
  The source identifies the speaker, so no diarization model is involved.
- Each stream is resampled to 16 kHz mono and passed through voice activity
  detection in 4096-sample chunks (256 ms).
- `UtteranceSegmenter` is a pure state machine: speech starts at a
  probability of 0.5, ends after 600 ms below 0.35, keeps about 200 ms of
  lead-in, and is cut at 14 seconds. While someone is speaking it asks for a
  partial transcript once a second; when they stop, the utterance is
  transcribed a final time and committed as a segment.
- `EchoDeduper` drops a "Me" segment when an "Others" segment within 1.5
  seconds has nearly the same words, which happens when loudspeakers feed the
  call back into the microphone.
- One model instance serves both streams, with separate decoder state per
  utterance. It is loaded before capture starts and unloaded when the
  recording ends.
- Failures never reach the recorder. If the model cannot load or a call
  fails, the transcript is marked failed, the recording continues, and the
  audio remains in the sidecars for later.
- `Retranscriber` rebuilds a transcript from the sidecars, or from the
  video's mixed track when there are none (labelled "Speaker"). It is
  cancellable and resumes from the last transcribed offset, which is also how
  recovery finishes a transcript after a crash.

Models are stored in the app's own folder. On first use the app copies
Parakeet v2 from FluidAudio's shared cache when another app has already
downloaded it; otherwise FluidAudio downloads it.

## Library data

One SQLite database in WAL mode, owned by the Swift side through GRDB. The web
UI reads and writes only through the bridge.

| Table | Contents |
|---|---|
| `recording` | id, title, start and end time, duration, display name, size, staging path, video path, status, transcript status, transcribed-until offset, sidecar paths, thumbnail count, a JSON snapshot of the settings used, error message |
| `segment` | recording id, source (`me`, `others` or `speaker`), start and end in milliseconds, text, original text when edited, confidence |
| `segment_fts` | FTS5 index kept in step with `segment` |
| `setting` | key and JSON value; all settings are stored as one value |

A recording's status is one of `recording`, `unsaved`, `saved`, `discarded`
or `failed`. Segments are written as each one is finalised, so a crash keeps
everything up to the last pause in speech.

Settings decode with defaults for missing keys and are clamped to valid
ranges, so settings written by an older build always load.

## Lifecycle

Start. The coordinator loads the speech model, then starts capture, and shows
the live window. If the model fails to load the recording starts anyway and
the window says why.

Stop. The session finalises the file in the staging folder, then the
recording is saved automatically: moved to the video folder under a
collision-safe name (a rename on the same volume, a copy across volumes),
thumbnails are generated, sidecars are compressed, and transcript files are
exported if that option is on. A failed export never undoes a save. If the
move fails, the recording stays in staging and appears as Unsaved.

Sleep and wake. Sleep pauses the session and wake resumes into the same file
with no gap in the timeline.

Quit. Quitting while recording asks first. Logout, restart and shutdown stop
the recording without asking. In both cases the file is finalised before the
app exits.

Recovery. At launch, any row still marked as recording, and any staging file
without a row, becomes an Unsaved recording with a playable file. If its
transcript stops short of the end, a job is queued to finish it from the
sidecar audio.

State file. `state.json` in the data folder holds the current phase and
process id, written atomically on every change, so scripts can tell whether a
recording is running.

## The bridge between Swift and TypeScript

- Requests go through `WKScriptMessageHandlerWithReply` as
  `{ method, params }` and come back as `{ ok, value }` or
  `{ ok: false, error }`. `BridgeRouter` dispatches them to typed handlers.
- Events (library changed, recorder state, repeat transcription progress) are
  pushed from Swift to the page.
- The contract is defined once in `web/packages/core/src/contract.ts` with
  Effect Schema. Swift mirrors it with `Codable` DTOs. A fixture written by
  the TypeScript tests is decoded by the Swift tests, which keeps the two
  sides in step.
- Every payload is decoded on the TypeScript side. A reply that breaks the
  contract becomes a `DecodeError`, a transport failure a `BridgeError`, and a
  failure reported by Swift a `NativeError` with a message written for the
  user.
- The UI is served from the app bundle through the `nr-app://` scheme. Videos
  and thumbnails are served through `nr-media://` with byte-range support, so
  the player can seek in multi-gigabyte files without loosening WebKit's file
  access.
- Transcript formats (Markdown, text, SRT, WebVTT, JSON) are implemented once
  in the TypeScript core. The Library uses them directly; the native save path
  runs the same code from a small bundle in a JavaScriptCore context that is
  created per call and released afterwards.

## Theme

`theme/notch-dark.json` is the single source of colour. `web/scripts/gen-theme.mjs`
converts it into CSS variables for the Library and a Swift enum for the live
window, so both UIs share one palette. Both generated files are committed.

## Build

The project is a Swift package with no Xcode project. `scripts/make-app.sh`
builds the web UI, builds the release binary, assembles the app bundle
(Info.plist, the web UI, the formatter bundle, a generated icon) and signs it.
The icon is drawn by `scripts/make-icon.swift`, so no asset catalog compiler
is needed.

macOS ties the Screen Recording and Microphone permissions to the app's code
signature. Ad-hoc signatures differ between builds, which is why the build
accepts a stable identity through `CODESIGN_IDENTITY`.

## Testing

- Swift: pure logic (pacing, audio placement, mixing, segmentation, echo
  de-duplication, disk guard, naming, termination policy) is tested directly.
  The session, live transcription, saving and recovery are tested with fake
  sources, engines and file operations. The repository is tested against an
  in-memory database.
- TypeScript: transcript formats, subtitles and the contract in
  `packages/core`; bridge services, routing and helpers in `apps/library`
  against an in-memory stand-in for the native app.
- Tests that need a real screen, microphone or model are not part of the
  automated suite. `ASRCheck` exercises the real model by hand.
