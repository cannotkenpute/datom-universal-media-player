import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'source_bridge_contract.dart';

SourceBridge createSourceBridge() => _IoSourceBridge();

class _IoSourceBridge implements SourceBridge {
  final Set<_IoSourceCapability> _sources = {};

  @override
  Future<SourceCapability?> pickSource() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'mp3', 'datom', 'datmov', 'datmus'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    final selected = result.files.single;
    final source = _IoSourceCapability(
      selected.xFile,
      selected.name,
      selected.extension == 'mp4'
          ? 'video/mp4'
          : selected.extension == 'mp3'
              ? 'audio/mpeg'
              : '',
      selected.size,
    );
    _sources.add(source);
    return source;
  }

  @override
  Future<SourceCapability> openDroppedSource(Object file) async {
    if (file is! XFile) {
      throw ArgumentError('Dropped source must be an XFile');
    }
    final source = _IoSourceCapability(
      file,
      file.name,
      file.mimeType ?? '',
      await file.length(),
    );
    _sources.add(source);
    return source;
  }

  @override
  void installDropHandler(void Function(SourceCapability) onSource) {}

  @override
  Future<void> dispose() async {
    for (final source in _sources.toList()) {
      await source.dispose();
    }
    _sources.clear();
  }
}

class _IoSourceCapability implements SourceCapability {
  _IoSourceCapability(this._file, this.name, this.mime, this.size);

  final XFile _file;
  final Set<File> _temporaryFiles = {};

  @override
  final String name;

  @override
  final String mime;

  @override
  final int size;

  @override
  Future<Uint8List> readRange(int start, int end) async {
    if (start < 0 || end < start || end > size) {
      throw RangeError.range(end, start, size);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in _file.openRead(start, end)) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<File> _copyPayload(int payloadOffset, String suffix) async {
    final directory = await getTemporaryDirectory();
    final safeSuffix = suffix.startsWith('.') ? suffix : '.$suffix';
    final target = File(path.join(
      directory.path,
      'datom-${DateTime.now().microsecondsSinceEpoch}$safeSuffix',
    ));
    final sink = target.openWrite();
    try {
      await sink.addStream(_file.openRead(payloadOffset));
    } finally {
      await sink.close();
    }
    _temporaryFiles.add(target);
    return target;
  }

  @override
  Future<PreparedPlayback> preparePlayback({
    required int payloadOffset,
    required String mime,
    required String kind,
  }) async {
    final sourcePath = _file.path;
    final direct = payloadOffset == 0 && sourcePath.isNotEmpty;
    final suffix = kind == 'video' ? '.mp4' : '.mp3';
    final playbackFile =
        direct ? File(sourcePath) : await _copyPayload(payloadOffset, suffix);
    return PreparedPlayback(
      location: playbackFile.path,
      file: true,
      kind: kind,
      mime: mime,
      generation: 0,
      release: () async {
        if (!direct && await playbackFile.exists()) {
          await playbackFile.delete();
          _temporaryFiles.remove(playbackFile);
        }
      },
    );
  }

  @override
  Future<String?> saveWrapped({
    required Uint8List prefix,
    required int payloadOffset,
    required String suggestedName,
  }) async {
    final directory = await getTemporaryDirectory();
    final target = File(path.join(
      directory.path,
      'datom-export-${DateTime.now().microsecondsSinceEpoch}.datom',
    ));
    final sink = target.openWrite();
    try {
      sink.add(prefix);
      await sink.addStream(_file.openRead(payloadOffset));
    } finally {
      await sink.close();
    }
    _temporaryFiles.add(target);
    return FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(
        sourceFilePath: target.path,
        fileName: suggestedName,
        mimeTypesFilter: const ['application/vnd.datomworld.datom'],
      ),
    );
  }

  @override
  Future<void> dispose() async {
    for (final file in _temporaryFiles.toList()) {
      if (await file.exists()) {
        await file.delete();
      }
    }
    _temporaryFiles.clear();
  }
}
