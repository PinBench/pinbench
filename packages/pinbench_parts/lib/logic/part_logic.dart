import 'package:pinbench_pdl/pinbench_pdl.dart';

/// The escape hatch for `.pdl` parts that cannot be expressed declaratively:
/// one frame of Dart behaviour for one placed component.
///
/// `BEHAVIOR` rules are total by design — no loops, no memory beyond declared
/// state, no clock. That covers sensors and passives, and stops short of
/// anything needing real control flow: a one-shot that holds an output for two
/// seconds, a protocol state machine, a lookup table with interpolation. Such
/// a part writes `LOGIC <name>` in its `.pdl` and everything else stays data —
/// artwork, pins, properties, state declarations. Only the behaviour is Dart.
///
/// A logic runs *after* the part's `BEHAVIOR` rules, on the same maps, so a
/// part can declare the easy half and override the hard one without the two
/// fighting.
///
/// A function rather than an interface on purpose. A class would invite a
/// field to remember something between frames — and since a logic is
/// registered once by name, that field would be shared by every placed
/// instance, so two of the same sensor on one canvas would trample each other.
/// Per-component memory belongs in [PartLogicContext.state], which really is
/// per-component.
///
/// Must not block: this runs inside the simulation isolate, on the frame path,
/// for every instance.
typedef PartLogic = void Function(PartLogicContext context);

/// What a [PartLogic] may read and write for one placed component.
class const PartLogicContext({
  /// The `.pdl` definition, or null for a hand-painted part that names a logic
  /// without being data-driven.
  required final PartDefinition? definition,

  /// The component's runtime state, already populated by `BEHAVIOR` rules and
  /// by the previous frame. **Mutable** — write results here and they are
  /// queued to the canvas and carried into the next frame.
  required final Map<String, Object?> state,

  /// User-edited properties. Treat as read-only: writing here would fight the
  /// properties panel and persist into the saved circuit.
  required final Map<String, Object?> properties,

  /// SPICE element parameters — `resistance`, `voltage`, `capacitance`.
  /// **Mutable**; whichever one matches the part's `PHYSICS` type is applied.
  required final Map<String, double> physics,

  /// Simulated time since the run started. Excludes paused time, so a hold
  /// measured against this means simulated seconds — the same clock
  /// `millis()` sees.
  required final Duration elapsed,

  /// Solved voltage on one of this component's pins. 0 V when there is no
  /// circuit, which is what an unconnected pin reads anyway.
  required final double Function(String pinId) analog,

  /// The emulated board: which of this component's ports reach which Arduino
  /// pin, and what those pins are doing.
  ///
  /// This is what lets a peripheral's behaviour move out of the engine. A
  /// servo needs the pulse width on whichever pin its signal line happens to
  /// be wired to — a question about *this circuit*, which the part cannot
  /// answer and the engine should not have to answer on its behalf.
  required final PartPinApi pins,

  /// The analog model, as far as this one component can see it.
  required final PartSpiceApi spice,

  /// The board's I²C bus, as far as this one component can see it.
  final PartI2cApi i2c = const NoI2cBus(),
}) {
  bool digital(String pinId, [double threshold = 2.5]) => analog(pinId) >= threshold;

  /// Reads a numeric property, falling back to [orElse] when it is absent or
  /// not a number — the same forgiving coercion the expression language uses,
  /// so a logic and a rule read a property the same way.
  double number(String id, [double orElse = 0]) {
    final value = properties[id] ?? definition?.properties[id]?.defaultValue;
    return switch (value) {
      final num n => n.toDouble(),
      final bool b => b ? 1 : 0,
      final String s => double.tryParse(s) ?? orElse,
      _ => orElse,
    };
  }

  bool flag(String id, {bool orElse = false}) {
    final value = properties[id] ?? definition?.properties[id]?.defaultValue;
    return switch (value) {
      final bool b => b,
      final num n => n != 0,
      'true' => true,
      'false' => false,
      _ => orElse,
    };
  }
}

/// The analog solve, as far as one placed component can see it.
///
/// Narrow for the same reason as [PartPinApi]: a part may ask about its own
/// element, not about the circuit.
abstract interface class PartSpiceApi {
  /// Whether the analog model runs at all this session. False for a purely
  /// digital circuit, where every reading below is 0.
  bool get isActive;

  /// Current through this component's element, in amps.
  ///
  /// Only meaningful for parts the netlist gave a measuring source — diodes
  /// today. Everything else reads 0, which is also what an unsolved circuit
  /// reads, so a caller needs no special case for either.
  double current();
}

/// The emulated board, as far as one placed component can see it.
///
/// Deliberately narrow: a logic may ask what its own ports are wired to and
/// read what the emulator is doing there. It cannot enumerate the circuit,
/// reach other components, or drive the board — a peripheral that could write
/// the Arduino's pins would be modelling the sketch, not itself.
abstract interface class PartPinApi {
  /// The Arduino pin this component's [portId] is wired to, or null when it
  /// reaches no board pin.
  int? connectedTo(String portId);

  /// The board port this component's [portId] reaches, under the board's own
  /// name for it — `'9'`, `'A4'`, `'5V'`, `'GND_1'` — or null when it reaches
  /// none.
  ///
  /// [connectedTo] answers the same question in the form a *signal* wants (a
  /// pin number to measure), and cannot name anything else: the analog and
  /// power headers are not numbered pins. A bus peripheral needs the other
  /// form, because being on the I²C bus means being on `A4` and `A5`
  /// specifically — the ATmega328P's TWI hardware is wired to those two pads
  /// and nothing else. A display wired to the wrong pins should stay dark
  /// here, exactly as it would on a desk.
  String? boardPortFor(String portId);

  /// PWM duty on [pin], 0..1 — what `analogWrite` last set.
  double duty(int pin);

  /// Width of the last HIGH pulse measured on [pin], in microseconds; 0 if
  /// none has been seen yet.
  ///
  /// Asking also *starts* the measurement: the emulator only tracks pulse
  /// widths on pins it has been told to watch, and a part asking is the only
  /// evidence anyone needs them. The first answer after a fresh request is
  /// therefore 0, which callers already have to handle — a servo holds its
  /// pose until a real pulse arrives.
  double pulseUs(int pin);

  /// Whether [pin] is currently driven HIGH by the sketch.
  bool isHigh(int pin);

  /// The frequency the emulator last detected on [pin], in hertz, or null when
  /// it is not oscillating.
  ///
  /// Asking also asks for detection to *start* there, like [pulseUs]. That
  /// targeting matters more than it looks: frequency detection run across
  /// every toggling pin picks up serial TX and blinking LEDs, which is how you
  /// get audio garbage instead of a tone.
  ///
  /// Only one pin is watched at a time — the emulator detects on a single pin —
  /// so with two sounding parts on a canvas, the last to ask wins.
  double? frequencyOn(int pin);
}

/// The board's I²C bus, as far as one placed component can see it.
///
/// A digital bus is a different shape from every capability beside it. A pin
/// has a *level* a part can sample whenever it likes; a bus has *traffic*, and
/// traffic missed is traffic gone — a display that skipped a frame's worth of
/// bytes would show a corrupt picture forever after. So this hands over a
/// queue rather than a reading, and hands it over exactly once.
///
/// Narrow in the same way as [PartPinApi]: a part may listen at its own
/// address. It cannot see another device's traffic, and it cannot write to the
/// bus — a peripheral that could put bytes on the wire would be modelling the
/// sketch's side of the conversation.
// One method today, and still an interface: it is the seam a fake bus is
// installed at in tests, and the shape the other capability APIs here take.
abstract interface class PartI2cApi() {
  /// Every transaction the sketch has addressed to [address] since the last
  /// call, oldest first, each holding the bytes that followed the address.
  ///
  /// Asking also *starts* the recording, like [PartPinApi.pulseUs]: the
  /// emulator only keeps traffic for addresses some part has claimed, so a bus
  /// nobody listens on costs nothing. The first answer after a fresh claim is
  /// therefore empty, and a display simply keeps the frame it already had.
  List<List<int>> drain(int address);
}

/// The bus a part sees when there is no emulator behind it — in a unit test,
/// or before a run starts. Always silent, never null.
class const NoI2cBus() implements PartI2cApi {
  @override
  List<List<int>> drain(int address) => const [];
}

/// Maps the name in a `LOGIC` line to an implementation.
///
/// A registry rather than a `switch` so a part's logic can live beside the
/// part it serves, and so tests can install a fake without touching shipped
/// behaviour.
abstract final class PartLogicRegistry {
  static final Map<String, PartLogic> _byName = {};

  /// Registers [logic] under [name], replacing any previous entry.
  static void register(String name, PartLogic logic) => _byName[name] = logic;

  /// The logic for [name], or null — an unknown name is not fatal. The part
  /// still draws and still runs whatever `BEHAVIOR` it declared; it simply
  /// does not get its Dart half. `PartBehaviorFrameUpdater` reports it once.
  static PartLogic? find(String name) => _byName[name];

  static Iterable<String> get names => _byName.keys;

  /// Runs [register] once, unless [reset] has since cleared the registry.
  ///
  /// The "already done" flag lives here rather than in the built-ins because
  /// this is where it gets invalidated: a flag owned by the caller survives a
  /// [reset] and leaves the registry permanently empty, which is a fine way
  /// for one test to silently break the next.
  static void ensureBuiltIns(void Function() register) {
    if (_builtInsLoaded) return;
    _builtInsLoaded = true;
    register();
  }

  static var _builtInsLoaded = false;

  /// Test seam — drops every registration, including the built-ins, and lets
  /// [ensureBuiltIns] run again.
  static void reset() {
    _byName.clear();
    _builtInsLoaded = false;
  }
}
