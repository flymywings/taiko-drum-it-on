import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taiko_rhythm_proto/chart/chart.dart';
import 'package:taiko_rhythm_proto/storage/chart_importer.dart';
import 'package:taiko_rhythm_proto/storage/song_library.dart';

class _MemoryLibrary extends SongLibrary {
  final saved = <SongEntry>[];

  @override
  Future<SongEntry> save(
      Chart chart, List<int> audioBytes, String extension) async {
    final entry = SongEntry(
      id: '${saved.length}',
      chart: chart,
      audioPath: 'memory.$extension',
    );
    saved.add(entry);
    return entry;
  }
}

const _osu = '''
[General]
AudioFilename: song.mp3
Mode: 1
[Metadata]
Title: Imported
Version: Normal
[HitObjects]
256,192,1000,1,0
''';

void main() {
  test('paired chart and audio import together', () async {
    final library = _MemoryLibrary();
    final report = await ChartImporter(library).importFiles([
      ImportInput('map.osu', Uint8List.fromList(utf8.encode(_osu))),
      ImportInput('song.mp3', Uint8List.fromList([1, 2, 3])),
    ]);
    expect(report.songs.length, 1);
    expect(report.songs.single.chart.title, 'Imported');
    expect(report.messages, isEmpty);
  });

  test('osz archive matches audio in the same folder', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('Pack/map.osu', utf8.encode(_osu)))
      ..addFile(ArchiveFile.bytes('Pack/song.mp3', [1, 2, 3]));
    final library = _MemoryLibrary();
    final report = await ChartImporter(library).importFiles([
      ImportInput('pack.osz', ZipEncoder().encodeBytes(archive)),
    ]);
    expect(report.songs.length, 1);
    expect(report.messages, isEmpty);
  });

  test('missing audio is reported without saving a broken song', () async {
    final library = _MemoryLibrary();
    final report = await ChartImporter(library).importFiles([
      ImportInput('map.osu', Uint8List.fromList(utf8.encode(_osu))),
    ]);
    expect(report.songs, isEmpty);
    expect(report.messages.single, contains('audio missing'));
    expect(library.saved, isEmpty);
  });

  test('Shift-JIS TJA title survives import', () async {
    final library = _MemoryLibrary();
    final tja = '''
TITLE:太鼓
BPM:120
WAVE:song.mp3
#START
1000,
#END
''';
    final report = await ChartImporter(library).importFiles([
      ImportInput('map.tja', Uint8List.fromList(shiftJis.encode(tja))),
      ImportInput('song.mp3', Uint8List.fromList([1, 2, 3])),
    ]);
    expect(report.songs.single.chart.title, '太鼓');
  });
}
