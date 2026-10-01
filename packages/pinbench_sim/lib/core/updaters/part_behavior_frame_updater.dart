import 'package:flutter/foundation.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_pdl/pinbench_pdl.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_parts/logic/part_logic.dart';
import 'package:pinbench_parts/logic/built_in_part_logic.dart';

import '../board/board_emulator.dart';
import '../circuit_netlist.dart';
import '../engine_pin_api.dart';
import '../spice_engine.dart';

/// Per-frame update for every part whose behaviour is *dispatched* rather than
/// written into the engine.
///
/// This replaced a frame updater per part type — LED, servo, buzzer — each
/// with its own bucket, pin map and last-state maps in `SimulationEngine`.
/// Adding a peripheral no longer means editing the engine.
///
/// **Three updaters deliberately remain, and should.** `AnalogIoFrameUpdater`
/// and `DigitalIoFrameUpdater` are not part behaviour at all: they are the
/// *Arduino's* I/O bridge, feeding solved voltages into its ADC and writing
/// its input pins from the netlist. `MicFrameUpdater` owns a real microphone,
/// a host device like the speaker. Turning any of them into a "part logic"
/// would be a category error — a peripheral that could write the board's pins
/// would be modelling the sketch rather than itself — and the ADC path in
/// particular has no part to attach to. The engine will always know about its
/// host; that is not the coupling this was removing.
///
/// This is what makes a declarative part *simulate* rather than merely draw:
/// each frame it reads the solved pin voltages, runs the part's `BEHAVIOR`
/// rules, pushes any `physics.*` result into ngspice via `alter`, and queues
/// the new `state.*` values back onto the canvas so the painter's `visual.*`
/// bindings redraw.
///
/// It follows the same contract as the hand-written updaters beside it: take
/// the engine's last-emitted state by reference and only queue an update when
/// something actually changed. A part whose light level is constant should
/// cost one map comparison per frame, not a canvas rebuild.
abstract final class PartBehaviorFrameUpdater {
  static void update({
    required List<ComponentInstance> nodes,
    required SpiceEngine spiceEngine,
    required bool isSpiceActive,

    /// Every part's state as of the last frame that changed it — both the
    /// engine's change detection *and* each part's memory between frames.
    ///
    /// The two used to be separate, with the memory living in the node's
    /// property map, and that only ever worked inline: the web engine reads
    /// the same live canvas it writes to, so state came back around. The
    /// isolate's output is write-only, so on native nothing did. Keeping the
    /// memory here works on both, and is also the only copy that is certainly
    /// this run's — the canvas still holds the previous run's final state.
    required Map<LocalKey, Map<String, Object?>> lastState,
    required Duration elapsed,
    required CircuitNetlist netlist,
    required BoardEmulator board,
    required ComponentInstance? boardNode,
    required EmulatorMeasurements measurements,
    required void Function(LocalKey key, Map<String, dynamic> props) queueUpdate,
    void Function(String)? onDebugLog,
  }) {
    for (final node in nodes) {
      // A part may be data-driven (a .pdl definition with rules), Dart-driven
      // (a hand-painted part naming a logic), or both. Only "neither" is
      // skipped — how a part is *drawn* says nothing about whether it behaves.
      final definitionId = node.part.definitionId;
      final definition = definitionId == null ? null : PartRegistry.getPart(definitionId);
      final logicName = PartRegistry.logicFor(node.part);
      final rules = definition?.behavior ?? const [];
      if (rules.isEmpty && logicName == null) continue;

      final result = PdlBehaviorEvaluator.evaluate(
        definition,
        _withoutDeclaredState(definition, node.properties),
        // The engine's own record of the last frame, not the node's property
        // map. Only one of the two `SimulationOutput`s writes updates back
        // onto the nodes — see [lastState] — so the node map is a starting
        // point, and this is the memory.
        previousState: lastState[node.key],
        // Without a solved circuit every pin reads 0 V, which is what an
        // unconnected pin reads anyway — so a part still runs its rules and
        // shows its idle state rather than freezing.
        analog: isSpiceActive ? (pinId) => spiceEngine.getPortVoltage(node.key, pinId) : (_) => 0.0,
      );

      // Dart logic runs *after* the declarative rules, on the same maps, so a
      // part can declare the easy half and override the hard one.
      if (logicName != null) {
        _runLogic(
          name: logicName,
          definition: definition,
          node: node,
          result: result,
          elapsed: elapsed,
          spiceEngine: spiceEngine,
          isSpiceActive: isSpiceActive,
          netlist: netlist,
          board: board,
          boardNode: boardNode,
          measurements: measurements,
          onDebugLog: onDebugLog,
        );
      }

      _applyPhysics(node, definition, result, spiceEngine, isSpiceActive, onDebugLog);
      _applyState(node, result, lastState, queueUpdate);
    }
  }

  /// [properties] without the keys [definition] declares as `STATE`.
  ///
  /// The canvas keeps the last run's final state in each node's property map
  /// (a stopped display keeps its picture), and the evaluator seeds state from
  /// that map. So without this a `.pdl` part started every run where the last
  /// one ended — a PIR still holding, a sensor still configured — although
  /// `STATE` is documented as recreated from its initial value every run.
  /// `lastState` is the memory *within* a run; this is only about where a run
  /// starts. A part with no definition has no declared state to strip: its
  /// logic owns the whole map.
  static Map<String, dynamic> _withoutDeclaredState(
    PartDefinition? definition,
    Map<String, dynamic> properties,
  ) {
    if (definition == null || definition.state.isEmpty) return properties;
    return {
      for (final entry in properties.entries)
        if (!definition.state.containsKey(entry.key)) entry.key: entry.value,
    };
  }

  /// Names already reported as missing, so an unknown `LOGIC` is logged once
  /// rather than sixty times a second for the life of the run.
  static final Set<String> _reportedMissing = {};

  static void _runLogic({
    required String name,
    required PartDefinition? definition,
    required ComponentInstance node,
    required PdlBehaviorResult result,
    required Duration elapsed,
    required SpiceEngine spiceEngine,
    required bool isSpiceActive,
    required CircuitNetlist netlist,
    required BoardEmulator board,
    required ComponentInstance? boardNode,
    required EmulatorMeasurements measurements,
    void Function(String)? onDebugLog,
  }) {
    BuiltInPartLogic.ensureRegistered();
    final logic = PartLogicRegistry.find(name);
    if (logic == null) {
      // Not fatal: the part still draws and still runs its BEHAVIOR. Losing
      // the Dart half quietly is bad; losing the whole part is worse.
      if (_reportedMissing.add(name)) {
        onDebugLog?.call(
          '[warn] ${definition?.id ?? node.part.name} declares logic "$name", '
          'which is not registered',
        );
      }
      return;
    }

    logic(
      PartLogicContext(
        definition: definition,
        state: result.state,
        properties: {...?definition?.defaultProperties(), ...node.properties},
        physics: result.physics,
        elapsed: elapsed,
        analog: isSpiceActive ? (pinId) => spiceEngine.getPortVoltage(node.key, pinId) : (_) => 0.0,
        pins: EnginePinApi(
          node: node,
          netlist: netlist,
          board: board,
          boardNode: boardNode,
          measurements: measurements,
        ),
        spice: EngineSpiceApi(node: node, spiceEngine: spiceEngine, isActive: isSpiceActive),
        i2c: EngineI2cApi(board),
      ),
    );
  }

  static void _applyPhysics(
    ComponentInstance node,
    PartDefinition? definition,
    PdlBehaviorResult result,
    SpiceEngine spiceEngine,
    bool isSpiceActive,
    void Function(String)? onDebugLog,
  ) {
    if (!isSpiceActive || result.physics.isEmpty) return;
    final element = spiceEngine.pdlElementFor(node.key);
    if (element == null) return;

    // One element, one alterable value: ngspice's `alter <name> = <v>` sets an
    // element's principal value, so a part maps to exactly one of these.
    // Whichever parameter its PHYSICS type uses is the one that applies.
    final value = switch (definition?.spiceModel?.type) {
      SpiceComponentType.resistor => result.physics['resistance'],
      SpiceComponentType.voltageSource => result.physics['voltage'],
      SpiceComponentType.capacitor => result.physics['capacitance'],
      SpiceComponentType.spdt => result.physics['position'],
      _ => null,
    };
    if (value == null || !value.isFinite) return;

    // An SPDT is the one type that is two elements thrown by one value.
    final changed = definition?.spiceModel?.type == SpiceComponentType.spdt
        ? spiceEngine.setSwitchPosition(element, value)
        : spiceEngine.setElementValue(element, value);
    if (changed) {
      onDebugLog?.call(
        '[Debug] ${definition?.id ?? node.part.name} $element = ${value.toStringAsFixed(3)}',
      );
    }
  }

  static void _applyState(
    ComponentInstance node,
    PdlBehaviorResult result,
    Map<LocalKey, Map<String, Object?>> lastState,
    void Function(LocalKey key, Map<String, dynamic> props) queueUpdate,
  ) {
    if (result.state.isEmpty) return;

    // Compared against the engine's own last-emitted map rather than the
    // node's properties: the cached node goes stale the moment an update
    // replaces it, and comparing against stale values is how a re-run gets
    // stuck showing the previous run's final state.
    final previous = lastState[node.key];
    if (previous != null && mapEquals(previous, result.state)) return;

    lastState[node.key] = Map<String, Object?>.from(result.state);
    queueUpdate(node.key, Map<String, dynamic>.from(result.state));
  }
}
