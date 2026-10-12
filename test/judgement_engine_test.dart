import 'package:flutter_test/flutter_test.dart';
import 'package:taiko_rhythm_proto/chart/chart.dart';
import 'package:taiko_rhythm_proto/game/judgement_engine.dart';

Chart testChart(List<ChartNote> notes) => Chart(
      title: 'Test',
      difficulty: 'Test',
      audioFileName: 'test.wav',
      format: 'test',
      notes: notes,
    );

void main() {
  test('tap timing and wrong color produce stable judgments', () {
    final engine = JudgementEngine(
      testChart([
        const ChartNote(timeMs: 1000, kind: NoteKind.don),
        const ChartNote(timeMs: 1500, kind: NoteKind.ka),
        const ChartNote(timeMs: 2000, kind: NoteKind.don),
      ]),
    );
    engine.tap(HitColor.red, Hand.left, 1020);
    engine.tap(HitColor.blue, Hand.right, 1560);
    engine.tap(HitColor.blue, Hand.left, 2000);
    expect(engine.snapshot.perfect, 1);
    expect(engine.snapshot.good, 1);
    expect(engine.snapshot.miss, 1);
    expect(engine.snapshot.combo, 0);
    expect(engine.snapshot.score, 450);
    expect(engine.snapshot.accuracy, closeTo(0.5, 0.001));
  });

  test('large note doubles score for two hands, otherwise scores once', () {
    final engine = JudgementEngine(
      testChart([
        const ChartNote(timeMs: 1000, kind: NoteKind.don, large: true),
        const ChartNote(timeMs: 2000, kind: NoteKind.ka, large: true),
      ]),
    );
    engine.tap(HitColor.red, Hand.left, 1000);
    engine.tap(HitColor.red, Hand.right, 1030);
    engine.tap(HitColor.blue, Hand.left, 2000);
    engine.advance(2051);
    expect(engine.snapshot.score, 900);
    expect(engine.snapshot.perfect, 2);
  });

  test('misses expire, while long notes award hits and balloon completion', () {
    final engine = JudgementEngine(
      testChart([
        const ChartNote(timeMs: 1000, kind: NoteKind.don),
        const ChartNote(timeMs: 1200, endMs: 1600, kind: NoteKind.roll),
        const ChartNote(
          timeMs: 1800,
          endMs: 2300,
          kind: NoteKind.balloon,
          requiredHits: 2,
        ),
      ]),
    );
    engine.advance(1131);
    engine.tap(HitColor.red, Hand.left, 1300);
    engine.tap(HitColor.blue, Hand.right, 1360);
    engine.tap(HitColor.red, Hand.left, 1900);
    engine.tap(HitColor.blue, Hand.right, 1960);
    engine.advance(2301);
    expect(engine.snapshot.miss, 1);
    expect(engine.snapshot.longHits, 4);
    expect(engine.snapshot.score, 340);
    expect(engine.snapshot.combo, 0);
  });
}
