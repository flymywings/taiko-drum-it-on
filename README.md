# Taiko Rhythm Prototype

An offline Flutter rhythm-game prototype for web and Android. It imports native osu!taiko `.osu` charts, TJA `.tja` charts, or `.osz` archives with audio. No songs or commercial game art are included.

The [implementation and React Native handoff](REACT_NATIVE_HANDOFF.md) explains the screens, data model, import pipeline, timing, scoring, and mobile rebuild.

## Run the fast web preview

Use Flutter 3.47.5 or a compatible recent version, Node.js, and PowerShell. From this folder:

```powershell
.\build_web.ps1
node .\serve_web.mjs
```

Open [http://127.0.0.1:8080/](http://127.0.0.1:8080/). Keep the server terminal open. The script uses `C:\src\flutter` on this computer; set `$env:FLUTTER_SDK` to another Flutter SDK directory if yours differs. Re-run the build script after changing Dart source or the import worker, then refresh the page.

This preview is a release build. It is the right mode for judging page-load and gameplay performance. A first uncached visit can take longer while the browser fetches Flutter's engine and the app bundle.

For interactive Flutter debugging, compile the import worker first and use the development server:

```powershell
.\build_web.ps1 -WorkerOnly
& "C:\src\flutter\bin\flutter.bat" run -d web-server --web-hostname 127.0.0.1 --web-port 8080
```

The development server loads many separate scripts and is noticeably slower to open. Use only one server on port 8080 at a time.

## Run on Android

Install Flutter, the Android SDK, and an emulator or connected device. Then run:

```powershell
& "C:\src\flutter\bin\flutter.bat" pub get
& "C:\src\flutter\bin\flutter.bat" test
& "C:\src\flutter\bin\flutter.bat" run -d android
```

Use `flutter devices` to find the exact device ID if `android` does not resolve. The Android version continues to use the app's private support directory for songs and settings.

## Play

Select an `.osz` archive containing a native osu!taiko (`Mode: 1`) chart and audio, or select an `.osu` or `.tja` file together with its audio. Supported extensions are MP3, Ogg, WAV, M4A, and FLAC; the browser or device must be able to decode the selected audio. On web, click **Start song** after opening a chart to allow browser audio playback. Use the four colored pads to hit notes, or use **D/F/J/K** for left blue, left red, right red, and right blue. The library's timing-offset control adjusts judgments by −200 to +200 ms.

Imported web songs and the offset are stored in IndexedDB for the current browser origin. Keep the same address and port to see the same library; clearing site data or using a private window removes or isolates it. Android stores imported songs in app-private files. Import progress appears while files are read, parsed, and saved.

## Common problems

- A folder or `index.html` cannot launch the app by double-clicking. Serve the release build over `http://127.0.0.1:8080/`.
- If the library shows an error, use **Retry**. Browser storage may be unavailable in restrictive private modes or when site data is blocked.
- If audio does not start, use the **Tap to play** button. Browser autoplay rules can require another direct tap. Try a browser-supported audio format if decoding fails.
- If a chart reports missing audio, select the chart and audio together. `.osz` archives must include both.
- If code changes do not appear, rebuild and refresh; the release preview serves generated files from `build/web`.
- If an Android build stops before compiling with an NDK error, install the NDK version requested by Flutter in Android SDK Manager. This computer could not fetch NDK `28.2.13676358`, so the Android APK smoke build remains unverified here.

## Checks

```powershell
& "C:\src\flutter\bin\flutter.bat" analyze
& "C:\src\flutter\bin\flutter.bat" test
.\build_web.ps1
```

Add `?profile=1` to the web URL to log the time until the library is usable. During a song it also logs a 300-frame timing sample to the browser console. These measurements are intended for development, not gameplay UI.
