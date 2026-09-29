import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Rasterless cache of the SVG artwork `.pdl` parts are drawn from.
///
/// A `CustomPainter` paints synchronously and an SVG loads asynchronously, so
/// something has to bridge the two. This holds each asset's decoded
/// [ui.Picture] and its intrinsic size, kicks off the load the first time a
/// path is asked for, and bumps [revision] when one arrives so painters
/// listening to it repaint.
///
/// It is a process-wide cache on purpose: a circuit with twenty of the same
/// sensor should decode that artwork once, and the entries are immutable
/// pictures that stay valid for the life of the app.
class PdlSvgCache._() {
  /// Bumped whenever a picture finishes loading. Painters pass this as their
  /// `repaint` listenable, which is how art appears without a rebuild.
  static final revision = ValueNotifier<int>(0);

  static final Map<String, PdlSvgArtwork> _loaded = {};
  static final Set<String> _inFlight = {};
  static final Set<String> _failed = {};

  /// The artwork for [assetPath], or null while it loads (or if it failed).
  ///
  /// Returning null rather than throwing is what lets a part draw its shapes
  /// and pins on the first frame and gain its SVG on a later one.
  static PdlSvgArtwork? artwork(String assetPath) {
    final hit = _loaded[assetPath];
    if (hit != null) return hit;
    if (!_inFlight.contains(assetPath) && !_failed.contains(assetPath)) {
      _inFlight.add(assetPath);
      unawaited(_load(assetPath));
    }
    return null;
  }

  static Future<void> _load(String assetPath) async {
    try {
      final info = await vg.loadPicture(SvgAssetLoader(assetPath), null);
      _loaded[assetPath] = PdlSvgArtwork(picture: info.picture, size: info.size);
      revision.value++;
    } catch (error, stack) {
      // Remembered as failed so a missing asset is not retried once per frame
      // forever. Reported through the framework rather than a logger: this
      // package deliberately has no logging dependency, and FlutterError is
      // already routed to the app's logger and to Crashlytics.
      _failed.add(assetPath);
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'pinbench_parts',
          context: ErrorDescription('loading PDL artwork "$assetPath"'),
        ),
      );
    } finally {
      _inFlight.remove(assetPath);
    }
  }

  /// Test seam: forgets everything, including failures.
  @visibleForTesting
  static void reset() {
    _loaded.clear();
    _inFlight.clear();
    _failed.clear();
  }

  /// Whether [assetPath] failed to load. Used by tests that assert bundled
  /// artwork is actually present.
  @visibleForTesting
  static bool hasFailed(String assetPath) => _failed.contains(assetPath);
}

/// A decoded SVG: the picture plus the size it was authored at, which is what
/// a part is scaled from.
@immutable
class const PdlSvgArtwork({required final ui.Picture picture, required final ui.Size size});
