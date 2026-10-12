import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:taiko_rhythm_proto/chart/chart.dart';
import 'package:taiko_rhythm_proto/storage/song_library_web.dart';

void runBrowserSuite() {
  test('browser library persists summaries, shared audio, and offset',
      () async {
    final library = BrowserSongLibrary();
    final audio = Uint8List.fromList([1, 2, 3, 4]);
    Chart chart(String difficulty) => Chart(
          title: 'Browser fixture',
          difficulty: difficulty,
          audioFileName: 'fixture.wav',
          format: 'test',
          notes: [const ChartNote(timeMs: 1000, kind: NoteKind.don)],
        );

    final first = await library.save(chart('Easy'), audio, 'wav');
    final second = await library.save(chart('Hard'), audio, 'wav');
    expect(first.audioPath, second.audioPath);
    final summaries = await library.loadSummaries();
    expect(
        summaries.where((song) => song.title == 'Browser fixture').length, 2);
    expect((await library.loadById(first.id)).chart.notes.single.timeMs, 1000);
    final source = await library.prepareAudio(first);
    expect(source.isFile, isFalse);
    expect(source.source, startsWith('blob:'));
    source.release?.call();
    await library.saveOffset(35);
    expect(await library.loadOffset(), 35);
    await library.delete(first);
    expect((await library.loadById(second.id)).chart.difficulty, 'Hard');
    await library.delete(second);
  });
}
