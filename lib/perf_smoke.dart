import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'chart/chart.dart';
import 'main.dart' show GamePage;
import 'storage/song_library.dart';
import 'storage/song_library_web.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: _PerfPage()));
}

class _PerfPage extends StatefulWidget {
  const _PerfPage();

  @override
  State<_PerfPage> createState() => _PerfPageState();
}

class _PerfPageState extends State<_PerfPage> {
  final BrowserSongLibrary _library = BrowserSongLibrary();
  SongEntry? _song;
  String _status = 'Preparing 2,000 notes…';

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final notes = List.generate(
          2000,
          (i) => ChartNote(
                timeMs: 2000 + i * 20,
                kind: i.isEven ? NoteKind.don : NoteKind.ka,
              ));
      final chart = Chart(
          title: '2,000 note profile',
          difficulty: 'Stress',
          audioFileName: 'silence.wav',
          format: 'synthetic',
          notes: notes);
      const sampleRate = 8000;
      const seconds = 45;
      final wav = ByteData(44 + sampleRate * seconds * 2);
      wav.buffer.asUint8List().setRange(0, 4, 'RIFF'.codeUnits);
      wav.setUint32(4, wav.lengthInBytes - 8, Endian.little);
      wav.buffer.asUint8List().setRange(8, 16, 'WAVEfmt '.codeUnits);
      wav.setUint32(16, 16, Endian.little);
      wav.setUint16(20, 1, Endian.little);
      wav.setUint16(22, 1, Endian.little);
      wav.setUint32(24, sampleRate, Endian.little);
      wav.setUint32(28, sampleRate * 2, Endian.little);
      wav.setUint16(32, 2, Endian.little);
      wav.setUint16(34, 16, Endian.little);
      wav.buffer.asUint8List().setRange(36, 40, 'data'.codeUnits);
      wav.setUint32(40, sampleRate * seconds * 2, Endian.little);
      final song = await _library.save(chart, wav.buffer.asUint8List(), 'wav');
      if (mounted) setState(() => _song = song);
    } catch (error) {
      if (mounted) setState(() => _status = 'FAIL: $error');
    }
  }

  Future<void> _finish() async {
    final song = _song;
    if (song == null) return;
    setState(() {
      _song = null;
      _status = 'Profile finished; cleaning up…';
    });
    await _library.delete(song);
    if (mounted) {
      setState(() => _status = 'Profile complete; test song removed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final song = _song;
    if (song == null) {
      return Scaffold(body: Center(child: Text(_status)));
    }
    return Stack(children: [
      GamePage(song: song, library: _library, offsetMs: 0),
      Positioned(
          top: 52,
          right: 12,
          child: FilledButton(
              onPressed: _finish, child: const Text('Finish profile'))),
    ]);
  }
}
