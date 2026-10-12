import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import 'chart/chart.dart';
import 'game/judgement_engine.dart';
import 'game/key_bindings.dart';
import 'page_clock_io.dart' if (dart.library.js_interop) 'page_clock_web.dart'
    as page_clock;
import 'storage/chart_importer.dart';
import 'storage/library_factory.dart';
import 'storage/song_library.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
  runApp(const TaikoApp());
}

final bool _profileWeb =
    kIsWeb && Uri.base.queryParameters.containsKey('profile');

class TaikoApp extends StatelessWidget {
  const TaikoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Taiko Rhythm Prototype',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: Colors.deepOrange,
          useMaterial3: true,
        ),
        home: const LibraryPage(),
      );
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final SongLibrary _library = createSongLibrary();
  List<SongSummary> _songs = [];
  bool _busy = true;
  int _offsetMs = 0;
  String? _loadError;
  String _progress = 'Loading library…';
  bool _reportedFirstReady = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final loaded = await Future.wait<Object>([
        _library.loadSummaries(),
        _library.loadOffset(),
      ]);
      if (mounted) {
        setState(() {
          _songs = loaded[0] as List<SongSummary>;
          _offsetMs = loaded[1] as int;
          _loadError = null;
          _busy = false;
        });
        if (_profileWeb && !_reportedFirstReady) {
          _reportedFirstReady = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            debugPrint('WEB_LIBRARY_READY_MS: ${page_clock.nowMs().round()}');
          });
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = 'Library could not load: $error';
          _busy = false;
        });
      }
    }
  }

  Future<void> _openSong(SongSummary summary) async {
    setState(() {
      _busy = true;
      _progress = 'Opening ${summary.title}…';
    });
    try {
      final song = await _library.loadById(summary.id);
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) =>
                GamePage(song: song, library: _library, offsetMs: _offsetMs),
          ));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open song: $error')),
      );
    }
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _progress = 'Importing…';
    });
    try {
      final report = await ChartImporter(_library).pickAndImport(
        onProgress: (message) {
          if (mounted) setState(() => _progress = message);
        },
      );
      await _reload();
      if (!mounted) return;
      final message = '${report.songs.length} chart(s) imported.';
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import complete'),
          content: SingleChildScrollView(
            child: Text([message, ...report.messages].join('\n')),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Import failed: $error')));
      }
    }
  }

  Future<void> _editOffset() async {
    var value = _offsetMs.toDouble();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Timing offset'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Move judgments later or earlier to match what you hear.',
                ),
                Slider(
                  value: value,
                  min: -200,
                  max: 200,
                  divisions: 80,
                  label: '${value.round()} ms',
                  onChanged: (next) => setDialogState(() => value = next),
                ),
                Text('${value.round()} ms'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await _library.saveOffset(value.round());
                if (!mounted) return;
                setState(() => _offsetMs = value.round());
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Taiko Rhythm Prototype'),
          actions: [
            IconButton(
              tooltip: 'Timing offset',
              icon: const Icon(Icons.tune),
              onPressed: _editOffset,
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: _loadError != null
            ? Center(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_loadError!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: () {
                        setState(() {
                          _loadError = null;
                          _busy = true;
                          _progress = 'Loading library…';
                        });
                        _reload();
                      },
                      child: const Text('Retry')),
                ],
              ))
            : _busy
                ? Center(
                    child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(_progress),
                    ],
                  ))
                : _songs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Import an .osz or a .osu/.tja chart with its audio.',
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _import,
                              icon: const Icon(Icons.file_open),
                              label: const Text('Import song'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _songs.length,
                        itemBuilder: (context, index) {
                          final song = _songs[index];
                          return ListTile(
                            leading: const Icon(Icons.music_note),
                            title: Text(song.title),
                            subtitle: Text(
                              '${song.difficulty} · ${song.format} · ${song.noteCount} notes',
                            ),
                            trailing: const Icon(Icons.play_arrow),
                            onTap: () => _openSong(song),
                          );
                        },
                      ),
        floatingActionButton: _songs.isEmpty || _busy
            ? null
            : FloatingActionButton.extended(
                onPressed: _import,
                icon: const Icon(Icons.add),
                label: const Text('Import'),
              ),
      );
}

class GamePage extends StatefulWidget {
  const GamePage(
      {super.key,
      required this.song,
      required this.library,
      required this.offsetMs});
  final SongEntry song;
  final SongLibrary library;
  final int offsetMs;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  final AudioPlayer _player = AudioPlayer();
  final Stopwatch _leadClock = Stopwatch();
  final ValueNotifier<int> _clock = ValueNotifier<int>(-2000);
  final ValueNotifier<int> _hitRevision = ValueNotifier<int>(0);
  Timer? _ticker;
  late JudgementEngine _engine;
  PlaybackAudio? _audioSource;
  int _leadMs = 2000;
  int _nowMs = -2000;
  bool _ready = false;
  bool _started = false;
  bool _paused = false;
  bool _audioStarted = false;
  bool _audioTransitioning = false;
  bool _finished = false;
  String? _error;
  final List<double> _profileFrames = [];
  bool _profilingFrames = false;

  @override
  void initState() {
    super.initState();
    _engine = JudgementEngine(widget.song.chart);
    final first = widget.song.chart.notes.first.timeMs;
    _leadMs = math.max(2000, -first + 1000);
    _nowMs = -_leadMs;
    _clock.value = _nowMs;
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      _audioSource = await widget.library.prepareAudio(widget.song);
      if (_audioSource!.isFile) {
        await _player.setFilePath(_audioSource!.source);
      } else {
        await _player.setUrl(_audioSource!.source);
      }
      if (kIsWeb) await _player.setVolume(0);
      if (!mounted) return;
      setState(() => _ready = true);
      if (!kIsWeb) _start();
    } catch (error) {
      if (mounted) setState(() => _error = 'Audio could not play: $error');
    }
  }

  void _start() {
    if (!_ready || _started) return;
    if (_profileWeb && !_profilingFrames) {
      _profileFrames.clear();
      _profilingFrames = true;
      SchedulerBinding.instance.addTimingsCallback(_recordFrameTimings);
    }
    _leadClock.start();
    if (kIsWeb) unawaited(_playAudio());
    _ticker ??=
        Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
    setState(() => _started = true);
  }

  void _recordFrameTimings(List<FrameTiming> timings) {
    for (final frame in timings) {
      _profileFrames.add(frame.totalSpan.inMicroseconds / 1000);
    }
    if (_profileFrames.length < 300) return;
    final sorted = [..._profileFrames]..sort();
    final p95 = sorted[(sorted.length * 0.95).floor()];
    final over32 = sorted.where((ms) => ms > 32).length;
    debugPrint('WEB_PLAY_FRAMES: count=${sorted.length} '
        'p95_ms=${p95.toStringAsFixed(1)} over32=$over32');
    SchedulerBinding.instance.removeTimingsCallback(_recordFrameTimings);
    _profilingFrames = false;
    _profileFrames.clear();
  }

  int _clockMs() {
    if (!_audioStarted) {
      return _leadClock.elapsedMilliseconds - _leadMs + widget.offsetMs;
    }
    return _player.position.inMilliseconds + widget.offsetMs;
  }

  Future<void> _playAudio() async {
    try {
      await _player.play();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Audio playback stopped: $error';
          _paused = true;
        });
      }
    }
  }

  Future<void> _beginAudio() async {
    try {
      if (kIsWeb) {
        await _player.seek(Duration.zero);
        await _player.setVolume(1);
      }
      if (!_player.playing) unawaited(_playAudio());
      _audioStarted = true;
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Audio playback stopped: $error';
          _paused = true;
        });
      }
    } finally {
      _audioTransitioning = false;
    }
  }

  void _tick() {
    if (!mounted || !_ready || !_started || _paused || _finished) return;
    if (!_audioStarted &&
        !_audioTransitioning &&
        _leadClock.elapsedMilliseconds >= _leadMs) {
      _audioTransitioning = true;
      unawaited(_beginAudio());
    }
    final now = _clockMs();
    final oldScore = _engine.score;
    final oldCombo = _engine.combo;
    final oldJudgement = _engine.lastJudgement;
    final wasLeading = _nowMs < 0;
    _engine.advance(now);
    final done = now >= _engine.finalTimeMs ||
        _audioStarted && _player.processingState == ProcessingState.completed;
    if (done) {
      _engine.advance(_engine.finalTimeMs);
      unawaited(_player.pause());
    }
    _nowMs = now;
    _clock.value = now;
    if (done ||
        oldScore != _engine.score ||
        oldCombo != _engine.combo ||
        oldJudgement != _engine.lastJudgement ||
        wasLeading != (now < 0)) {
      setState(() => _finished = done);
    }
  }

  void _tap(HitColor color, Hand hand) {
    if (!_ready || !_started || _paused || _finished) return;
    final now = _clockMs();
    final oldScore = _engine.score;
    final oldCombo = _engine.combo;
    final oldJudgement = _engine.lastJudgement;
    _nowMs = now;
    _engine.tap(color, hand, now);
    if (oldScore != _engine.score ||
        oldCombo != _engine.combo ||
        oldJudgement != _engine.lastJudgement) {
      setState(() {});
    }
    _clock.value = now;
    _hitRevision.value++;
  }

  Future<void> _togglePause() async {
    if (_paused) {
      setState(() => _paused = false);
      if (_audioStarted) {
        unawaited(_playAudio());
      } else {
        _leadClock.start();
        if (kIsWeb) unawaited(_playAudio());
      }
    } else {
      setState(() => _paused = true);
      if (_audioStarted) {
        await _player.pause();
      } else {
        _leadClock.stop();
        if (kIsWeb) await _player.pause();
      }
    }
  }

  Future<void> _retry() async {
    await _player.pause();
    await _player.seek(Duration.zero);
    if (kIsWeb) await _player.setVolume(0);
    _leadClock.reset();
    if (!kIsWeb) _leadClock.start();
    if (!mounted) return;
    setState(() {
      _engine = JudgementEngine(widget.song.chart);
      _nowMs = -_leadMs;
      _started = !kIsWeb;
      _paused = false;
      _audioStarted = false;
      _audioTransitioning = false;
      _finished = false;
      _error = null;
    });
    _clock.value = -_leadMs;
  }

  void _resumeAfterError() {
    setState(() {
      _error = null;
      _paused = false;
    });
    if (_audioStarted) {
      unawaited(_playAudio());
    } else {
      unawaited(_playAudio());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (_profilingFrames) {
      SchedulerBinding.instance.removeTimingsCallback(_recordFrameTimings);
    }
    final source = _audioSource;
    unawaited(_player.dispose().then((_) => source?.release?.call()));
    _clock.dispose();
    _hitRevision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = _engine.snapshot;
    return GameKeyboard(
      onHit: _tap,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${widget.song.chart.title} · ${widget.song.chart.difficulty}',
          ),
          actions: [
            if (_ready && _started && !_finished)
              IconButton(
                tooltip: _paused ? 'Resume' : 'Pause',
                icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                onPressed: _togglePause,
              ),
            IconButton(
              tooltip: 'Retry',
              icon: const Icon(Icons.replay),
              onPressed: _ready ? _retry : null,
            ),
          ],
        ),
        body: _error != null
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!, textAlign: TextAlign.center),
                if (_ready)
                  FilledButton(
                    onPressed: _resumeAfterError,
                    child: const Text('Tap to play'),
                  ),
              ]))
            : !_ready
                ? const Center(child: CircularProgressIndicator())
                : !_started
                    ? Center(
                        child: FilledButton.icon(
                        onPressed: _start,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start song'),
                      ))
                    : _finished
                        ? _Results(stats: stats, onRetry: _retry)
                        : Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 6,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Score ${stats.score}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    Text(
                                      _paused
                                          ? 'Paused'
                                          : _nowMs < 0
                                              ? 'Ready…'
                                              : _engine.lastJudgement,
                                    ),
                                    Text(
                                      'Combo ${stats.combo}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: CustomPaint(
                                  painter: _LanePainter(
                                    widget.song.chart,
                                    _engine,
                                    _clock,
                                    _hitRevision,
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                              SizedBox(
                                height: 86,
                                child: Row(
                                  children: [
                                    _Pad(
                                      'D · Left Ka',
                                      HitColor.blue,
                                      Hand.left,
                                      Colors.blue,
                                      _tap,
                                    ),
                                    _Pad(
                                      'F · Left Don',
                                      HitColor.red,
                                      Hand.left,
                                      Colors.deepOrange,
                                      _tap,
                                    ),
                                    _Pad(
                                      'J · Right Don',
                                      HitColor.red,
                                      Hand.right,
                                      Colors.deepOrange,
                                      _tap,
                                    ),
                                    _Pad(
                                      'K · Right Ka',
                                      HitColor.blue,
                                      Hand.right,
                                      Colors.blue,
                                      _tap,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
      ),
    );
  }
}

class _Pad extends StatelessWidget {
  const _Pad(this.label, this.color, this.hand, this.paint, this.onTap);
  final String label;
  final HitColor color;
  final Hand hand;
  final Color paint;
  final void Function(HitColor, Hand) onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Semantics(
            button: true,
            label: label,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => onTap(color, hand),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: paint.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _LanePainter extends CustomPainter {
  _LanePainter(this.chart, this.engine, this.clock, this.hitRevision)
      : super(repaint: Listenable.merge([clock, hitRevision]));
  final Chart chart;
  final JudgementEngine engine;
  final ValueNotifier<int> clock;
  final ValueNotifier<int> hitRevision;

  @override
  void paint(Canvas canvas, Size size) {
    final lane = Rect.fromLTWH(
      0,
      size.height * 0.24,
      size.width,
      size.height * 0.52,
    );
    canvas.drawRect(lane, Paint()..color = const Color(0xFF20242A));
    final center = lane.center.dy;
    final hitX = size.width * 0.18;
    final speed = size.width / 2400;
    final nowMs = clock.value;
    final firstVisibleMs = nowMs + ((-50 - hitX) / speed).floor();
    final lastVisibleMs = nowMs + ((size.width + 50 - hitX) / speed).ceil();
    canvas.drawCircle(
      Offset(hitX, center),
      31,
      Paint()..color = Colors.white24,
    );
    canvas.drawCircle(
      Offset(hitX, center),
      24,
      Paint()..color = Colors.black54,
    );
    canvas.save();
    canvas.clipRect(lane);
    for (final i in engine.activeLongIndices) {
      if (chart.notes[i].timeMs < firstVisibleMs) {
        _paintNote(canvas, i, size, center, hitX, speed, nowMs);
      }
    }
    for (var i = _firstAtOrAfter(firstVisibleMs);
        i < chart.notes.length && chart.notes[i].timeMs <= lastVisibleMs;
        i++) {
      _paintNote(canvas, i, size, center, hitX, speed, nowMs);
    }
    canvas.restore();
  }

  int _firstAtOrAfter(int timeMs) {
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

  void _paintNote(Canvas canvas, int i, Size size, double center, double hitX,
      double speed, int nowMs) {
    final note = chart.notes[i];
    if (engine.results[i] != NoteResult.pending) return;
    final x = hitX + (note.timeMs - nowMs) * speed;
    if (note.isLong) {
      final endX = hitX + (note.endMs! - nowMs) * speed;
      if (endX < -50 || x > size.width + 50) return;
      final color =
          note.kind == NoteKind.roll ? Colors.amber : Colors.purpleAccent;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x, center - 16, endX, center + 16),
          const Radius.circular(16),
        ),
        Paint()..color = color,
      );
    } else {
      if (x < -50 || x > size.width + 50) return;
      final color = note.kind == NoteKind.don
          ? Colors.deepOrangeAccent
          : Colors.lightBlueAccent;
      canvas.drawCircle(
        Offset(x, center),
        note.large ? 27 : 19,
        Paint()..color = color,
      );
      canvas.drawCircle(
        Offset(x, center),
        note.large ? 27 : 19,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LanePainter oldDelegate) =>
      oldDelegate.chart != chart ||
      oldDelegate.engine != engine ||
      oldDelegate.clock != clock;
}

class _Results extends StatelessWidget {
  const _Results({required this.stats, required this.onRetry});
  final GameSnapshot stats;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Results', style: Theme.of(context).textTheme.headlineMedium),
            Text(
              'Score ${stats.score}   Accuracy ${(stats.accuracy * 100).toStringAsFixed(1)}%',
            ),
            Text(
              'Perfect ${stats.perfect}   Good ${stats.good}   Miss ${stats.miss}',
            ),
            Text('Max combo ${stats.maxCombo}   Long hits ${stats.longHits}'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.replay),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
}
