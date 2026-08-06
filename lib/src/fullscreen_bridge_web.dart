// ignore_for_file: deprecated_member_use

import 'dart:html' as html;

import 'fullscreen_contract.dart';

FullscreenBridge createFullscreenBridge() => _WebFullscreenBridge();

class _WebFullscreenBridge implements FullscreenBridge {
  @override
  Future<bool> enter() async {
    await html.document.documentElement?.requestFullscreen();
    return html.document.fullscreenElement != null;
  }

  @override
  Future<bool> exit() async {
    if (html.document.fullscreenElement != null) {
      html.document.exitFullscreen();
    }
    return false;
  }
}
