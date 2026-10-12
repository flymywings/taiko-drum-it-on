import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:taiko_rhythm_proto/storage/import_processor.dart';

@JS('self')
external web.DedicatedWorkerGlobalScope get workerScope;

void main() {
  workerScope.onmessage = ((web.Event event) {
    try {
      final data = (event as web.MessageEvent).data as JSArray<JSAny?>;
      final names =
          (jsonDecode((data[1] as JSString).toDart) as List).cast<String>();
      final files = <ImportInput>[];
      for (var i = 0; i < names.length; i++) {
        files.add(ImportInput(names[i], (data[i + 2] as JSUint8Array).toDart));
      }
      final prepared = ImportProcessor().process(files, onProgress: (message) {
        workerScope.postMessage(<JSAny?>['progress'.toJS, message.toJS].toJS);
      });
      final uniqueAudio = <Uint8List>[];
      final audioIndexes = <Uint8List, int>{};
      final songs = <Map<String, Object?>>[];
      for (final song in prepared.songs) {
        final index = audioIndexes.putIfAbsent(song.audioBytes, () {
          uniqueAudio.add(song.audioBytes);
          return uniqueAudio.length - 1;
        });
        songs.add({
          'chart': song.chart.toJson(),
          'audioIndex': index,
          'extension': song.extension,
        });
      }
      final jsBytes = uniqueAudio.map((bytes) => bytes.toJS).toList();
      workerScope.postMessage(
        <JSAny?>[
          'result'.toJS,
          jsonEncode({'songs': songs, 'messages': prepared.messages}).toJS,
          ...jsBytes,
        ].toJS,
        jsBytes
            .map((bytes) => bytes.getProperty<JSArrayBuffer>('buffer'.toJS))
            .toList()
            .toJS,
      );
    } catch (error) {
      workerScope.postMessage(<JSAny?>['error'.toJS, '$error'.toJS].toJS);
    }
  }).toJS;
}
