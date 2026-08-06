@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:datom_universal_media_player/datom_media_bridge.dart';
import 'package:datom_universal_media_player/src/source_bridge_web.dart'
    show createWebSourcePicker;

void main() {
  test('web source picker does not filter unknown iOS file types', () {
    expect(createWebSourcePicker().accept, isEmpty);
  });

  test('web source reads bounded byte ranges', () async {
    final bridge = createSourceBridge();
    final source = await bridge.openDroppedSource(
      XFile.fromData(
        Uint8List.fromList([0, 0, 0, 24, 102, 116, 121, 112, 109, 112, 52, 50]),
        name: 'clip.mp4',
        mimeType: 'video/mp4',
      ),
    );

    expect(await source.readRange(4, 8), [102, 116, 121, 112]);

    await source.dispose();
    await bridge.dispose();
  });
}
