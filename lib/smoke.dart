import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'storage/chart_importer.dart';
import 'storage/library_factory.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: _SmokePage()));
}

class _SmokePage extends StatefulWidget {
  const _SmokePage();

  @override
  State<_SmokePage> createState() => _SmokePageState();
}

class _SmokePageState extends State<_SmokePage> {
  String _message = 'Checking import worker and browser storage…';

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final clock = Stopwatch()..start();
    try {
      final library = createSongLibrary();
      final chart = utf8.encode('''
TITLE:Browser smoke
BPM:120
WAVE:smoke.wav
COURSE:Easy
LEVEL:1
#START
1000,
#END
COURSE:Hard
LEVEL:3
#START
1010,
#END
''');
      final bytes = ByteData(44 + 22050 * 2);
      bytes.buffer.asUint8List().setRange(0, 4, 'RIFF'.codeUnits);
      bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
      bytes.buffer.asUint8List().setRange(8, 16, 'WAVEfmt '.codeUnits);
      bytes.setUint32(16, 16, Endian.little);
      bytes.setUint16(20, 1, Endian.little);
      bytes.setUint16(22, 1, Endian.little);
      bytes.setUint32(24, 22050, Endian.little);
      bytes.setUint32(28, 44100, Endian.little);
      bytes.setUint16(32, 2, Endian.little);
      bytes.setUint16(34, 16, Endian.little);
      bytes.buffer.asUint8List().setRange(36, 40, 'data'.codeUnits);
      bytes.setUint32(40, 22050 * 2, Endian.little);
      for (var i = 0; i < 22050; i++) {
        bytes.setInt16(
            44 + i * 2,
            (math.sin(2 * math.pi * 440 * i / 22050) * 1000).round(),
            Endian.little);
      }
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('smoke.tja', chart))
        ..addFile(ArchiveFile.bytes('smoke.wav', bytes.buffer.asUint8List()));
      final pack = ZipEncoder().encodeBytes(archive);
      final report = await ChartImporter(library).importFiles([
        ImportInput('smoke.osz', Uint8List.fromList(pack)),
      ]);
      try {
        if (report.songs.length != 2) {
          throw StateError('Import failed: ${report.messages.join(', ')}');
        }
        final entry = report.songs.first;
        if (entry.audioPath != report.songs.last.audioPath) {
          throw StateError('Imported difficulties did not share audio.');
        }
        final summaries = await createSongLibrary().loadSummaries();
        if (!summaries.any((song) => song.id == entry.id)) {
          throw StateError('Saved song was not found after reopening storage.');
        }
        final loaded = await createSongLibrary().loadById(entry.id);
        final source = await library.prepareAudio(loaded);
        try {
          final player = AudioPlayer();
          try {
            await player.setUrl(source.source);
          } finally {
            await player.dispose();
          }
        } finally {
          source.release?.call();
        }
      } finally {
        for (final entry in report.songs) {
          await library.delete(entry);
        }
      }
      clock.stop();
      if (mounted) {
        setState(() => _message =
            'PASS: ZIP worker, two shared-audio charts, IndexedDB, and audio (${clock.elapsedMilliseconds} ms)');
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'FAIL: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(child: Text(_message, textAlign: TextAlign.center)),
      );
}
