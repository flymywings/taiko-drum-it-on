import 'package:file_picker/file_picker.dart';

import 'import_processor.dart';
import 'import_processor_io.dart'
    if (dart.library.js_interop) 'import_processor_web.dart' as platform;
import 'song_library.dart';

export 'import_processor.dart' show ImportInput;

class ImportReport {
  const ImportReport(this.songs, this.messages);
  final List<SongEntry> songs;
  final List<String> messages;
}

class ChartImporter {
  ChartImporter(this.library);
  final SongLibrary library;

  Future<ImportReport> pickAndImport(
      {void Function(String)? onProgress}) async {
    final chosen = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'osz',
        'osu',
        'tja',
        ...ImportProcessor.audioExtensions,
      ],
      dialogTitle: 'Choose .osz or chart and audio files',
    );
    if (chosen.isEmpty) return const ImportReport([], []);
    final messages = <String>[];
    final files = <ImportInput>[];
    for (final file in chosen) {
      onProgress?.call('Reading ${file.name}…');
      final length = await file.length();
      if (length != null && length > ImportProcessor.maxInputBytes) {
        messages.add('${file.name}: file is too large.');
        continue;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > ImportProcessor.maxInputBytes) {
        messages.add('${file.name}: file is too large.');
        continue;
      }
      files.add(ImportInput(file.name, bytes));
    }
    final report = await importFiles(files, onProgress: onProgress);
    return ImportReport(report.songs, [...messages, ...report.messages]);
  }

  Future<ImportReport> importFiles(List<ImportInput> files,
      {void Function(String)? onProgress}) async {
    final prepared =
        await platform.processImports(files, onProgress: onProgress);
    final imported = <SongEntry>[];
    final messages = [...prepared.messages];
    for (final song in prepared.songs) {
      onProgress
          ?.call('Saving ${song.chart.title} (${song.chart.difficulty})…');
      try {
        imported.add(
            await library.save(song.chart, song.audioBytes, song.extension));
      } catch (error) {
        messages.add('${song.chart.title} (${song.chart.difficulty}): $error');
      }
    }
    return ImportReport(imported, messages);
  }
}
