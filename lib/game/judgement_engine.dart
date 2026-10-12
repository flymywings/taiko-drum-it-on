import '../chart/chart.dart';

enum HitColor { red, blue }

enum Hand { left, right }

enum NoteResult { pending, perfect, good, miss, completed }

class GameSnapshot {
  const GameSnapshot({
    required this.score,
    required this.combo,
    required this.maxCombo,
    required this.perfect,
    required this.good,
    required this.miss,
    required this.longHits,
  });
  final int score;
  final int combo;
  final int maxCombo;
  final int perfect;
  final int good;
  final int miss;
  final int longHits;

  double get accuracy {
    final total = perfect + good + miss;
    return total == 0 ? 0 : (perfect + good * 0.5) / total;
  }
}

class _LargePending {
  const _LargePending(this.index, this.timeMs, this.hand, this.judgement);
  final int index;
  final int timeMs;
  final Hand hand;
  final NoteResult judgement;
}

class JudgementEngine {
  JudgementEngine(this.chart)
      : results = List.filled(chart.notes.length, NoteResult.pending),
        _longHitCounts = List.filled(chart.notes.length, 0),
        _lastLongHitMs = List.filled(chart.notes.length, -999999),
        finalTimeMs = _lastNoteTime(chart) + missWindowMs + 700;

  static const perfectWindowMs = 40;
  static const goodWindowMs = 90;
  static const missWindowMs = 130;
  static const largeChordWindowMs = 50;

  final Chart chart;
  final List<NoteResult> results;
  final List<int> _longHitCounts;
  final List<int> _lastLongHitMs;
  final List<int> _activeLongIndices = [];
  Iterable<int> get activeLongIndices => _activeLongIndices;
  int _longActivationCursor = 0;
  int _missCursor = 0;
  _LargePending? _largePending;
  int score = 0;
  int combo = 0;
  int maxCombo = 0;
  int perfect = 0;
  int good = 0;
  int miss = 0;
  int longHits = 0;
  String lastJudgement = '';

  GameSnapshot get snapshot => GameSnapshot(
        score: score,
        combo: combo,
        maxCombo: maxCombo,
        perfect: perfect,
        good: good,
        miss: miss,
        longHits: longHits,
      );

  final int finalTimeMs;

  static int _lastNoteTime(Chart chart) {
    var last = 0;
    for (final note in chart.notes) {
      final end = note.endMs ?? note.timeMs;
      if (end > last) last = end;
    }
    return last;
  }

  int _firstNoteAtOrAfter(int timeMs) {
    var low = 0;
    var high = chart.notes.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (chart.notes[middle].timeMs < timeMs) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  void advance(int nowMs) {
    final pending = _largePending;
    if (pending != null && nowMs > pending.timeMs + largeChordWindowMs) {
      _scoreTap(pending.index, pending.judgement, doubled: false);
      _largePending = null;
    }
    while (_longActivationCursor < chart.notes.length &&
        chart.notes[_longActivationCursor].timeMs <= nowMs) {
      final i = _longActivationCursor++;
      if (chart.notes[i].isLong) _activeLongIndices.add(i);
    }
    while (_missCursor < chart.notes.length &&
        chart.notes[_missCursor].timeMs + missWindowMs < nowMs) {
      final i = _missCursor++;
      if (!chart.notes[i].isLong &&
          results[i] == NoteResult.pending &&
          _largePending?.index != i) {
        _scoreTap(i, NoteResult.miss, doubled: false);
      }
    }
    _activeLongIndices.removeWhere((i) {
      final note = chart.notes[i];
      if (nowMs <= note.endMs!) return false;
      if (results[i] == NoteResult.pending) {
        if (note.kind == NoteKind.balloon &&
            _longHitCounts[i] >= note.requiredHits) {
          score += 300;
          lastJudgement = 'Balloon!';
        }
        results[i] = NoteResult.completed;
      }
      return true;
    });
  }

  void tap(HitColor color, Hand hand, int nowMs) {
    advance(nowMs);
    final pending = _largePending;
    if (pending != null) {
      final note = chart.notes[pending.index];
      if (_matches(note, color) &&
          hand != pending.hand &&
          nowMs - pending.timeMs <= largeChordWindowMs) {
        _scoreTap(pending.index, pending.judgement, doubled: true);
        _largePending = null;
        return;
      }
    }

    int? candidate;
    var closest = missWindowMs + 1;
    for (var i = _firstNoteAtOrAfter(nowMs - missWindowMs);
        i < chart.notes.length && chart.notes[i].timeMs <= nowMs + missWindowMs;
        i++) {
      final note = chart.notes[i];
      if (note.isLong ||
          results[i] != NoteResult.pending ||
          _largePending?.index == i) {
        continue;
      }
      final distance = (note.timeMs - nowMs).abs();
      if (distance <= missWindowMs && distance < closest) {
        closest = distance;
        candidate = i;
      }
    }
    if (candidate != null) {
      final note = chart.notes[candidate];
      final judgement = !_matches(note, color)
          ? NoteResult.miss
          : closest <= perfectWindowMs
              ? NoteResult.perfect
              : closest <= goodWindowMs
                  ? NoteResult.good
                  : NoteResult.miss;
      if (note.large && judgement != NoteResult.miss) {
        _largePending = _LargePending(candidate, nowMs, hand, judgement);
      } else {
        _scoreTap(candidate, judgement, doubled: false);
      }
      return;
    }

    for (final i in _activeLongIndices) {
      final note = chart.notes[i];
      if (!note.isLong ||
          results[i] != NoteResult.pending ||
          nowMs < note.timeMs ||
          nowMs > note.endMs!) {
        continue;
      }
      if (nowMs - _lastLongHitMs[i] < 45) return;
      _lastLongHitMs[i] = nowMs;
      _longHitCounts[i]++;
      longHits++;
      score += note.kind == NoteKind.roll ? (note.large ? 20 : 10) : 10;
      lastJudgement = note.kind == NoteKind.roll
          ? 'Drumroll ${_longHitCounts[i]}'
          : 'Balloon ${_longHitCounts[i]}/${note.requiredHits}';
      return;
    }
  }

  bool _matches(ChartNote note, HitColor color) =>
      (note.kind == NoteKind.don && color == HitColor.red) ||
      (note.kind == NoteKind.ka && color == HitColor.blue);

  void _scoreTap(int index, NoteResult result, {required bool doubled}) {
    results[index] = result;
    switch (result) {
      case NoteResult.perfect:
        perfect++;
        combo++;
        score += doubled ? 600 : 300;
        lastJudgement = doubled ? 'Perfect x2' : 'Perfect';
        break;
      case NoteResult.good:
        good++;
        combo++;
        score += doubled ? 300 : 150;
        lastJudgement = doubled ? 'Good x2' : 'Good';
        break;
      case NoteResult.miss:
        miss++;
        combo = 0;
        lastJudgement = 'Miss';
        break;
      case NoteResult.pending:
      case NoteResult.completed:
        break;
    }
    if (combo > maxCombo) maxCombo = combo;
  }
}
