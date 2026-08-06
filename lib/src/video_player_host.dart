import 'package:flutter/widgets.dart';

import 'source_bridge_contract.dart';

abstract class VideoPlayerHost {
  Widget buildSurface();

  Future<void> load(PreparedPlayback source);

  Future<void> play();

  Future<void> pause();

  Future<void> seek(double seconds);

  Future<void> setVolume(double volume);

  Future<void> setMuted(bool muted);

  Future<void> setRate(double rate);

  Future<void> close();

  Future<void> dispose();
}
