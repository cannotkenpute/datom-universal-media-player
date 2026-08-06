import 'package:flutter/services.dart';

import 'fullscreen_contract.dart';

FullscreenBridge createFullscreenBridge() => _MobileFullscreenBridge();

class _MobileFullscreenBridge implements FullscreenBridge {
  @override
  Future<bool> enter() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    return true;
  }

  @override
  Future<bool> exit() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    return false;
  }
}
