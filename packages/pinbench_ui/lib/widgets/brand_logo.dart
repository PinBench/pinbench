import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';

/// The PinBench wordmark from the brand kit: Outfit Bold drawn as outlines,
/// with a gold pad for the dot on the i and two more under the P and the B,
/// joined by a trace.
///
/// Drawn, never typed. The typeface alone has none of the pads, and the
/// outlines look the same whether or not a font has loaded. Teal on a light
/// ground and white on a dark one, the kit's `wordmark-teal.svg` and
/// `wordmark-white.svg` (`handbook/brand/logo/svg/`). The name is still typed
/// wherever it is text rather than a logo: window titles, menus, dialogs.
class const BrandWordmark({
  super.key,

  /// The wordmark's height; its width follows, at about 4.5 times this.
  final double height = 32,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SvgPicture.string(
    context.appBrightness == Brightness.dark ? _wordmarkWhite : _wordmarkTeal,
    height: height,
    semanticsLabel: 'PinBench',
  );
}

/// The app icon, as the kit's `icon-teal-rounded.svg`: the PB monogram drawn
/// as traces on PCB teal, standing on two gold pads.
///
/// The rounded cut, because nothing masks it inside the app; the platform
/// icons are the full-bleed square, which each OS rounds itself.
class const BrandIcon({super.key, required final double size}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      SvgPicture.string(_iconTealRounded, width: size, height: size, excludeFromSemantics: true);
}

// The kit's SVG masters, verbatim but for the XML declaration.

const _wordmarkTeal =
    '''<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="265" viewBox="34 -738 4038 891" role="img" aria-label="PinBench wordmark"><g transform="scale(1,-1)"><path d="M146.5 -40 H1531.5" fill="none" stroke="#9FCFD2" stroke-width="46" stroke-linecap="round"></path><g fill="#00878F"><path transform="translate(0 0)" d="M188 257V379H340Q369.27456647398844 379 392.8887283236994 390.9015151515151Q416.5028901734104 402.8030303030303 430.5014450867052 425.7833333333333Q444.5 448.76363636363635 444.5 481.5Q444.5 514.2363636363636 430.5014450867052 537.2166666666667Q416.5028901734104 560.1969696969697 392.8887283236994 572.0984848484849Q369.27456647398844 584 340 584H188V706H362.5Q430 706 484.0 678.75Q538 651.5 569.5 601.3475609756098Q601 551.1951219512196 601 481.5975609756098Q601 412.5 569.5 362.0Q538 311.5 484.0 284.25Q430 257 362.5 257ZM67.5 0V706H225V0Z"></path><path transform="translate(603 0)" d="M54 0V486H207V0Z"></path><path transform="translate(839 0)" d="M375 0V276.5Q375 315 351.5 338.25Q328 361.5 291.6224489795918 361.5Q266.8724489795918 361.5 247.6862244897959 351.0Q228.5 340.5 217.75 321.25Q207 302 207 276.5L147.5 305.5Q147.5 363 172.75 405.75Q198 448.5 242.44796954314722 472.25Q286.89593908629445 496 343.1979695431472 496Q396.5 496 438.25 470.5Q480 445 504.0 403.0Q528 361 528 311V0ZM54 0V486H207V0Z"></path><path transform="translate(1386 0)" d="M188 0V122H354Q399.5 122 425.5 148.75Q451.5 175.5 451.5 215Q451.5 241.5 439.75 262.75Q428 284 406.25 296.0Q384.5 308 354 308H188V427H341Q379.5 427 403.5 446.5Q427.5 466 427.5 505.5Q427.5 545 403.5 564.5Q379.5 584 341 584H188V706H370.5Q438.5 706 486.25 680.75Q534 655.5 559.0 613.75Q584 572 584 521Q584 455.5 541.75 410.5Q499.5 365.5 418 349L421.5 401.5Q511 384.5 559.5 332.5Q608 280.5 608 204.5Q608 146.5 579.25 100.25Q550.5 54 497.0 27.0Q443.5 0 369 0ZM67.5 0V706H223V0Z"></path><path transform="translate(2002 0)" d="M293.5 -11Q214.5 -11 153.25 21.5Q92 54 57.0 111.75Q22 169.5 22 243Q22 316 56.25 373.25Q90.5 430.5 149.75 463.75Q209 497 282.5 497Q354.5 497 409.75 465.75Q465 434.5 496.5 379.5Q528 324.5 528 254Q528 240.5 526.5 226.0Q525 211.5 521 193L102 191.5V296.5L456 298L390 253.5Q389 295.5 376.75 323.25Q364.5 351 341.25 365.5Q318 380 283.5 380Q247.5 380 221.0 363.5Q194.5 347 180.25 316.75Q166 286.5 166 244Q166 201 181.25 170.25Q196.5 139.5 225.0 123.25Q253.5 107 293 107Q329 107 358.0 119.25Q387 131.5 409 156.5L493 72.5Q457 31 406.0 10.0Q355 -11 293.5 -11Z"></path><path transform="translate(2525 0)" d="M375 0V276.5Q375 315 351.5 338.25Q328 361.5 291.6224489795918 361.5Q266.8724489795918 361.5 247.6862244897959 351.0Q228.5 340.5 217.75 321.25Q207 302 207 276.5L147.5 305.5Q147.5 363 172.75 405.75Q198 448.5 242.44796954314722 472.25Q286.89593908629445 496 343.1979695431472 496Q396.5 496 438.25 470.5Q480 445 504.0 403.0Q528 361 528 311V0ZM54 0V486H207V0Z"></path><path transform="translate(3072 0)" d="M289 -11Q213.5 -11 152.75 22.0Q92 55 57.0 112.75Q22 170.5 22 242.5Q22 315.5 57.25 373.0Q92.5 430.5 153.5 463.75Q214.5 497 290.5 497Q347.5 497 395.0 477.25Q442.5 457.5 479.5 419L382 321Q365 339.5 342.25 348.75Q319.5 358 290.5 358Q258 358 232.5 343.5Q207 329 192.25 303.5Q177.5 278 177.5 243.5Q177.5 209.5 192.25 183.5Q207 157.5 232.75 142.75Q258.5 128 290.5 128Q321 128 344.25 138.25Q367.5 148.5 384.5 168L482 70Q443.5 30 395.75 9.5Q348 -11 289 -11Z"></path><path transform="translate(3543 0)" d="M375 0V276.5Q375 315 351.5 338.25Q328 361.5 291.6224489795918 361.5Q266.8724489795918 361.5 247.6862244897959 351.0Q228.5 340.5 217.75 321.25Q207 302 207 276.5L147.5 305.5Q147.5 363 171.75 405.75Q196 448.5 238.94796954314722 472.25Q281.89593908629445 496 337.6979695431472 496Q394.5 496 437.5 472.25Q480.5 448.5 504.25 407.0Q528 365.5 528 311V0ZM54 0V726H207V0Z"></path></g><circle cx="733.5" cy="637" r="100" fill="#E0B95C"></circle><circle cx="733.5" cy="637" r="40" fill="#06363A"></circle><circle cx="146.5" cy="-40" r="112" fill="#E0B95C"></circle><circle cx="146.5" cy="-40" r="44" fill="#06363A"></circle><circle cx="1531.5" cy="-40" r="112" fill="#E0B95C"></circle><circle cx="1531.5" cy="-40" r="44" fill="#06363A"></circle></g></svg>''';

/// The white wordmark is the teal one with its two colours swapped, exactly as
/// the kit's `wordmark-white.svg` is: white letters, a trace dark enough to
/// sit on board ink. The pads stay gold.
final _wordmarkWhite = _wordmarkTeal
    .replaceFirst('#00878F', '#FFFFFF')
    .replaceFirst('#9FCFD2', '#2F6E72');

const _iconTealRounded =
    '''<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 100 100" role="img" aria-label="PinBench icon on teal"><rect width="100" height="100" rx="22" fill="#00878F"></rect><path d="M30 76 H54" fill="none" stroke="#6FD6DB" stroke-width="3.5" stroke-linecap="round"></path><g fill="none" stroke="#FFFFFF" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"><path d="M26 76 V24 H40 L48 32 V42 L40 50 H26"></path><path d="M58 76 V24"></path><path d="M58 24 H72 L80 32 V42 L72 50 H58"></path><path d="M58 50 H72 L80 58 V68 L72 76 H58"></path></g><circle cx="26" cy="76" r="9" fill="#E0B95C"></circle><circle cx="58" cy="76" r="9" fill="#E0B95C"></circle><circle cx="26" cy="76" r="3.6" fill="#06363A"></circle><circle cx="58" cy="76" r="3.6" fill="#06363A"></circle></svg>''';
