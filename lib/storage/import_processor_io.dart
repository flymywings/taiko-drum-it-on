import 'import_processor.dart';

Future<PreparedImport> processImports(List<ImportInput> files,
        {void Function(String)? onProgress}) async =>
    ImportProcessor().process(files, onProgress: onProgress);
