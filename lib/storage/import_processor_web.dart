import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../chart/chart.dart';
import 'import_processor.dart';

Future<PreparedImport> processImports(List<ImportInput> files,
    {void Function(String)? onProgress}) async {
  if (files.isEmpty) return const PreparedImport([], []);
  final worker =
      web.Worker(Uri.base.resolve('import_worker.js').toString().toJS);
  final result = Completer<PreparedImport>();
  worker.onmessage = ((web.Event event) {
    try {
      final data = (event as web.MessageEvent).data as JSArray<JSAny?>;
      final kind = (data[0] as JSString).toDart;
      if (kind == 'progress') {
        onProgress?.call((data[1] as JSString).toDart);
        return;
      }
      if (kind == 'error') {
        if (!result.isCompleted) {
          result.completeError(StateError((data[1] as JSString).toDart));
        }
        return;
      }
      final decoded =
          jsonDecode((data[1] as JSString).toDart) as Map<String, dynamic>;
      final audio = <Uint8List>[];
      for (var i = 2; i < data.length; i++) {
        audio.add((data[i] as JSUint8Array).toDart);
      }
      final songs = <PreparedSong>[];
      for (final raw in decoded['songs'] as List) {
        final song = Map<String, dynamic>.from(raw as Map);
        songs.add(PreparedSong(
          Chart.fromJson(Map<String, dynamic>.from(song['chart'] as Map)),
          audio[song['audioIndex'] as int],
          song['extension'] as String,
        ));
      }
      if (!result.isCompleted) {
        result.complete(PreparedImport(
            songs, (decoded['messages'] as List).cast<String>()));
      }
    } catch (error, stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    }
  }).toJS;
  worker.onerror = ((web.Event event) {
    if (!result.isCompleted) {
      result.completeError(StateError('Import worker could not start.'));
    }
  }).toJS;
  final jsBytes = files.map((file) => file.bytes.toJS).toList();
  worker.postMessage(
    <JSAny?>[
      'process'.toJS,
      jsonEncode(files.map((file) => file.name).toList()).toJS,
      ...jsBytes,
    ].toJS,
    jsBytes
        .map((bytes) => bytes.getProperty<JSArrayBuffer>('buffer'.toJS))
        .toList()
        .toJS,
  );
  try {
    return await result.future;
  } finally {
    worker.terminate();
  }
}
