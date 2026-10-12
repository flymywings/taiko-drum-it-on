import 'dart:js_interop';
import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';
import 'package:web/web.dart' as web;

import '../chart/chart.dart';
import 'song_library.dart';

SongLibrary createSongLibrary() => BrowserSongLibrary();

class BrowserSongLibrary extends SongLibrary {
  static const _summaries = 'summaries';
  static const _charts = 'charts';
  static const _audio = 'audio';
  static const _settings = 'settings';

  Future<Database>? _opening;
  final Expando<String> _audioKeys = Expando<String>('import audio key');
  int _nextId = 0;

  Future<Database> get _db => _opening ??= idbFactoryNative.open(
        'taiko_rhythm_proto',
        version: 1,
        onUpgradeNeeded: (event) {
          final db = event.database;
          for (final name in [_summaries, _charts, _audio, _settings]) {
            if (!db.objectStoreNames.contains(name)) db.createObjectStore(name);
          }
        },
      ).catchError((Object error) {
        _opening = null;
        throw error;
      });

  String _id() => '${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';

  @override
  Future<List<SongEntry>> load() async {
    final songs = <SongEntry>[];
    for (final summary in await loadSummaries()) {
      try {
        songs.add(await loadById(summary.id));
      } catch (_) {
        // Keep healthy songs visible if one record is damaged.
      }
    }
    return songs;
  }

  @override
  Future<List<SongSummary>> loadSummaries() async {
    final db = await _db;
    final txn = db.transaction(_summaries, idbModeReadOnly);
    final rows = await txn.objectStore(_summaries).getAll();
    await txn.completed;
    final songs = <SongSummary>[];
    for (final row in rows) {
      try {
        final value = Map<String, dynamic>.from(row as Map);
        songs.add(SongSummary(
          id: value['id'] as String,
          title: value['title'] as String,
          difficulty: value['difficulty'] as String,
          format: value['format'] as String,
          noteCount: value['noteCount'] as int,
        ));
      } catch (_) {
        // One broken record must not hide the rest of the library.
      }
    }
    songs.sort((a, b) => a.title.compareTo(b.title));
    return songs;
  }

  @override
  Future<SongEntry> loadById(String id) async {
    final db = await _db;
    final txn = db.transaction([_summaries, _charts], idbModeReadOnly);
    final summaryRequest = txn.objectStore(_summaries).getObject(id);
    final chartRequest = txn.objectStore(_charts).getObject(id);
    final summary = await summaryRequest;
    final chart = await chartRequest;
    await txn.completed;
    if (summary == null || chart == null) throw StateError('Song is missing.');
    final info = Map<String, dynamic>.from(summary as Map);
    return SongEntry(
      id: id,
      chart: Chart.fromJson(Map<String, dynamic>.from(chart as Map)),
      audioPath: info['audioId'] as String,
    );
  }

  @override
  Future<SongEntry> save(
      Chart chart, List<int> audioBytes, String extension) async {
    final db = await _db;
    final id = _id();
    final existingAudioId = _audioKeys[audioBytes];
    final audioId = existingAudioId ?? _id();
    final txn = db.transaction([_summaries, _charts, _audio], idbModeReadWrite);
    if (existingAudioId == null) {
      await txn.objectStore(_audio).put({
        'bytes': Uint8List.fromList(audioBytes),
        'extension': extension,
      }, audioId);
    }
    await txn.objectStore(_charts).put(chart.toJson(), id);
    await txn.objectStore(_summaries).put({
      'id': id,
      'title': chart.title,
      'difficulty': chart.difficulty,
      'format': chart.format,
      'noteCount': chart.notes.length,
      'audioId': audioId,
    }, id);
    await txn.completed;
    _audioKeys[audioBytes] = audioId;
    return SongEntry(id: id, chart: chart, audioPath: audioId);
  }

  @override
  Future<void> delete(SongEntry entry) async {
    final db = await _db;
    final summaries = await loadSummaries();
    // The record itself contains the audio key. Count other references before
    // removing it, so imported difficulties can share one audio record.
    final read = db.transaction(_summaries, idbModeReadOnly);
    final rows = await read.objectStore(_summaries).getAll();
    await read.completed;
    final usedElsewhere = rows.any((row) {
      final value = Map<String, dynamic>.from(row as Map);
      return value['id'] != entry.id && value['audioId'] == entry.audioPath;
    });
    if (!summaries.any((song) => song.id == entry.id)) return;
    final txn = db.transaction([_summaries, _charts, _audio], idbModeReadWrite);
    await txn.objectStore(_summaries).delete(entry.id);
    await txn.objectStore(_charts).delete(entry.id);
    if (!usedElsewhere) await txn.objectStore(_audio).delete(entry.audioPath);
    await txn.completed;
  }

  @override
  Future<int> loadOffset() async {
    final db = await _db;
    final txn = db.transaction(_settings, idbModeReadOnly);
    final value = await txn.objectStore(_settings).getObject('offsetMs');
    await txn.completed;
    return ((value as num?)?.round() ?? 0).clamp(-200, 200).toInt();
  }

  @override
  Future<void> saveOffset(int value) async {
    final db = await _db;
    final txn = db.transaction(_settings, idbModeReadWrite);
    await txn.objectStore(_settings).put(value.clamp(-200, 200), 'offsetMs');
    await txn.completed;
  }

  @override
  Future<PlaybackAudio> prepareAudio(SongEntry entry) async {
    final db = await _db;
    final txn = db.transaction(_audio, idbModeReadOnly);
    final row = await txn.objectStore(_audio).getObject(entry.audioPath);
    await txn.completed;
    if (row == null) throw StateError('Song audio is missing.');
    final value = Map<String, dynamic>.from(row as Map);
    final raw = value['bytes'];
    final bytes =
        raw is Uint8List ? raw : Uint8List.fromList((raw as List).cast<int>());
    final mime = switch (value['extension']) {
      'mp3' => 'audio/mpeg',
      'ogg' => 'audio/ogg',
      'wav' => 'audio/wav',
      'm4a' => 'audio/mp4',
      'flac' => 'audio/flac',
      _ => 'application/octet-stream',
    };
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
    final url = web.URL.createObjectURL(blob);
    return PlaybackAudio(url,
        isFile: false, release: () => web.URL.revokeObjectURL(url));
  }
}
