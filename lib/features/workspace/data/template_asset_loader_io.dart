import 'package:flutter/services.dart';

/// Loads a bundled asset's bytes by [assetKey] (e.g.
/// `assets/templates/blink/blink.ino`). Native platforms read straight from the
/// app bundle via [rootBundle].
Future<Uint8List> loadTemplateAsset(String assetKey) async =>
    (await rootBundle.load(assetKey)).buffer.asUint8List();
