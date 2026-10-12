import '../chart/chart.dart';

class SongSummary {
  const SongSummary(
      {required this.id,
      required this.title,
      required this.difficulty,
      required this.format,
      required this.noteCount});

  final String id;
  final String title;
  final String difficulty;
  final String format;
  final int noteCount;

  factory SongSummary.fromEntry(SongEntry entry) => SongSummary(
        id: entry.id,
        title: entry.chart.title,
        difficulty: entry.chart.difficulty,
        format: entry.chart.format,
        noteCount: entry.chart.notes.length,
      );
}

class SongEntry {
  const SongEntry(
      {required this.id, required this.chart, required this.audioPath});

  final String id;
  final Chart chart;
  // Filesystem path on Android; audio record key on web.
  final String audioPath;
}

class PlaybackAudio {
  const PlaybackAudio(this.source, {required this.isFile, this.release});

  final String source;
  final bool isFile;
  final void Function()? release;
}

abstract class SongLibrary {
  Future<List<SongEntry>> load() async => throw UnimplementedError();

  Future<List<SongSummary>> loadSummaries() async =>
      (await load()).map(SongSummary.fromEntry).toList();

  Future<SongEntry> loadById(String id) async =>
      (await load()).firstWhere((song) => song.id == id);

  Future<SongEntry> save(Chart chart, List<int> audioBytes, String extension);

  Future<void> delete(SongEntry entry) async => throw UnimplementedError();

  Future<int> loadOffset() async => 0;

  Future<void> saveOffset(int value) async => throw UnimplementedError();

  Future<PlaybackAudio> prepareAudio(SongEntry entry) async =>
      PlaybackAudio(entry.audioPath, isFile: true);
}
