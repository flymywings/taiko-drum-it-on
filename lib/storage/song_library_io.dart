import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../chart/chart.dart';
import 'song_library.dart';

SongLibrary createSongLibrary() => FileSongLibrary();

class FileSongLibrary extends SongLibrary {
  Future<Directory> get _root async {
    final support = await getApplicationSupportDirectory();
    final root =
        Directory('${support.path}${Platform.pathSeparator}taiko_songs');
    await root.create(recursive: true);
    return root;
  }

  @override
  Future<List<SongEntry>> load() async {
    final summaries = await loadSummaries();
    final songs = <SongEntry>[];
    for (final summary in summaries) {
      try {
        songs.add(await loadById(summary.id));
      } catch (_) {
        // A damaged import must not hide healthy songs.
      }
    }
    return songs;
  }

  @override
  Future<List<SongSummary>> loadSummaries() async {
    final root = await _root;
    final songs = <SongSummary>[];
    await for (final item in root.list()) {
      if (item is! Directory) continue;
      try {
        final manifest = await _readManifest(item);
        final audioName = manifest['audioFile'] as String;
        if (!await File('${item.path}${Platform.pathSeparator}$audioName')
            .exists()) {
          continue;
        }
        final chart = Map<String, dynamic>.from(manifest['chart'] as Map);
        songs.add(SongSummary(
          id: item.uri.pathSegments.where((s) => s.isNotEmpty).last,
          title: chart['title'] as String,
          difficulty: chart['difficulty'] as String,
          format: chart['format'] as String,
          noteCount: (chart['notes'] as List).length,
        ));
      } catch (_) {
        // A damaged import must not hide healthy songs.
      }
    }
    songs.sort((a, b) => a.title.compareTo(b.title));
    return songs;
  }

  @override
  Future<SongEntry> loadById(String id) async {
    final root = await _root;
    final dir = Directory('${root.path}${Platform.pathSeparator}$id');
    final manifest = await _readManifest(dir);
    final audioName = manifest['audioFile'] as String;
    final audio = File('${dir.path}${Platform.pathSeparator}$audioName');
    if (!await audio.exists()) throw StateError('Song audio is missing.');
    return SongEntry(
      id: id,
      chart:
          Chart.fromJson(Map<String, dynamic>.from(manifest['chart'] as Map)),
      audioPath: audio.path,
    );
  }

  Future<Map<String, dynamic>> _readManifest(Directory dir) async =>
      jsonDecode(await File('${dir.path}${Platform.pathSeparator}chart.json')
          .readAsString()) as Map<String, dynamic>;

  @override
  Future<SongEntry> save(
      Chart chart, List<int> audioBytes, String extension) async {
    final root = await _root;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final dir = Directory('${root.path}${Platform.pathSeparator}$id');
    await dir.create();
    final audioName = 'audio.$extension';
    final audio = File('${dir.path}${Platform.pathSeparator}$audioName');
    try {
      await audio.writeAsBytes(audioBytes, flush: true);
      await File('${dir.path}${Platform.pathSeparator}chart.json')
          .writeAsString(
              jsonEncode({'audioFile': audioName, 'chart': chart.toJson()}),
              flush: true);
      return SongEntry(id: id, chart: chart, audioPath: audio.path);
    } catch (_) {
      await dir.delete(recursive: true);
      rethrow;
    }
  }

  @override
  Future<void> delete(SongEntry entry) async {
    final root = await _root;
    final dir = Directory('${root.path}${Platform.pathSeparator}${entry.id}');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  @override
  Future<int> loadOffset() async {
    final root = await _root;
    try {
      final data = jsonDecode(
          await File('${root.path}${Platform.pathSeparator}settings.json')
              .readAsString()) as Map<String, dynamic>;
      return (data['offsetMs'] as num).round().clamp(-200, 200).toInt();
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<void> saveOffset(int value) async {
    final root = await _root;
    await File('${root.path}${Platform.pathSeparator}settings.json')
        .writeAsString(jsonEncode({'offsetMs': value.clamp(-200, 200)}),
            flush: true);
  }
}
