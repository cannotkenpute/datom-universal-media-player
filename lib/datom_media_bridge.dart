import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'src/fullscreen_bridge.dart'
    if (dart.library.html) 'src/fullscreen_bridge_web.dart' as fullscreen_impl;
import 'src/fullscreen_contract.dart';
import 'src/source_bridge_contract.dart';
import 'src/video_player_host.dart';
import 'src/source_bridge_io.dart'
    if (dart.library.html) 'src/source_bridge_web.dart' as source_impl;
import 'src/video_controller_io.dart'
    if (dart.library.html) 'src/video_controller_web.dart' as video_impl;

export 'src/source_bridge_contract.dart';
export 'src/video_player_host.dart';

SourceBridge createSourceBridge() => source_impl.createSourceBridge();

VideoPlayerHost createVideoPlayerHost(
  void Function(Map<String, Object?>) onEvent,
) =>
    video_impl.createVideoPlayerHost(onEvent);

FullscreenBridge createFullscreenBridge() =>
    fullscreen_impl.createFullscreenBridge();

Uint8List datomHeader(String magic, int manifestLength) {
  final bytes = Uint8List(12);
  final magicBytes = Uint8List.fromList(magic.codeUnits);
  bytes.setRange(0, 8, magicBytes);
  ByteData.sublistView(bytes).setUint32(8, manifestLength, Endian.little);
  return bytes;
}

int littleEndianUint32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint32(offset, Endian.little);

Uint8List datomPrefix(String magic, String manifest) {
  final manifestBytes = Uint8List.fromList(utf8.encode(manifest));
  final header = datomHeader(magic, manifestBytes.length);
  final output = Uint8List(header.length + manifestBytes.length);
  output.setRange(0, header.length, header);
  output.setRange(header.length, output.length, manifestBytes);
  return output;
}

String decodeUtf8(Uint8List bytes) => utf8.decode(bytes);

class PlayerSettingsStore {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<Map<String, Object?>> load() async => {
        'volume': await _preferences.getDouble('player.volume') ?? 1.0,
        'muted': await _preferences.getBool('player.muted') ?? false,
        'rate': await _preferences.getDouble('player.rate') ?? 1.0,
      };

  Future<void> save(double volume, bool muted, double rate) async {
    await _preferences.setDouble('player.volume', volume);
    await _preferences.setBool('player.muted', muted);
    await _preferences.setDouble('player.rate', rate);
  }
}
