# Notch Recorder

A macOS menu bar screen recorder that writes a transcript while you record.
One shortcut starts a recording of your screen, your microphone and whatever
your Mac is playing; a live window shows what is being said as it is said; and
when you stop you have a small HEVC video plus a searchable transcript that
tells your voice apart from everyone else's.

Everything happens on your Mac. Speech recognition runs on-device (Parakeet
through [FluidAudio](https://github.com/FluidInference/FluidAudio)), the
library is a local SQLite file, and the app makes no network requests apart
from the one-time download of the speech model.

## Why

Recording a call or a walkthrough usually means two tools and a wait: a screen
recorder, then a transcription service that receives the audio afterwards.
Notch Recorder does both at once and keeps the result private:

- Local. Video, audio and transcripts never leave the machine.
- Live. The transcript appears about a second behind the speaker, not after an upload.
- Light. Hardware HEVC encoding, speech recognition on the Neural Engine, and
  no timers or background work when you are not recording.

## Features

- Records one display with the cursor, system audio and the microphone mixed
  into a single stereo track. The app's own windows and sound are excluded.
- Hardware HEVC video (constant quality, 30 fps constant frame rate by
  default) and AAC audio in an MP4, scaled on the GPU with a Lanczos filter.
- Live transcript in a floating window with a timer, level meters and Stop.
  The microphone is labelled "Me" and system audio "Others", so no speaker
  diarization model is needed.
- Crash safety: the file is written in 2 second fragments, so a crash or
  power loss costs at most the last fragment. The next launch recovers the
  recording and finishes its transcript.
- Sleep pauses a recording and wake resumes into the same file. Quitting,
  logging out or shutting down stops the recording cleanly first.
- Library window: recordings grouped by day with thumbnails, full-text search
  across every transcript (SQLite FTS5), a player with a transcript that
  follows playback, click a line to seek, find in transcript, inline
  correction of misheard words (the original is kept).
- Copy a whole transcript or selected lines as clean text, text with
  timestamps, plain text or Markdown.
- Export to Markdown, plain text, SubRip (`.srt`), WebVTT (`.vtt`) or JSON,
  on demand or automatically on save.
- Transcribe again: per-speaker audio is kept beside the library, so any
  recording can be transcribed again later with "Me" and "Others" intact.
- Global shortcut Control-Option-Command-R, a menu bar item, and
  `notchrecorder://` URL commands for scripting.

## Requirements

- macOS 15 or later on an Apple Silicon Mac.
- Permissions, requested on first launch:
  - Screen & System Audio Recording, to capture the display and what the Mac plays.
  - Microphone, to record and transcribe your voice. If you decline, recordings
    contain system audio only.
- To build: the Swift 6.2 toolchain or later (Xcode or the Command Line
  Tools are both enough) and Node.js 22.20 or later with npm.
- About 500 MB of disk space for the speech model.

## Build from source

There is no prebuilt download. On the Mac:

```sh
git clone https://github.com/direksethi/notch-recorder.git
cd notch-recorder
scripts/make-app.sh
```

`make-app.sh` installs the web dependencies, builds the Library UI, builds the
Swift package in release mode and assembles `build/Notch Recorder.app` with an
ad-hoc signature. Install and start it with:

```sh
mkdir -p ~/Applications
cp -R "build/Notch Recorder.app" ~/Applications/
open ~/Applications/"Notch Recorder.app"
```

The steps the script runs, if you prefer to run them yourself:

```sh
cd web && npm ci && npm run build && cd ..
swift build -c release --product NotchRecorder
```

### Signing

macOS ties the Screen Recording and Microphone permissions to the app's
signature. An ad-hoc signature changes with every build, so after rebuilding
you may be asked to grant the permissions again. To avoid that, sign every
build with the same identity:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/make-app.sh
```

Any code-signing identity in your keychain works. If you have none,
`scripts/setup-signing.sh` creates a self-signed one named "Notch Recorder
Local Signing" in a dedicated keychain. The app is not sandboxed and not
notarized.

## Usage

- Start or stop: Control-Option-Command-R, the menu bar icon, or the Record
  button in the Library.
- Starting loads the speech model first (a fraction of a second once it is
  cached by the system, up to about a minute the first time), then capture
  begins. If the model cannot load, the recording still starts and the
  transcript can be produced later with Transcribe again.
- While recording, the Live transcript window shows the timer, levels, Stop
  and the transcript so far. It is never captured in the recording.
- On stop, the recording is saved to the video folder from Settings, named by
  date and time (`2026-01-31 14-05-09.mp4`). If it cannot be saved it is kept
  in the Library under Unsaved, never deleted.
- Open Library from the menu bar icon to browse, search, rename, copy, export
  or delete recordings, and to change Settings: video folder, display,
  microphone, cursor, output size, frame rate, quality, transcript export and
  launch at login.

URL commands: `notchrecorder://start`, `stop`, `toggle`, `library`,
`settings`, `close`. For example `open notchrecorder://toggle`.

## Output

| | Standard display | Retina display |
|---|---|---|
| Size | 0.8 of the pixel size: 5120x2160 becomes 4096x1728 | 4/3 of the point size: 3024x1964 becomes 2016x1308 |
| Video | HEVC (hardware), Main profile, quality 0.60, 30 fps constant, keyframe every 2 s, B-frames, Rec. 709 | same |
| Audio | AAC 160 kbit/s, 48 kHz stereo, microphone and system audio mixed | same |

The defaults follow a common OBS profile for Apple's hardware HEVC encoder.
Scale, frame rate and quality can be changed in Settings.

## Where your data lives

| What | Where |
|---|---|
| Saved videos | `~/Movies/Notch Recorder/` by default; change it in Settings |
| Library database | `~/Library/Application Support/NotchRecorder/library.sqlite` (recordings, transcripts, settings) |
| Recordings in progress and unsaved | `~/Library/Application Support/NotchRecorder/Staging/` |
| Per-speaker audio for Transcribe again | `~/Library/Application Support/NotchRecorder/Audio/` |
| Thumbnails | `~/Library/Application Support/NotchRecorder/Thumbnails/` |
| Speech models | `~/Library/Application Support/NotchRecorder/Models/` |
| Recorder state for scripts | `~/Library/Application Support/NotchRecorder/state.json` |

Transcripts live in the database. Files are written elsewhere only when you
export them. Logs go to the unified log:

```sh
log show --predicate 'subsystem == "com.direksethi.NotchRecorder"' --last 1h
```

To remove everything, delete the app, the Application Support folder above and
your video folder.

## Speech model

Transcription uses [Parakeet TDT 0.6B v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2)
(English) by NVIDIA, in the Core ML conversion published by FluidInference,
with Silero VAD for voice activity detection. Both run through the FluidAudio
SDK on the Neural Engine.

The models are not part of this repository or of the built app. FluidAudio
downloads them into the Models folder the first time a recording starts, which
needs a network connection once. If another FluidAudio app (such as
FluidVoice) has already downloaded Parakeet v2 into FluidAudio's shared cache
on the same Mac, Notch Recorder copies that instead of downloading.

Licenses: Parakeet TDT 0.6B v2 is released under CC-BY-4.0, Silero VAD under
MIT, FluidAudio under Apache-2.0. If you redistribute the model, follow the
CC-BY-4.0 attribution terms.

## Architecture

A Swift package with focused library targets and a TypeScript UI:

| Part | Role |
|---|---|
| `RecorderKit` | ScreenCaptureKit capture, Metal Lanczos scaling to NV12, VideoToolbox HEVC, audio mixing, fragmented movie writer |
| `TranscriptKit` | Voice activity detection, utterance segmentation, live and repeat transcription, echo de-duplication |
| `LibraryKit` | SQLite library through GRDB, with FTS5 search |
| `BridgeKit` | The Library window (WKWebView), the typed request and event bridge, URL scheme handlers for the UI and for seekable video |
| `LiveUI` | The SwiftUI live transcript window |
| `NotchRecorder` | The app: menu bar item, shortcut, recording lifecycle, saving, crash recovery |
| `web/packages/core` | Effect Schema contract shared with Swift, transcript formatting, subtitles |
| `web/apps/library` | The Library, Settings and onboarding UI (React, Tailwind) |

The capture and encoding path is native because those frameworks are only
available natively. The Library is a web view that exists only while its
window is open. The transcript formatter is written once in TypeScript and
also runs natively through JavaScriptCore. See
[docs/architecture.md](docs/architecture.md) for the pipeline, the data model
and the reasons behind these choices.

## Development

```sh
# TypeScript: typecheck and tests (runs on any OS)
cd web
npm ci
npm run typecheck
npm test

# Library UI in a browser with made-up data, at http://localhost:5280
npm run dev -w @nr/library

# Swift tests (macOS)
cd ..
scripts/test.sh
```

`scripts/test.sh` first builds the formatter bundle and the contract fixtures
that the Swift bridge tests read, then runs `swift test`. With only the
Command Line Tools installed it also adds the search paths Swift Testing needs.
Arguments are passed on, for example `scripts/test.sh --filter RecorderKitTests`.

Colours for both UIs come from `theme/notch-dark.json`; `npm run theme` in
`web/` regenerates `web/apps/library/src/theme.css` and
`Sources/LiveUI/Theme.generated.swift`.

`swift run ASRCheck <audio file>` transcribes a file with the real model and
prints timing and memory use.

If your checkout lives on another machine, `scripts/remote-build.sh <ssh-host>`
builds the web UI locally, copies the tree to a Mac over SSH and builds or
tests there. It is optional; see the comments at the top of the script.

## Known limitations

- English only. The app loads Parakeet v2, which is an English model.
- Records one whole display. There is no window or region capture, webcam
  overlay, or editing.
- Speakers are "Me" (microphone) and "Others" (system audio). People on the
  other side of a call are not told apart.
- With loudspeakers and no echo cancellation, the microphone also hears the
  call. Duplicate lines are detected and dropped, but the check is a text
  comparison and can miss.
- The keyboard shortcut is fixed at Control-Option-Command-R.
- There is no pause control. A recording pauses only while the Mac sleeps.
- Not sandboxed or notarized, and there is no prebuilt release or automatic
  update. macOS asks you to confirm screen recording access again from time to
  time; this is system behaviour.
- No custom vocabulary: names and product terms can be misheard. Lines can be
  corrected by hand in the Library.

## License

MIT. See [LICENSE](LICENSE). Dependencies and the speech models carry their
own licenses, listed under Speech model above;
[GRDB](https://github.com/groue/GRDB.swift) is MIT.
