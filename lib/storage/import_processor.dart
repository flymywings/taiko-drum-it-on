import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:charset/charset.dart';

import '../chart/chart.dart';
import '../chart/osu_parser.dart';
import '../chart/tja_parser.dart';

class ImportInput {
  const ImportInput(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

class PreparedSong {
  const PreparedSong(this.chart, this.audioBytes, this.extension);
  final Chart chart;
  final Uint8List audioBytes;
  final String extension;
}

class PreparedImport {
  const PreparedImport(this.songs, this.messages);
  final List<PreparedSong> songs;
  final List<String> messages;
}

class ImportProcessor {
  static const maxInputBytes = 150 * 1024 * 1024;
  static const maxAudioBytes = 80 * 1024 * 1024;
  static const audioExtensions = {'mp3', 'ogg', 'wav', 'm4a', 'flac'};

  PreparedImport process(List<ImportInput> files,
      {void Function(String)? onProgress}) {
    final messages = <String>[];
    final songs = <PreparedSong>[];
    final paired = files.where((f) => _extension(f.name) != 'osz').toList();
    for (final file in files) {
      if (_extension(file.name) != 'osz') continue;
      onProgress?.call('Unpacking ${file.name}…');
      try {
        final report = _importArchive(file, onProgress: onProgress);
        songs.addAll(report.songs);
        messages.addAll(report.messages);
      } catch (error) {
        messages.add('${file.name}: $error');
      }
    }
    if (paired.isNotEmpty) {
      final report = _importPairs(paired, onProgress: onProgress);
      songs.addAll(report.songs);
      messages.addAll(report.messages);
    }
    return PreparedImport(songs, messages);
  }

  PreparedImport _importArchive(ImportInput file,
      {void Function(String)? onProgress}) {
    final archive = ZipDecoder().decodeBytes(file.bytes, verify: true);
    if (archive.files.length > 500) {
      throw const ChartFormatException('Archive has too many files.');
    }
    final entries = <ImportInput>[];
    var unpackedBytes = 0;
    for (final item in archive.files) {
      if (!item.isFile || item.isSymbolicLink) continue;
      final ext = _extension(item.name);
      if (ext != 'osu' && ext != 'tja' && !audioExtensions.contains(ext)) {
        continue;
      }
      if (item.size > maxAudioBytes) {
        throw const ChartFormatException(
            'Archive contains an oversized chart or audio file.');
      }
      unpackedBytes += item.size;
      if (unpackedBytes > maxInputBytes) {
        throw const ChartFormatException(
            'Archive expands beyond the import size limit.');
      }
      final bytes = item.readBytes();
      if (bytes != null) entries.add(ImportInput(item.name, bytes));
    }
    return _importPairs(entries, onProgress: onProgress);
  }

  PreparedImport _importPairs(List<ImportInput> files,
      {void Function(String)? onProgress}) {
    final songs = <PreparedSong>[];
    final messages = <String>[];
    final audioFiles = files
        .where((f) => audioExtensions.contains(_extension(f.name)))
        .toList();
    for (final file in files) {
      final ext = _extension(file.name);
      if (ext != 'osu' && ext != 'tja') continue;
      onProgress?.call('Parsing ${file.name}…');
      try {
        final source = _decodeText(file.bytes);
        final charts = ext == 'osu'
            ? [OsuParser().parse(source)]
            : TjaParser().parse(source);
        for (final chart in charts) {
          final audio = _findAudio(chart.audioFileName, file.name, audioFiles);
          if (audio == null) {
            messages.add(
                '${file.name} (${chart.difficulty}): audio missing. Select the chart and audio together.');
            continue;
          }
          if (audio.bytes.length > maxAudioBytes) {
            messages.add('${file.name}: audio is too large.');
            continue;
          }
          songs.add(PreparedSong(chart, audio.bytes, _extension(audio.name)));
          for (final warning in chart.warnings) {
            messages.add('${chart.title} (${chart.difficulty}): $warning');
          }
        }
      } catch (error) {
        messages.add('${file.name}: $error');
      }
    }
    if (songs.isEmpty && messages.isEmpty) {
      messages.add('No .osu or .tja chart was selected.');
    }
    return PreparedImport(songs, messages);
  }

  ImportInput? _findAudio(
      String reference, String chartName, List<ImportInput> audioFiles) {
    final normalized = reference.replaceAll('\\', '/').toLowerCase();
    final basename = normalized.split('/').last;
    final chartDir = chartName.replaceAll('\\', '/').split('/')..removeLast();
    final relative = [...chartDir, normalized].join('/').toLowerCase();
    for (final audio in audioFiles) {
      final name = audio.name.replaceAll('\\', '/').toLowerCase();
      if (name == relative ||
          name == normalized ||
          name.split('/').last == basename) {
        return audio;
      }
    }
    return audioFiles.length == 1 ? audioFiles.first : null;
  }

  String _decodeText(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return shiftJis.decode(bytes);
    }
  }

  String _extension(String name) {
    final base = name.replaceAll('\\', '/').split('/').last;
    final dot = base.lastIndexOf('.');
    return dot < 0 ? '' : base.substring(dot + 1).toLowerCase();
  }
}
