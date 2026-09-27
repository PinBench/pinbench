import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Loads a bundled asset's bytes by [assetKey] on the web, bypassing the HTTP
/// cache.
///
/// Flutter's `rootBundle` fetches assets with the browser's default cache mode.
/// Browsers that cached assets under an `immutable` HTTP header (from an earlier
/// deploy) keep serving the stale copy for up to a year, which is why an updated
/// template could keep rendering its old circuit. Template files change over
/// time, so fetch them with `cache: 'reload'` to always get the current version
/// from the server (this also refreshes the cached entry with the new headers).
///
/// The asset is served at `assets/<assetKey>` relative to the app's base href.
Future<Uint8List> loadTemplateAsset(String assetKey) async {
  final response = await web.window
      .fetch('assets/$assetKey'.toJS, web.RequestInit(cache: 'reload'))
      .toDart;
  final buffer = await response.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}
