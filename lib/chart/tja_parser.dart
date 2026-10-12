import 'chart.dart';

class _MeasurePart {
  const _MeasurePart(this.value, {this.command = false});
  final String value;
  final bool command;
}

class _CourseBuilder {
  _CourseBuilder(this.headers);

  final Map<String, String> headers;
  final List<_MeasurePart> measure = [];
  final List<ChartNote> notes = [];
  final Set<String> warnings = {};
  ChartNote? activeLong;
  int balloonIndex = 0;
  late final List<int> balloonCounts = (headers['BALLOON'] ?? '')
      .split(',')
      .map((value) => int.tryParse(value.trim()) ?? 0)
      .toList();
  late double bpm = _positive(headers['BPM'] ?? '120', 'BPM');
  late double measureRatio = 1;
  late double cursorMs = -_number(headers['OFFSET'] ?? '0', 'OFFSET') * 1000;

  void addNotation(String line) {
    for (final rune in line.runes) {
      final char = String.fromCharCode(rune);
      if (char == ',') {
        flushMeasure();
      } else if (RegExp(r'[0-9]').hasMatch(char)) {
        measure.add(_MeasurePart(char));
      } else if (!RegExp(r'\s').hasMatch(char)) {
        throw ChartFormatException('Unsupported TJA note "$char".');
      }
    }
  }

  void addCommand(String command) {
    final name = command.split(RegExp(r'\s+')).first.toUpperCase();
    if (name == '#BRANCHSTART' ||
        name == '#N' ||
        name == '#E' ||
        name == '#M' ||
        name == '#BRANCHEND') {
      throw const ChartFormatException(
        'Branching TJA charts are not supported yet.',
      );
    }
    if (name == '#SCROLL' || name == '#HEADSCROLL') {
      warnings.add('Custom scroll effects are ignored.');
    } else if (name == '#GOGOSTART' || name == '#GOGOEND') {
      warnings.add('Go-Go scoring effects are ignored.');
    } else if (name != '#BPMCHANGE' &&
        name != '#MEASURE' &&
        name != '#DELAY' &&
        name != '#BARLINEON' &&
        name != '#BARLINEOFF') {
      warnings.add('$name is ignored.');
    }
    measure.add(_MeasurePart(command, command: true));
  }

  void flushMeasure() {
    final slots = measure.where((part) => !part.command).length;
    for (final part in measure) {
      if (part.command) {
        final bits = part.value.split(RegExp(r'\s+'));
        final name = bits.first.toUpperCase();
        final arg = bits.length > 1 ? bits.sublist(1).join(' ') : '';
        switch (name) {
          case '#BPMCHANGE':
            bpm = _positive(arg, '#BPMCHANGE');
            break;
          case '#MEASURE':
            final pair = arg.split('/');
            if (pair.length != 2) {
              throw const ChartFormatException('Invalid #MEASURE value.');
            }
            measureRatio =
                _positive(pair[0], '#MEASURE') / _positive(pair[1], '#MEASURE');
            break;
          case '#DELAY':
            cursorMs += _number(arg, '#DELAY') * 1000;
            break;
        }
        continue;
      }
      final time = cursorMs.round();
      switch (part.value) {
        case '1':
        case '2':
        case '3':
        case '4':
          notes.add(
            ChartNote(
              timeMs: time,
              kind: part.value == '1' || part.value == '3'
                  ? NoteKind.don
                  : NoteKind.ka,
              large: part.value == '3' || part.value == '4',
            ),
          );
          break;
        case '5':
        case '6':
        case '7':
        case '9':
          if (activeLong != null) {
            throw const ChartFormatException(
              'A long note starts before the previous one ends.',
            );
          }
          final balloon = part.value == '7' || part.value == '9';
          final required = balloon && balloonIndex < balloonCounts.length
              ? balloonCounts[balloonIndex]
              : 0;
          if (balloon) balloonIndex++;
          activeLong = ChartNote(
            timeMs: time,
            kind: balloon ? NoteKind.balloon : NoteKind.roll,
            large: part.value == '6' || part.value == '9',
            requiredHits: balloon ? (required > 0 ? required : 5) : 0,
          );
          break;
        case '8':
          final start = activeLong;
          if (start == null || time <= start.timeMs) {
            throw const ChartFormatException('Long note has no valid start.');
          }
          notes.add(
            ChartNote(
              timeMs: start.timeMs,
              endMs: time,
              kind: start.kind,
              large: start.large,
              requiredHits: start.requiredHits,
            ),
          );
          activeLong = null;
          break;
        case '0':
          break;
      }
      cursorMs += 60000 * 4 * measureRatio / bpm / slots;
    }
    if (slots == 0) {
      cursorMs += 60000 * 4 * measureRatio / bpm;
    }
    measure.clear();
  }

  Chart finish() {
    if (measure.isNotEmpty) {
      throw const ChartFormatException('TJA measure is missing a comma.');
    }
    if (activeLong != null) {
      throw const ChartFormatException('TJA long note is missing its end (8).');
    }
    if (notes.isEmpty) {
      throw const ChartFormatException(
        'TJA course contains no supported notes.',
      );
    }
    final course = headers['COURSE'] ?? 'Oni';
    final level = headers['LEVEL'];
    return Chart(
      title: headers['TITLE'] ?? 'Untitled',
      difficulty: level == null ? course : '$course · $level',
      audioFileName: headers['WAVE'] ?? '',
      format: 'TJA',
      notes: notes,
      warnings: warnings.toList(),
    );
  }

  static double _number(String text, String field) {
    final number = double.tryParse(text.trim());
    if (number == null || !number.isFinite) {
      throw ChartFormatException('Invalid $field value.');
    }
    return number;
  }

  static double _positive(String text, String field) {
    final number = _number(text, field);
    if (number <= 0) throw ChartFormatException('$field must be positive.');
    return number;
  }
}

class TjaParser {
  List<Chart> parse(String source) {
    final global = <String, String>{};
    var local = <String, String>{};
    final charts = <Chart>[];
    _CourseBuilder? course;
    var inCourse = false;
    for (final raw
        in source.replaceFirst('\uFEFF', '').split(RegExp(r'\r?\n'))) {
      final line = raw.split('//').first.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        final command = line.split(RegExp(r'\s+')).first.toUpperCase();
        if (command == '#START') {
          if (inCourse) {
            throw const ChartFormatException('Nested #START in TJA.');
          }
          if (line.toUpperCase().contains('P2')) {
            throw const ChartFormatException(
              'Two-player TJA courses are not supported.',
            );
          }
          course = _CourseBuilder({...global, ...local});
          inCourse = true;
        } else if (command == '#END') {
          if (!inCourse || course == null) {
            throw const ChartFormatException('#END without #START in TJA.');
          }
          charts.add(course.finish());
          course = null;
          inCourse = false;
          local = {};
        } else if (inCourse) {
          course!.addCommand(line);
        }
        continue;
      }
      if (inCourse) {
        course!.addNotation(line);
      } else {
        final colon = line.indexOf(':');
        if (colon <= 0) continue;
        final key = line.substring(0, colon).trim().toUpperCase();
        final value = line.substring(colon + 1).trim();
        if (key == 'COURSE') {
          local = {'COURSE': value};
        } else if (local.isEmpty) {
          global[key] = value;
        } else {
          local[key] = value;
        }
      }
    }
    if (inCourse) {
      throw const ChartFormatException('TJA course is missing #END.');
    }
    if (charts.isEmpty) {
      throw const ChartFormatException('No TJA courses found.');
    }
    return charts;
  }
}
