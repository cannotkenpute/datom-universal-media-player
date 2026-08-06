import 'dart:typed_data';

abstract class SourceBridge {
  Future<SourceCapability?> pickSource();

  Future<SourceCapability> openDroppedSource(Object file);

  void installDropHandler(void Function(SourceCapability) onSource);

  Future<void> dispose();
}

abstract class SourceCapability {
  String get name;

  String get mime;

  int get size;

  Future<Uint8List> readRange(int start, int end);

  Future<PreparedPlayback> preparePlayback({
    required int payloadOffset,
    required String mime,
    required String kind,
  });

  Future<String?> saveWrapped({
    required Uint8List prefix,
    required int payloadOffset,
    required String suggestedName,
  });

  Future<void> dispose();
}

class PreparedPlayback {
  const PreparedPlayback({
    required this.location,
    required this.file,
    required this.kind,
    required this.mime,
    required this.generation,
    required this.release,
  });

  final String location;
  final bool file;
  final String kind;
  final String mime;
  final int generation;
  final Future<void> Function() release;

  PreparedPlayback withGeneration(int value) => PreparedPlayback(
        location: location,
        file: file,
        kind: kind,
        mime: mime,
        generation: value,
        release: release,
      );
}
