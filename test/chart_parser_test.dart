import 'package:flutter_test/flutter_test.dart';
import 'package:taiko_rhythm_proto/chart/chart.dart';
import 'package:taiko_rhythm_proto/chart/osu_parser.dart';
import 'package:taiko_rhythm_proto/chart/tja_parser.dart';

void main() {
  test('osu parser reads native taiko colors, sizes, rolls and balloons', () {
    final chart = OsuParser().parse('''
osu file format v14
[General]
AudioFilename: song.mp3
Mode: 1
[Metadata]
Title: Example
Version: Hard
[Difficulty]
SliderMultiplier: 1.4
[TimingPoints]
0,500,4,1,0,100,1,0
[HitObjects]
256,192,1000,1,0
256,192,1500,1,6
256,192,2000,2,0,B|300:192,1,140
256,192,3000,8,0,3600
''');
    expect(chart.title, 'Example');
    expect(chart.notes.length, 4);
    expect(chart.notes[0].kind, NoteKind.don);
    expect(chart.notes[1].kind, NoteKind.ka);
    expect(chart.notes[1].large, isTrue);
    expect(chart.notes[2].kind, NoteKind.roll);
    expect(chart.notes[2].endMs, 2500);
    expect(chart.notes[3].kind, NoteKind.balloon);
    expect(chart.notes[3].requiredHits, 6);
  });

  test('osu parser rejects standard mode', () {
    expect(
      () => OsuParser().parse('[General]\nMode: 0\nAudioFilename: a.mp3'),
      throwsA(isA<ChartFormatException>()),
    );
  });

  test('TJA parser reads courses, offset, tempo, long notes and warnings', () {
    final charts = TjaParser().parse('''
TITLE:Sample
BPM:120
WAVE:song.ogg
OFFSET:0.5
COURSE:Easy
LEVEL:2
#START
1000,
#END
COURSE:Oni
LEVEL:7
BALLOON:3
#START
#SCROLL 2
7008,
#BPMCHANGE 240
2000,
#END
''');
    expect(charts.length, 2);
    expect(charts[0].notes.single.timeMs, -500);
    expect(charts[1].difficulty, 'Oni · 7');
    expect(charts[1].notes.first.kind, NoteKind.balloon);
    expect(charts[1].notes.first.requiredHits, 3);
    expect(charts[1].notes.first.endMs, 1000);
    expect(charts[1].notes.last.timeMs, 1500);
    expect(charts[1].warnings, contains('Custom scroll effects are ignored.'));
  });

  test('TJA parser rejects branches and broken long notes', () {
    expect(
      () => TjaParser().parse(
        'BPM:120\n#START\n#BRANCHSTART p,50,80\n1000,\n#END',
      ),
      throwsA(isA<ChartFormatException>()),
    );
    expect(
      () => TjaParser().parse('BPM:120\n#START\n5000,\n#END'),
      throwsA(isA<ChartFormatException>()),
    );
  });

  test('TJA commands before an empty measure affect the next measure', () {
    final chart = TjaParser().parse('''
TITLE:Empty measure
BPM:120
WAVE:song.mp3
#START
#BPMCHANGE 240
,
1000,
#END
''').single;
    expect(chart.notes.single.timeMs, 1000);
  });
}
