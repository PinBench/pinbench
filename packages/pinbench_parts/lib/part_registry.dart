import 'package:flutter/services.dart';

import 'painters/arduino_painter/arduino_painter.dart';
import 'painters/breadboard_painter/breadboard_painter.dart';
import 'painters/breadboard_painter/configs/breadboard_config.dart';

import 'package:pinbench_pdl/pinbench_pdl.dart';

import 'models/part_model.dart';
import 'painters/led_painter.dart';
import 'painters/push_button_painter.dart';
import 'painters/resistor_painter.dart';
import 'painters/piezo_buzzer_painter.dart';
import 'painters/capacitor_painter.dart';
import 'painters/ky037_mic_sensor_painter.dart';
import 'painters/potentiometer_painter.dart';
import 'painters/servo_motor_painter.dart';
import 'painters/oled_display_painter.dart';
import 'painters/battery_9v_painter.dart';

/// The catalog of data-driven parts, loaded from the `.pdl` files under
/// this package's `assets/parts/`. Built-in parts (the ones with a
/// hand-written painter) are
/// the separate [standardParts] list; `partRegistryProvider` is what merges
/// the two into the one catalog the palette and the parsers see.
class PartRegistry {
  /// Where this package's parts live in the asset manifest.
  ///
  /// Two spellings, because the manifest genuinely differs by who is asking.
  /// An app that depends on this package sees its assets namespaced —
  /// `packages/pinbench_parts/assets/parts/…` — while this package's *own* tests
  /// see them bare, as `assets/parts/…`. Matching only the namespaced form
  /// meant the registry found nothing at all under `flutter test` here, and
  /// reported no diagnostics either, because an empty catalog is not an error.
  static const _namespacedPrefix = 'packages/pinbench_parts/assets/parts/';
  static const _localPrefix = 'assets/parts/';

  static bool _isPartAsset(String key) =>
      (key.startsWith(_namespacedPrefix) || key.startsWith(_localPrefix)) && key.endsWith('.pdl');

  static final Map<String, PartDefinition> _parts = {};

  /// Everything the last [initializeAsync] complained about, keyed by asset.
  ///
  /// Kept rather than logged so `pdl_bundled_parts_test.dart` can assert that
  /// every part shipped in this package loads without a single diagnostic. A
  /// broken `.pdl` used to mean a part that silently did not appear.
  static final Map<String, List<PdlDiagnostic>> diagnostics = {};

  static Future<void> initializeAsync() async {
    _parts.clear();
    diagnostics.clear();
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);

    for (final asset in manifest.listAssets()) {
      if (!_isPartAsset(asset)) continue;
      final source = await rootBundle.loadString(asset);
      final result = PdlParser.parse(
        source,
        // A relative `SVG "foo.svg"` resolves next to the .pdl that named it,
        // so a part is a self-contained directory that can be moved wholesale.
        assetDirectory: asset.substring(0, asset.lastIndexOf('/')),
      );
      if (result.diagnostics.isNotEmpty) diagnostics[asset] = result.diagnostics;
      final def = result.definition;
      if (def == null) continue;
      if (_parts.containsKey(def.id)) {
        diagnostics
            .putIfAbsent(asset, () => [])
            .add(PdlDiagnostic(0, 'duplicate part id "${def.id}" — the earlier one is kept'));
        continue;
      }
      _parts[def.id] = def;
    }
  }

  static PartDefinition? getPart(String id) => _parts[id];

  /// How [part] appears in the analog solve, from whichever source knows.
  ///
  /// Resolved by *type* for the same reason as [logicFor]: a `PartModel` built
  /// by hand carries nothing, and being a resistor is a fact about resistors.
  static SpiceModelDef? spiceFor(PartModel part) {
    if (part.spice != null) return part.spice;

    final definitionId = part.definitionId;
    if (definitionId != null) {
      final model = _parts[definitionId]?.spiceModel;
      if (model != null) return model;
    }

    for (final candidate in standardParts) {
      if (candidate.name == part.name) return candidate.spice;
    }
    return null;
  }

  /// Whether [part] is the microcontroller. Resolved by type, as above.
  static bool isBoard(PartModel part) {
    if (part.isBoard) return true;
    for (final candidate in standardParts) {
      if (candidate.name == part.name) return candidate.isBoard;
    }
    return false;
  }

  /// The simulation logic a [part] should run, from whichever source knows.
  ///
  /// Resolved by *type*, not read off the instance, and that distinction is
  /// load-bearing. A `PartModel` carries its logic name, but only if it came
  /// from the catalog — `clone()` preserves it, while anything that builds a
  /// model by hand (`PartModel.fromJson`'s unknown-part fallback, and every
  /// test fixture) does not. Behaviour belongs to "an LED", not to one
  /// particular LED object, so a hand-built model must not silently stop
  /// behaving.
  static String? logicFor(PartModel part) {
    if (part.logic != null) return part.logic;

    final definitionId = part.definitionId;
    if (definitionId != null) {
      final logic = _parts[definitionId]?.logic;
      if (logic != null) return logic;
    }

    for (final candidate in standardParts) {
      if (candidate.name == part.name) return candidate.logic;
    }
    return null;
  }

  static List<PartDefinition> getAllParts() => _parts.values.toList();
}

final breadboardPainterHalf = BreadboardPainter(config: BreadboardConfig.half());
final breadboardPainterFull = BreadboardPainter(config: BreadboardConfig.full());

final standardParts = <PartModel>[
  PartModel(
    name: PartNames.breadboardHalf,
    size: breadboardPainterHalf.config.boardSize,
    category: PartCategory.boards,
    painterBuilder: ({isOutline = false, properties}) =>
        BreadboardPainter(config: BreadboardConfig.half(), isOutline: isOutline),
  ),
  PartModel(
    name: PartNames.breadboardFull,
    size: breadboardPainterFull.config.boardSize,
    category: PartCategory.boards,
    painterBuilder: ({isOutline = false, properties}) =>
        BreadboardPainter(config: BreadboardConfig.full(), isOutline: isOutline),
  ),
  PartModel(
    name: PartNames.arduinoUno,
    size: ArduinoPainter.componentSize,
    category: PartCategory.microcontrollers,
    isBoard: true,
    painterBuilder: ({isOutline = false, properties}) => ArduinoPainter(isOutline: isOutline),
  ),
  PartModel(
    name: PartNames.led,
    size: LEDPainter.componentSize,
    category: PartCategory.basic,
    // A diode with a 0 V source in series, which is how the netlist measures
    // the current that decides whether it is lit.
    spice: const SpiceModelDef(
      type: SpiceComponentType.diode,
      pinMapping: {'n1': 'anode', 'n2': 'cathode'},
    ),
    // Behaviour is a registered logic; the painter stays hand-written for the
    // glow. See `part_logic_builtins.dart`.
    logic: 'led',
    painterBuilder: ({isOutline = false, properties}) =>
        LEDPainter(isOutline: isOutline, properties: properties),
  ),
  PartModel(
    name: PartNames.resistor,
    size: ResistorPainter.componentSize,
    category: PartCategory.basic,
    spice: const SpiceModelDef(
      type: SpiceComponentType.resistor,
      pinMapping: {'n1': 'left', 'n2': 'right'},
      valueProperty: ComponentProps.resistance,
      defaultValue: 220,
    ),
    painterBuilder: ({isOutline = false, properties}) =>
        ResistorPainter(isOutline: isOutline, properties: properties),
  ),
  PartModel(
    name: PartNames.pushButton,
    size: PushButtonPainter.componentSize,
    category: PartCategory.basic,
    painterBuilder: ({isOutline = false, properties}) =>
        PushButtonPainter(isOutline: isOutline, properties: properties),
  ),
  PartModel(
    name: PartNames.piezoBuzzer,
    size: PiezoBuzzerPainter.componentSize,
    category: PartCategory.actuators,
    logic: 'buzzer',
    painterBuilder: ({isOutline = false, properties}) =>
        PiezoBuzzerPainter(isOutline: isOutline, properties: properties),
  ),
  PartModel(
    name: PartNames.capacitor,
    size: CapacitorPainter.componentSize,
    category: PartCategory.basic,
    painterBuilder: ({isOutline = false, properties}) =>
        CapacitorPainter(isOutline: isOutline, properties: properties),
  ),
  PartModel(
    name: PartNames.ky037MicSensor,
    size: Ky037MicSensorPainter.componentSize,
    category: PartCategory.sensors,
    painterBuilder: ({isOutline = false, properties}) =>
        Ky037MicSensorPainter(isOutline: isOutline, properties: properties),
  ),
  PartModel(
    name: PartNames.potentiometer,
    size: PotentiometerPainter.componentSize,
    category: PartCategory.basic,
    spice: const SpiceModelDef(
      type: SpiceComponentType.potentiometer,
      pinMapping: {'term1': 'term1', 'wiper': 'wiper', 'term2': 'term2'},
      valueProperty: ComponentProps.potentiometerValue,
      defaultValue: 0.5,
      parameters: {'total': 10000},
    ),
    painterBuilder: ({isOutline = false, properties}) =>
        PotentiometerPainter(isOutline: isOutline, properties: properties),
  ),
  PartModel(
    name: PartNames.servoMotor,
    size: ServoMotorPainter.componentSize,
    category: PartCategory.actuators,
    // Behaviour lives in a registered logic rather than in the simulation
    // engine — see `part_logic_builtins.dart`. The painter stays hand-written
    // because a sweeping horn is not something artwork can express.
    logic: 'servo',
    painterBuilder: ({isOutline = false, properties}) =>
        ServoMotorPainter(isOutline: isOutline, properties: properties),
  ),
  PartModel(
    name: PartNames.oledDisplay,
    size: OledDisplayPainter.componentSize,
    category: PartCategory.displays,
    // Electrically inert on purpose: an SSD1306 draws a few milliamps and
    // presents no load worth solving, and its two signal pins carry a digital
    // bus rather than a voltage anyone measures. Everything it does is in the
    // bytes, which is what the logic reads — see `built_in_part_logic.dart`.
    logic: 'ssd1306',
    // The address decides whether the display answers at all, so it has to be
    // visible and editable from the moment the part is dropped.
    defaults: const {ComponentProps.i2cAddress: '0x3C', ComponentProps.pixelColor: 'White'},
    painterBuilder: ({isOutline = false, properties}) =>
        OledDisplayPainter(isOutline: isOutline, properties: properties),
  ),
  PartModel(
    name: PartNames.battery9v,
    size: Battery9vPainter.componentSize,
    category: PartCategory.basic,
    // An ideal source: it does not sag under load or run down. Enough to power
    // a circuit off-board, or to show what 9 V does to an LED with no resistor.
    spice: const SpiceModelDef(
      type: SpiceComponentType.voltageSource,
      pinMapping: {'n1': 'plus', 'n2': 'minus'},
      valueProperty: ComponentProps.voltage,
      defaultValue: 9,
    ),
    defaults: const {ComponentProps.voltage: '9'},
    painterBuilder: ({isOutline = false, properties}) =>
        Battery9vPainter(isOutline: isOutline, properties: properties),
  ),
];
