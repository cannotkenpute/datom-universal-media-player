import 'dart:convert';
import 'dart:typed_data';

import 'package:datom_universal_media_player/datom_media_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DATOM1 header stores the UTF-8 manifest length little-endian', () {
    const manifest = '[[-1025 :datom.media/version 1 1 1]]';
    final prefix = datomPrefix('DATOM1\r\n', manifest);
    final manifestBytes = utf8.encode(manifest);

    expect(prefix.sublist(0, 8), utf8.encode('DATOM1\r\n'));
    expect(littleEndianUint32(prefix, 8), manifestBytes.length);
    expect(utf8.decode(prefix.sublist(12)), manifest);
  });

  test('wrapper concatenation preserves payload bytes exactly', () {
    final prefix = datomPrefix('DATOM1\r\n', '[]');
    final payload = Uint8List.fromList([0, 1, 2, 127, 128, 254, 255]);
    final wrapped = Uint8List(prefix.length + payload.length)
      ..setRange(0, prefix.length, prefix)
      ..setRange(prefix.length, prefix.length + payload.length, payload);

    expect(wrapped.sublist(prefix.length), payload);
  });
}
