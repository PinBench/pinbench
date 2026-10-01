import 'package:flutter/widgets.dart';
import 'package:pinbench_pdl/pinbench_pdl.dart';

import '../part_registry.dart';
import '../painting/base_component_painter.dart';
import '../painting/dsl_component_painter.dart';

/// Grouping used to organize parts in the palette.
enum PartCategory() {
  microcontrollers,
  basic,
  sensors,
  actuators,
  displays,
  boards,
  other;

  /// Resolves the `CATEGORY` line of a `.pdl` file. Unknown or absent names
  /// fall back to [other] rather than failing — a part in the wrong palette
  /// group is a nuisance, not a reason to refuse to load it.
  static PartCategory fromName(String? name) =>
      values.firstWhere((c) => c.name == name, orElse: () => PartCategory.other);
}

/// A **part**: one entry in the catalog, describing a *type* of component —
/// its name, footprint and how to paint it. A placed one on the canvas is a
/// `ComponentInstance`, which holds a [PartModel] and the instance state
/// (position, rotation, properties) around it.
///
/// Parts come from two sources: built-in [standardParts] (which supply a
/// [painterBuilder]) and data-driven PDL definitions (which carry a
/// [definitionId] and are rendered by a `DSLComponentPainter`).
class PartModel({
  required final String name,

  /// The part's unrotated footprint, in canvas units.
  required final Size size,

  /// Builds the painter for this part. Null for PDL-defined parts, which are
  /// resolved via [definitionId] instead.
  final BaseComponentPainter Function({bool isOutline, Map<String, dynamic>? properties})?
  painterBuilder,

  /// Id into the [PartRegistry] for PDL/data-driven parts; null for built-in
  /// ones.
  final String? definitionId,

  /// Names a simulation behaviour registered in the app, or null for a part
  /// that has none.
  ///
  /// Deliberately on the *part*, not only on `PartDefinition`: how a part is
  /// drawn and how it behaves are different questions. An LED and a servo need
  /// hand-written painters — a glow, a sweeping horn — and still want their
  /// behaviour dispatched rather than hard-coded into the simulation engine.
  /// A `.pdl` part sets this from its `LOGIC` line; a built-in sets it here.
  final String? logic,

  /// How this part appears in the analog solve, for built-in parts. A `.pdl`
  /// part carries the same thing on its `PartDefinition` instead.
  final SpiceModelDef? spice,

  /// Whether this part *is* the microcontroller rather than something wired to
  /// it.
  ///
  /// The one thing a simulator legitimately must single out: the board hosts
  /// the sketch and supplies every pin voltage, so it is not an element in the
  /// netlist like the parts around it. A flag rather than a name comparison,
  /// so a second board would not mean editing the engine.
  final bool isBoard = false,
  final PartCategory category = PartCategory.other,

  /// Properties a freshly placed instance starts with.
  ///
  /// The built-in counterpart of a `.pdl`'s `PROPERTIES` defaults, and it
  /// exists for the same reason: the properties panel lists a component's
  /// *map*, so a property that has never been written is a property the user
  /// cannot discover, let alone change. A part whose behaviour depends on one
  /// — a display that answers on a particular I²C address — has to arrive
  /// carrying it. Empty for every part that reads its own defaults from the
  /// painter, which is all of the older ones.
  final Map<String, dynamic> defaults = const {},

  /// Other names the part goes by, from its `.pdl`'s `ALIAS` lines —
  /// `Photoresistor` for the `LDR`. The palette search matches them, and so
  /// does a `.cdl` type token, which keeps a file written under a part's old
  /// name loading. The part is always *written* under [name].
  final List<String> aliases = const [],
}) {
  BaseComponentPainter? getPainter({bool isOutline = false, Map<String, dynamic>? properties}) =>
      painterBuilder?.call(isOutline: isOutline, properties: properties);

  PartModel clone() => PartModel(
    name: name,
    size: size,
    painterBuilder: painterBuilder,
    definitionId: definitionId,
    category: category,
    defaults: defaults,
    aliases: aliases,
    // Every placed instance is a clone of a catalog entry, so dropping this
    // here would mean a part behaves in the palette and not on the canvas.
    logic: logic,
    spice: spice,
    isBoard: isBoard,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'size': {'width': size.width, 'height': size.height},
    'definitionId': definitionId,
    'category': category.name,
  };

  /// The model of a `.pdl` part, drawn by a `DSLComponentPainter`.
  ///
  /// [aliases] replaces the definition's own, for a palette entry that
  /// stands for every configuration of a part and is found by any of their
  /// names.
  factory fromDefinition(PartDefinition def, {List<String>? aliases}) => PartModel(
    name: def.name,
    size: Size(def.visual.width, def.visual.height),
    definitionId: def.id,
    aliases: aliases ?? def.aliases,
    category: PartCategory.fromName(def.category),
    logic: def.logic,
    painterBuilder: ({isOutline = false, properties}) =>
        DSLComponentPainter(definition: def, isOutline: isOutline, properties: properties),
  );

  factory fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String;
    final definitionId = json['definitionId'] as String?;

    // First try standard components
    for (final sc in standardParts) {
      if (sc.name == name) {
        return sc.clone();
      }
    }

    // Then try PDL definitions
    if (definitionId != null) {
      final def = PartRegistry.getPart(definitionId);
      if (def != null) return PartModel.fromDefinition(def);
    }

    // Fallback if missing
    final sizeMap = json['size'] as Map<String, dynamic>;
    final catName = json['category'] as String?;
    final cat = PartCategory.values.firstWhere(
      (e) => e.name == catName,
      orElse: () => PartCategory.other,
    );

    return PartModel(
      name: name,
      size: Size((sizeMap['width'] as num).toDouble(), (sizeMap['height'] as num).toDouble()),
      definitionId: definitionId,
      category: cat,
    );
  }
}

/// Canonical display names for the built-in parts. These strings double as the
/// part *type* identifier across the netlist, SPICE model and parsers, so they
/// must stay in sync with [standardParts] and the `.cdl` templates.
abstract class PartNames {
  static const arduinoUno = 'Arduino Uno';
  static const picoW = 'Raspberry Pi Pico W';
  static const led = 'LED';
  static const resistor = 'Resistor';
  static const pushButton = 'Push Button';
  static const piezoBuzzer = 'Piezo Buzzer';
  static const capacitor = 'Capacitor';
  static const breadboardHalf = 'Half Breadboard';
  static const breadboardFull = 'Full Breadboard';
  static const ky037MicSensor = 'Mic Sensor';
  static const potentiometer = 'Potentiometer';
  static const servoMotor = 'Servo Motor';
  static const oledDisplay = 'OLED Display';
  static const irRemote = 'IR Remote';
}

/// Canonical keys for `ComponentInstance.properties` (the per-component property
/// map). Centralized here so the simulation engine, painters, validators and the
/// property editor agree on the keys instead of re-typing string literals that
/// can silently drift apart.
///
/// Component-side, not part-side, despite living beside [PartModel]: a part
/// *declares* which properties exist, but these are the keys of a placed
/// component's own map — including runtime flags the simulation rewrites every
/// frame, which no catalog entry could hold.
///
/// The map holds two kinds of entries, kept as separate conventions on purpose:
///   * **Runtime flags** — lowercase keys written by the simulation each frame
///     (e.g. [isOn], [hasError]). Not user-editable.
///   * **Display properties** — capitalized keys the user edits in the property
///     panel and which are persisted in `.cdl` templates (e.g. [color],
///     [resistance]).
abstract class ComponentProps {
  // --- Runtime flags (simulation-written) ---

  /// Whether the component is energized/active (LED lit, buzzer sounding).
  static const isOn = 'isOn';

  /// LED brightness as a 0.0–1.0 fraction (the analogWrite/PWM duty cycle).
  static const brightness = 'brightness';

  /// Whether the component is in an error state (e.g. over-current).
  static const hasError = 'hasError';

  /// Whether a digital-output sensor (e.g. mic) currently reads logic-high.
  static const isDigitalHigh = 'isDigitalHigh';

  /// Whether a push button is currently held down.
  static const isPressed = 'isPressed';

  /// Which clickable region of a part is held down right now — a remote's
  /// button, by the id its painter's [BaseComponentPainter.regionAt] gives.
  static const pressedRegion = 'pressedRegion';

  /// Buzzer tone frequency in Hz.
  static const frequency = 'frequency';

  /// Servo horn angle in degrees (0–180), decoded from the signal pulse width.
  static const servoAngle = 'servoAngle';

  /// An OLED display controller's whole decoded state — registers and the 1 KB
  /// of graphics RAM — packed into one base64 string by `Ssd1306Controller`.
  ///
  /// One key rather than twenty, and a string rather than a byte list, because
  /// this map is the *only* memory a part's logic has: it travels to the
  /// canvas each frame and comes back the next. A string compares by value, so
  /// an idle display costs one comparison per frame and queues no redraw; a
  /// `Uint8List` would compare by identity and get this exactly backwards.
  static const oledFrame = 'oledFrame';

  // --- User-editable display properties (persisted in templates) ---

  /// LED color, as a named color string (e.g. `Red`).
  static const color = 'Color';

  /// Resistor value in ohms, as a string (e.g. `220`, `1k`). Units are
  /// tolerated on input — `ResistorCalculator.parseResistanceValue` reads
  /// `220 Ω` too — but not written.
  static const resistance = 'Resistance';

  /// Capacitor value, as a display string (e.g. `100nF`).
  static const capacitance = 'Capacitance';

  /// Potentiometer wiper position, 0.0–1.0 (stored as a string).
  static const potentiometerValue = 'Potentiometer Value';

  /// The address an I²C peripheral answers on, as `0x3C` or a plain number.
  /// The one property a display cannot work without: a module wired correctly
  /// but addressed wrongly stays dark, which is the commonest OLED problem in
  /// the real world too.
  static const i2cAddress = 'I2C Address';

  /// What colour an OLED's lit pixels glow — `White`, `Blue` or `Yellow`,
  /// matching the panels sold. Cosmetic: the panel is monochrome either way.
  static const pixelColor = 'Pixel Color';

  /// Runtime-flag keys the property editor must hide (they are not user-editable).
  /// Includes legacy lowercase keys that may still be present in older `.cdl`
  /// templates (`color`, `drawGlow`) so they never render as editable fields.
  static const runtimeFlags = <String>{
    pressedRegion,
    isOn,
    brightness,
    hasError,
    isDigitalHigh,
    isPressed,
    frequency,
    servoAngle,
    oledFrame,
    'color',
    'drawGlow',
  };
}
