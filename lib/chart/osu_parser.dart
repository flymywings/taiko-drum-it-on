import 'chart.dart';

class _TimingPoint {
  const _TimingPoint(this.time, this.beatLength, this.uninherited);
  final double time;
  final double beatLength;
  final bool uninherited;
}

class OsuParser {
  Chart parse(String source) {
    final sections = <String, List<String>>{};
    var section = '';
    for (final raw
        in source.replaceFirst('\uFEFF', '').split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('//')) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1);
        sections.putIfAbsent(section, () => []);
      } else {
        sections.putIfAbsent(section, () => []).add(line);
      }
    }
    final general = _properties(sections['General']);
    if (general['Mode'] != '1') {
      throw const ChartFormatException(
        'Only native osu!taiko (Mode: 1) charts are supported.',
      );
    }
    final audio = general['AudioFilename']?.trim() ?? '';
    if (audio.isEmpty) {
      throw const ChartFormatException('Chart has no AudioFilename.');
    }
    final metadata = _properties(sections['Metadata']);
    final difficulty = _properties(sections['Difficulty']);
    final sliderMultiplier =
        double.tryParse(difficulty['SliderMultiplier'] ?? '') ?? 1.4;
    if (sliderMultiplier <= 0) {
      throw const ChartFormatException('Invalid slider multiplier.');
    }

    final timing = <_TimingPoint>[];
    for (final line in sections['TimingPoints'] ?? const <String>[]) {
      final fields = line.split(',');
      if (fields.length < 2) continue;
      final time = double.tryParse(fields[0]);
      final beat = double.tryParse(fields[1]);
      if (time == null || beat == null) continue;
      timing.add(
        _TimingPoint(time, beat, fields.length < 7 || fields[6] == '1'),
      );
    }
    timing.sort((a, b) => a.time.compareTo(b.time));

    final notes = <ChartNote>[];
    for (final line in sections['HitObjects'] ?? const <String>[]) {
      final fields = line.split(',');
      if (fields.length < 5) continue;
      final time = int.tryParse(fields[2]);
      final type = int.tryParse(fields[3]);
      final sound = int.tryParse(fields[4]);
      if (time == null || type == null || sound == null) continue;
      if ((type & 1) != 0) {
        notes.add(
          ChartNote(
            timeMs: time,
            kind: (sound & 10) != 0 ? NoteKind.ka : NoteKind.don,
            large: (sound & 4) != 0,
          ),
        );
      } else if ((type & 2) != 0 && fields.length >= 8) {
        final repeats = int.tryParse(fields[6]);
        final length = double.tryParse(fields[7]);
        if (repeats == null || length == null || repeats < 1 || length <= 0) {
          continue;
        }
        var beat = 500.0;
        var velocity = 1.0;
        for (final point in timing) {
          if (point.time > time) break;
          if (point.uninherited && point.beatLength > 0) {
            beat = point.beatLength;
            velocity = 1;
          } else if (!point.uninherited && point.beatLength < 0) {
            velocity = -100 / point.beatLength;
          }
        }
        final duration =
            (length * repeats * beat / (100 * sliderMultiplier * velocity))
                .round();
        if (duration > 0) {
          notes.add(
            ChartNote(
              timeMs: time,
              endMs: time + duration,
              kind: NoteKind.roll,
            ),
          );
        }
      } else if ((type & 8) != 0 && fields.length >= 6) {
        final end = int.tryParse(fields[5]);
        if (end != null && end > time) {
          notes.add(
            ChartNote(
              timeMs: time,
              endMs: end,
              kind: NoteKind.balloon,
              requiredHits: ((end - time) / 100).ceil(),
            ),
          );
        }
      }
    }
    if (notes.isEmpty) {
      throw const ChartFormatException('Chart contains no supported notes.');
    }
    return Chart(
      title: metadata['TitleUnicode']?.isNotEmpty == true
          ? metadata['TitleUnicode']!
          : metadata['Title'] ?? 'Untitled',
      difficulty: metadata['Version'] ?? 'Taiko',
      audioFileName: audio,
      format: 'osu!taiko',
      notes: notes,
    );
  }

  Map<String, String> _properties(List<String>? lines) {
    final result = <String, String>{};
    for (final line in lines ?? const <String>[]) {
      final colon = line.indexOf(':');
      if (colon > 0) {
        result[line.substring(0, colon).trim()] =
            line.substring(colon + 1).trim();
      }
    }
    return result;
  }
}
