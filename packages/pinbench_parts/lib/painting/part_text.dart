import 'package:flutter/widgets.dart';

import 'package:google_fonts/google_fonts.dart';

/// A word printed on a part — a transistor's type, a battery's voltage, a
/// remote's keys — set as text with a [TextPainter], in the face the
/// hand-written parts use (see `CapacitorPainter`), rather than outlined into
/// the artwork's paths. It stays sharp at any zoom, and changing a label is
/// changing a string, not redrawing geometry.
///
/// Sized by the height of its capitals and placed by their centre, because
/// that is what can be measured off a drawing.
@immutable
class const PartText(
  final String text, {
  required final double capHeight,
  required final Color color,

  /// The widest it may be; a longer word is set smaller to fit.
  final double? maxWidth,
}) {
  /// JetBrains Mono's capitals stand 0.73 em tall.
  static const _capRatio = 0.73;

  /// Notifies when a font finishes loading. The face is fetched at runtime,
  /// so a part first drawn before it arrives is drawn in a fallback; a
  /// painter repainting on this is redrawn in the real one.
  static Listenable get fontsChanged => _fonts;
  static final _fonts = _FontsChanged();

  /// Laid-out text, kept between paints: the words never change, only where
  /// they are drawn. Dropped when a font loads, so they are set again in it.
  static final _laidOut = <PartText, (TextPainter, double)>{};

  (TextPainter, double) _layout() => _laidOut[this] ??= () {
    _fonts.listen();
    var fontSize = capHeight / _capRatio;
    TextPainter set(double size) => TextPainter(
      text: TextSpan(
        text: text,
        style: GoogleFonts.jetBrainsMono(color: color, fontSize: size, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var painter = set(fontSize);
    if (maxWidth case final max? when painter.width > max) {
      fontSize *= max / painter.width;
      painter = set(fontSize);
    }
    return (painter, fontSize * _capRatio);
  }();

  /// Draws the text with its capitals centred on [centre], turned by [angle]
  /// radians about it.
  void paint(Canvas canvas, Offset centre, {double angle = 0}) {
    final (painter, cap) = _layout();
    final baseline = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    if (angle != 0) canvas.rotate(angle);
    painter.paint(canvas, Offset(-painter.width / 2, cap / 2 - baseline));
    canvas.restore();
  }

  @override
  bool operator ==(Object other) =>
      other is PartText &&
      other.text == text &&
      other.capHeight == capHeight &&
      other.color == color &&
      other.maxWidth == maxWidth;

  @override
  int get hashCode => Object.hash(text, capHeight, color, maxWidth);
}

class _FontsChanged extends ChangeNotifier {
  var _listening = false;

  /// Starts following font loads, the first time any text is set — by then
  /// the binding that announces them exists.
  void listen() {
    if (_listening) return;
    _listening = true;
    PaintingBinding.instance.systemFonts.addListener(() {
      PartText._laidOut.clear();
      notifyListeners();
    });
  }
}
