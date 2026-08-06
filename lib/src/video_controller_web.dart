import 'package:video_player/video_player.dart';

import 'source_bridge_contract.dart';
import 'video_player_host.dart';
import 'video_player_host_base.dart';

VideoPlayerHost createVideoPlayerHost(
  void Function(Map<String, Object?>) onEvent,
) =>
    DatomVideoPlayerHost(
      onEvent,
      (PreparedPlayback source) =>
          VideoPlayerController.networkUrl(Uri.parse(source.location)),
    );
