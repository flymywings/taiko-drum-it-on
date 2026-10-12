# Implementation guide and React Native handoff

This is a behavior guide for rebuilding the prototype for Android and iPhone. The Flutter web app is the fastest way to inspect the current behavior. Recreate the chart, timing, and judgment rules before changing visuals or adding new modes.

## What the player sees

1. The library opens with imported difficulty entries and a timing-offset control. With no entries, it offers **Import song**. A storage failure shows an error and **Retry** instead of an endless spinner.
2. Import accepts an `.osz` pack or a `.osu`/`.tja` chart selected together with audio. It reports per-file warnings and failures; healthy charts still import when another chart fails.
3. Selecting a difficulty loads its full chart and audio. Web shows **Start song** so playback begins after a player gesture. A lead-in precedes chart time zero. The game has pause, resume, retry, four hit pads, live score/combo, and results. On web and with hardware keyboards, D/F/J/K match the pads from left to right (blue/red/red/blue); held-key repeats are ignored.
4. The offset slider changes judgment timing from −200 to +200 ms in 5 ms steps and persists after restart.

On web, summaries are loaded before full charts so the library can appear quickly. The Android version reads its existing app-private song files. Imported files stay offline and are never uploaded by this app.

## Chart data contract

`lib/chart/chart.dart` is the source of truth. A normalized chart is sorted by `timeMs` and has this shape:

```json
{
  "title": "Example",
  "difficulty": "Easy",
  "audioFileName": "song.wav",
  "format": "TJA",
  "notes": [
    {"timeMs": 1000, "endMs": null, "kind": "don", "large": false, "requiredHits": 0},
    {"timeMs": 1500, "endMs": null, "kind": "ka", "large": true, "requiredHits": 0},
    {"timeMs": 2000, "endMs": 2600, "kind": "balloon", "large": false, "requiredHits": 5}
  ],
  "warnings": []
}
```

All times are integer milliseconds relative to chart audio; negative note times are valid after a TJA offset. `don` is red, `ka` is blue, `roll` is a drumroll, and `balloon` has a target hit count. Long notes require `endMs`. `large` affects tap doubling or roll bonus. Keep this normalized format between parsing, storage, rendering, and judgment in the React Native version. Avoid interpreting raw TJA or osu! data during play.

## Import and storage

The import path is: picker → size checks → optional ZIP extraction → UTF-8 or Shift-JIS decoding → format parser → audio matching → normalized charts → private storage → library summaries. Web runs archive extraction and parsing in a dedicated worker; the UI reports progress while records are saved. Preserve that separation in React Native so a large import does not block touch or animation.

Rules currently implemented:

- Each chosen input is limited to 150 MiB. An `.osz` can have at most 500 entries and up to 150 MiB of supported extracted content; each chart or audio entry is limited to 80 MiB. Symlinks are ignored.
- Accepted audio extensions: MP3, Ogg, WAV, M4A, FLAC. A chart's audio reference is matched by relative path, then normalized filename, then the single selected audio file if there is exactly one. Decoding support depends on the platform.
- `.osu` must be native osu!taiko with `Mode: 1`. Circles become red/blue taps, sliders become rolls, and spinners become balloons. Standard osu! mode conversion is not implemented.
- TJA supports red/blue and large taps, rolls, balloons, BPM changes, measures, delay, and offset. Branching, two-player courses, unsupported symbols, and malformed long notes are rejected. Custom scrolling and Go-Go scoring are reported as ignored.
- Parser failures for one file become import messages; other files continue. Do not save a chart whose audio cannot be found.

Web IndexedDB uses separate stores for summaries, full charts, audio, and settings. Multiple difficulties from one import can reference one audio record. The same browser origin must be used on later visits; private windows and site-data clearing do not preserve it. Android keeps the existing `taiko_songs/<id>/chart.json` plus `audio.<ext>` directories and `settings.json` in the app support directory. Do not change or delete those existing Android files in a Flutter update.

For React Native, use an app-private file location for audio and a small local index for summaries and chart records. Save the file and index as one logical operation: if either fails, remove the incomplete import. Keep large audio out of React component state. Use a stable song ID and an audio reference so several difficulties can share the same copied file.

## Playback clock and judgment

The game uses the audio player's reported position as the time source after audio starts. Before it starts, a monotonic lead-in clock supplies negative chart time. On web, **Start song** immediately begins muted playback from the player's tap to satisfy browser gesture rules; when the lead-in ends, playback seeks to zero and becomes audible. For a chart whose first note is `firstTimeMs`:

```text
leadMs = max(2000, -firstTimeMs + 1000)
before audio: nowMs = leadClockElapsedMs - leadMs + offsetMs
after audio:  nowMs = audioPositionMs + offsetMs
```

The screen updates roughly every 16 ms, but judgments use `nowMs` at the exact touch-down, not the last painted frame. Pause stops the lead clock or audio player. Retry seeks audio to zero and creates a new judgment engine. A song ends after its last note/end plus the 130 ms miss window and 700 ms grace period, or when the audio reports completion.

For React Native, keep judgment logic outside React rendering. Use a monotonic clock and an audio API with a reliable playback position; measure actual device latency on both Android and iPhone. Avoid basing judgment time on animation frame counts or ordinary JavaScript timers. Trigger hits from touch-down and pass color, left/right hand, and current audio time into the engine. Browser playback can require a direct tap; preserve an explicit start/resume action there.

Judgment rules from `lib/game/judgement_engine.dart`:

- Choose the closest pending tap within ±130 ms. Wrong color inside that window is a miss. A matching tap within ±40 ms is Perfect, within ±90 ms is Good; the rest is Miss. Unplayed taps become Miss after 130 ms.
- Perfect scores 300; Good scores 150. Each successful tap increases combo; a miss resets it. A large tap can score twice if a matching second hit comes from the other hand within 50 ms of the first; otherwise it scores once.
- Rolls accept hits during their time span, at least 45 ms apart. Each hit gives 10 points, or 20 for a large roll. Balloon hits give 10 each; meeting its target before the end adds 300. Long-note hits do not change combo.
- Accuracy is `(perfect + 0.5 × good) / (perfect + good + miss)`, or zero if there are no judged taps. This is the prototype's own score model, not another game's scoring system.

## Rendering and performance

The lane hit position is 18% of available width. Notes move according to `x = hitX + (noteTimeMs - nowMs) × width / 2400`. Taps are circles; rolls and balloons span their start/end times. Only pending notes near the visible time window are drawn, plus active long notes that began before it. Judgment scans also use a time window, rather than walking all notes each frame. The lane repaints from the clock without rebuilding the entire screen; score text changes only when its value changes.

In React Native, use a drawing surface or native-driven animation for the lane and keep score/settings controls separate. Keep sorted notes and a moving cursor or binary search for visible notes. Test a roughly 2,000-note chart on real Android and iPhone devices while recording frame time and input-to-judgment latency.

On this computer, three warm reloads of the already-running release preview reached a usable library in 1,460 ms, 269 ms, and 246 ms (median 269 ms). An additional load after rebuilding was 484 ms, but it was not a controlled uncached test; the truly uncached load remains unmeasured. Three release web samples with 2,000 synthetic notes had 95th-percentile frame spans of 2.0, 2.1, and 1.8 ms over 306, 301, and 304 frames; respectively 1, 1, and 0 frames exceeded 32 ms, with no sustained slow frames. Browser start, pause, resume, and retry were exercised on this synthetic chart. A small synthetic ZIP with two difficulties imported through the worker, shared one IndexedDB audio record, and prepared browser audio in 193 ms. These are local smoke measurements, not guarantees for other devices or large song packs. Add `?profile=1` to the web URL to log library-ready time and a 300-frame gameplay sample in the browser console.

### Shared real-song test fixture

The supplied `2598108 Jane Remover - goldfish.osz` is a useful cross-platform comparison fixture; it is not bundled or redistributed with this repository. It contains one native osu!taiko `Mode: 1` chart (`goldfish`, difficulty `fear`) and `audio.ogg` (Ogg/Vorbis). The app's import parser accepted the archive with no warnings and produced 216 red/blue tap notes. The first note is at 20,818 ms and the last at 144,028 ms, so allow for a long intro when checking playback. The audio payload is 1,478,790 bytes.

With a copy of this archive, import it on web and each mobile rebuild. Confirm the library shows one 216-note difficulty, open it, use **Start song** on web, then compare note timing and judgments through the same audio. Pause, resume, retry, adjust the offset, and refresh/restart to check persistence. These last UI and persistence steps are a test procedure, not yet verified results: browser file-picker control failed in this environment, and the browser test runner stalled before executing its storage suite.

The Android debug APK build stopped before compilation because this machine's SDK could not install NDK `28.2.13676358`; Android runtime compatibility has not been smoke-tested on a device.

## Rebuild checklist

1. Implement the normalized chart model and pure osu!/TJA parser tests. Verify negative offsets, BPM/measure changes, large notes, long notes, and rejected formats.
2. Implement private import/storage with audio deduplication and lightweight library summaries. Confirm restart persistence and cleanup after a failed import.
3. Implement audio preparation, explicit start, lead-in, pause/resume/retry, and the judgment engine. Test wrong color, window boundaries, both-hand large taps, rolls, balloons, and accuracy.
4. Render only nearby notes. Compare score and timing against the Flutter prototype using the same chart and audio on each device.
5. Verify missing audio, unsupported audio decoding, corrupt chart/ZIP, storage failure, and browser autoplay recovery. Use a real chart/audio pair supplied for this project after the synthetic fixtures pass.
