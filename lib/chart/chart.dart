enum NoteKind { don, ka, roll, balloon }

class ChartNote {
  const ChartNote({
    required this.timeMs,
    required this.kind,
    this.endMs,
    this.large = false,
    this.requiredHits = 0,
  });

  final int timeMs;
  final int? endMs;
  final NoteKind kind;
  final bool large;
  final int requiredHits;

  bool get isLong => kind == NoteKind.roll || kind == NoteKind.balloon;

  Map<String, Object?> toJson() => {
        'timeMs': timeMs,
        'endMs': endMs,
        'kind': kind.name,
        'large': large,
        'requiredHits': requiredHits,
      };

  factory ChartNote.fromJson(Map<String, dynamic> json) => ChartNote(
        timeMs: json['timeMs'] as int,
        endMs: json['endMs'] as int?,
        kind: NoteKind.values.byName(json['kind'] as String),
        large: json['large'] as bool? ?? false,
        requiredHits: json['requiredHits'] as int? ?? 0,
      );
}

class Chart {
  Chart({
    required this.title,
    required this.difficulty,
    required this.audioFileName,
    required this.format,
    required List<ChartNote> notes,
    List<String> warnings = const [],
  })  : notes = List.unmodifiable(
          notes..sort((a, b) => a.timeMs.compareTo(b.timeMs)),
        ),
        warnings = List.unmodifiable(warnings);

  final String title;
  final String difficulty;
  final String audioFileName;
  final String format;
  final List<ChartNote> notes;
  final List<String> warnings;

  Map<String, Object?> toJson() => {
        'title': title,
        'difficulty': difficulty,
        'audioFileName': audioFileName,
        'format': format,
        'notes': notes.map((n) => n.toJson()).toList(),
        'warnings': warnings,
      };

  factory Chart.fromJson(Map<String, dynamic> json) => Chart(
        title: json['title'] as String,
        difficulty: json['difficulty'] as String,
        audioFileName: json['audioFileName'] as String,
        format: json['format'] as String,
        notes: (json['notes'] as List)
            .map((n) => ChartNote.fromJson(Map<String, dynamic>.from(n as Map)))
            .toList(),
        warnings: (json['warnings'] as List? ?? []).cast<String>(),
      );
}

class ChartFormatException implements Exception {
  const ChartFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}
