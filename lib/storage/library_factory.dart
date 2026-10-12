import 'song_library.dart';
import 'song_library_io.dart'
    if (dart.library.js_interop) 'song_library_web.dart' as platform;

SongLibrary createSongLibrary() => platform.createSongLibrary();
