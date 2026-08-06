// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import 'source_bridge_contract.dart';

SourceBridge createSourceBridge() => _WebSourceBridge();

html.FileUploadInputElement createWebSourcePicker() =>
    html.FileUploadInputElement();

class _WebSourceBridge implements SourceBridge {
  final Set<_WebSourceCapability> _sources = {};
  StreamSubscription<html.Event>? _dragOverSubscription;
  StreamSubscription<html.Event>? _dropSubscription;

  @override
  Future<SourceCapability?> pickSource() async {
    final completer = Completer<html.File?>();
    // iOS disables custom extensions when an accept filter is present.
    // The selected file is validated by the media parser instead.
    final input = createWebSourcePicker();
    late StreamSubscription<html.Event> subscription;
    subscription = input.onChange.listen((_) {
      completer
          .complete(input.files?.isEmpty ?? true ? null : input.files!.first);
      subscription.cancel();
    });
    input.click();
    final file = await completer.future;
    if (file == null) {
      return null;
    }
    final source = _WebSourceCapability(file, file.name, file.type);
    _sources.add(source);
    return source;
  }

  @override
  Future<SourceCapability> openDroppedSource(Object file) async {
    if (file is html.File) {
      final source = _WebSourceCapability(file, file.name, file.type);
      _sources.add(source);
      return source;
    }
    if (file is XFile) {
      final request = await html.HttpRequest.request(
        file.path,
        responseType: 'blob',
      );
      final blob = request.response as html.Blob;
      final source = _WebSourceCapability(blob, file.name, file.mimeType ?? '');
      _sources.add(source);
      return source;
    }
    throw ArgumentError('Dropped source must be a browser File or XFile');
  }

  @override
  void installDropHandler(void Function(SourceCapability) onSource) {
    _dragOverSubscription?.cancel();
    _dropSubscription?.cancel();
    _dragOverSubscription = html.document.onDragOver.listen((event) {
      event.preventDefault();
    });
    _dropSubscription = html.document.onDrop.listen((event) {
      event.preventDefault();
      final files = event.dataTransfer.files;
      if (files == null || files.isEmpty) {
        return;
      }
      final source = _WebSourceCapability(
        files.first,
        files.first.name,
        files.first.type,
      );
      _sources.add(source);
      onSource(source);
    });
  }

  @override
  Future<void> dispose() async {
    await _dragOverSubscription?.cancel();
    await _dropSubscription?.cancel();
    for (final source in _sources.toList()) {
      await source.dispose();
    }
    _sources.clear();
  }
}

class _WebSourceCapability implements SourceCapability {
  _WebSourceCapability(this._blob, this.name, this.mime);

  final html.Blob _blob;
  final Set<String> _objectUrls = {};

  @override
  final String name;

  @override
  final String mime;

  @override
  int get size => _blob.size;

  Future<Uint8List> _readBlob(html.Blob blob) {
    final completer = Completer<Uint8List>();
    final reader = html.FileReader();
    reader.onLoad.listen((_) {
      final result = reader.result;
      if (result is! String) {
        completer.completeError(StateError('Browser returned non-text data'));
        return;
      }
      final separator = result.indexOf(',');
      if (separator < 0) {
        completer.completeError(StateError('Browser returned malformed data'));
        return;
      }
      completer.complete(base64.decode(result.substring(separator + 1)));
    });
    reader.onError.listen((_) {
      completer.completeError(reader.error ?? StateError('File read failed'));
    });
    reader.readAsDataUrl(blob);
    return completer.future;
  }

  @override
  Future<Uint8List> readRange(int start, int end) {
    if (start < 0 || end < start || end > size) {
      throw RangeError.range(end, start, size);
    }
    return _readBlob(_blob.slice(start, end));
  }

  @override
  Future<PreparedPlayback> preparePlayback({
    required int payloadOffset,
    required String mime,
    required String kind,
  }) async {
    final payload = _blob.slice(payloadOffset, size, mime);
    final url = html.Url.createObjectUrlFromBlob(payload);
    _objectUrls.add(url);
    return PreparedPlayback(
      location: url,
      file: false,
      kind: kind,
      mime: mime,
      generation: 0,
      release: () async {
        if (_objectUrls.remove(url)) {
          html.Url.revokeObjectUrl(url);
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
    final output = html.Blob(
      [prefix, _blob.slice(payloadOffset)],
      'application/vnd.datomworld.datom',
    );
    final url = html.Url.createObjectUrlFromBlob(output);
    final anchor = html.AnchorElement(href: url)
      ..download = suggestedName
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
    return suggestedName;
  }

  @override
  Future<void> dispose() async {
    for (final url in _objectUrls) {
      html.Url.revokeObjectUrl(url);
    }
    _objectUrls.clear();
  }
}
