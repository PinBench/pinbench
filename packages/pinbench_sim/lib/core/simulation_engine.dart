import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:pinbench_parts/models/board_profile.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/logic/ir_remote_keys.dart';
import 'package:pinbench_parts/part_registry.dart';

import 'sim_log.dart';
import 'board/board_emulator.dart';
import 'circuit_netlist.dart';
import 'sim_io.dart';
import 'updaters/analog_io_frame_updater.dart';
import 'updaters/digital_io_frame_updater.dart';
import 'engine_pin_api.dart';
import 'updaters/part_behavior_frame_updater.dart';
import 'updaters/ir_link.dart';
import 'updaters/mic_frame_updater.dart';
import 'simulation_output.dart';
import 'spice_engine.dart';
import 'wire_current_solver.dart';
import '../config/avr_config.dart';
import '../config/sim_constants.dart';
import '../diagnostics/frame_profiler.dart';
import '../models/simulation_snapshot.dart';

/// Pure simulation loop with no dependency on CanvasController.
///
/// All canvas reads/writes are mediated through the SimulationOutput
/// interface, making this class independently unit-testable.
class SimulationEngine({
  required final SimulationOutput _output,
  final void Function(String)? onSerialPrint,
  final void Function(String)? onSpiceLog,
  final void Function(String)? onDebugLog,

  /// Emitted when the detected buzzer tone changes (Hz, or null when it stops).
  /// The owner turns this into actual audio on the UI isolate.
  final void Function(double? hz)? onBuzzerFrequency,

  /// Per-wire current in amps keyed by wire id, signed so a positive value runs
  /// from the wire's `start` port to its `end`. Fired only when the values have
  /// actually moved, and with a fresh map each time (the solver reuses its own).
  ///
  /// Supplying this callback is what turns the current calculation on at all —
  /// it is the only consumer, so a headless run never pays for it.
  final void Function(Map<String, double> currents)? onWireCurrents,

  /// Rolling frame-stats callback, fired periodically (~1 Hz) so the owning
  /// isolate can export performance data to telemetry. Receives the current
  /// profiler rolling averages.
  final void Function(FrameStats stats)? onFrameStats,

  /// The circuit's live warnings — today a supply rail delivering more than
  /// its rating — as one message each, or an empty list once none apply.
  /// Fired only when the set changes, so a steady overload costs nothing
  /// after the first frame that finds it.
  final void Function(List<String> warnings)? onCircuitWarnings,

  /// Optional profiler. Assign profiler.enabled = true to start
  /// collecting per-frame timing. Zero overhead when disabled.
  final FrameProfiler? profiler,
  MicInput? micInput,
}) {
  static const _log = SimLog('app.simulation.engine');

  /// Latest microphone reading, injected so the engine never touches the audio
  /// plugins directly (it may run in a background isolate). Defaults to silence.
  final MicInput _micInput = micInput ?? const SilentMicInput();

  var _isSimulating = false;
  bool get isSimulating => _isSimulating;
  var _isPaused = false;
  bool get isPaused => _isPaused;

  // Run lifecycle guards. [_runGeneration] is bumped on every [start]; each
  // [_runLoop] captures its generation and exits the instant a newer run begins,
  // so two loops can NEVER tick the shared AVR + ngspice state at once (the cause
  // of the "blink stops working after a re-run" bug). [_loopDone] lets a new run
  // await the previous loop's full teardown before reconfiguring native state.
  var _runGeneration = 0;
  Future<void>? _loopDone;
  var _activeLoops = 0;

  /// Number of run loops currently executing. Invariant: never exceeds 1.
  /// Exposed for regression tests that assert the single-loop guarantee.
  @visibleForTesting
  int get activeLoopCount => _activeLoops;

  /// The current run loop's completion future (null when stopped). Lets tests
  /// await a clean stop deterministically.
  @visibleForTesting
  Future<void>? get loopDone => _loopDone;

  late CircuitNetlist _netlist;
  late SpiceEngine _spiceEngine;

  /// Turns solved element currents into a current for every drawn wire. Null
  /// when nothing is listening, so a run with no flow overlay pays nothing.
  WireCurrentSolver? _wireCurrents;

  /// Last per-wire currents handed to [onWireCurrents], so an unchanged circuit
  /// costs a comparison rather than a message across the isolate boundary.
  final Map<String, double> _lastWireCurrents = {};

  // Per-frame update batch — reset each frame, flushed once at frame end.
  final _frameUpdates = <LocalKey, Map<String, dynamic>>{};

  // Frame counter for periodic profiler stats emission (~1 Hz).
  var _frameCount = 0;

  /// Simulated time since this run started, in microseconds.
  ///
  /// Accumulated from the same clamped delta the AVR is advanced by, so it
  /// tracks emulated time rather than wall time — paused seconds do not count,
  /// exactly as they do not for `millis()`. A `LOGIC` behaviour that holds an
  /// output for two seconds must mean two *simulated* seconds, or pausing the
  /// run would silently expire it.
  var _runElapsedUs = 0;

  /// Whether this run's parts have had their power-on pass — see [runFrame].
  var _partsPoweredOn = false;

  /// Last-seen state of everything that can change circuit *connectivity*
  /// mid-run, so the adjacency map is only rebuilt when it actually moved.
  ///
  /// Replaced wholesale each frame rather than mutated in place like the other
  /// last-state maps, because the updater that computes it returns it.
  Map<LocalKey, bool> _lastTopologyState = {};

  // Last seen on-board LED (`LED_BUILTIN`) state, tracked across frames so a
  // change can be pushed to the board node. A field (rather than a [_runLoop]
  // local) so that a single frame can be stepped in isolation via [runFrame].
  var _lastBuiltinLedState = false;

  /// The chip running the sketch, picked for the board on the canvas when a
  /// run starts. An Uno until then — and for a canvas with no board at all,
  /// which is what a run without one always got.
  var _board = BoardEmulator.forProfile(BoardProfile.arduinoUno);

  BoardProfile get _profile => _board.profile;

  /// The board [_boardNode] is, or the Uno for a canvas without one.
  BoardProfile get _canvasProfile {
    final node = _boardNode;
    return (node == null ? null : BoardProfile.of(node.part)) ?? BoardProfile.arduinoUno;
  }

  /// A fresh emulator for the board on the canvas. Called as a run starts,
  /// after [_indexNodes], and never on a mid-run rebuild: the program is
  /// already loaded into the one there is.
  void _pickBoard() => _board = BoardEmulator.forProfile(_canvasProfile);

  // Engine-owned "last emitted visual state" per node, keyed by node key. These
  // are the source of truth for change detection — NOT the canvas node's
  // properties. [_output.applyNodeUpdates] replaces node objects (copyWith), so
  // the cached references in the buckets below go stale after the first flush;
  // reading their `.properties` back would compare against frozen state and is
  final Map<LocalKey, bool> _lastMicHigh = {};
  // Last analog-input voltage emitted per ADC channel, to throttle debug logs.
  final Map<int, double> _lastAnalog = {};

  // LED node key -> the Arduino digital pin driving it (if any), traced from the
  // netlist on build. Lets PWM (analogWrite) duty modulate LED brightness.

  // Whether the analog (SPICE) model produces anything observable this run.
  // Its results are only read through LED currents and analog-pin voltages, so
  // a circuit with no LED, no connected A0–A5 input and no mic sensor (e.g. a
  // bare pin-13 blink) gets zero per-frame SPICE cost. Recomputed on each build.
  var _isSpiceActive = true;

  /// Whether the per-frame SPICE solve runs this session (false when nothing
  /// observes the analog model). Exposed for tests.
  @visibleForTesting
  bool get isSpiceActive => _isSpiceActive;

  // Per-run node index + typed buckets, rebuilt on start/rebuild. Node
  // *membership* is frozen for a run (the canvas is read-only while simulating),
  // so these buckets are safe for iterating topology and reading the stable
  // `key`/`part`. They must NOT be used to read live `properties` —
  // see the last-state maps above.
  final Map<LocalKey, ComponentInstance> _nodesByKey = {};
  ComponentInstance? _boardNode;
  final List<ComponentInstance> _micSensors = [];
  final List<ComponentInstance> _buttons = [];

  /// Nodes backed by a `.pdl` definition that declares BEHAVIOR rules. Kept as
  /// its own bucket for the same reason as the others: the frame loop indexes
  /// rather than rescanning every node and re-reading the registry.
  final List<ComponentInstance> _behaviourNodes = [];

  /// Last state map emitted per PDL node, so an unchanged part costs a map
  /// comparison rather than a canvas update.
  final Map<LocalKey, Map<String, Object?>> _lastBehaviourState = {};

  /// Pins a part's logic has asked to have pulse-measured this run.
  final _measurements = EmulatorMeasurements();

  /// Rebuilds [_nodesByKey] and the typed buckets from the current canvas
  /// snapshot. Called on start/rebuild so per-frame helpers index instead of
  /// rescanning + filtering the whole node list every frame.
  void _indexNodes() {
    _nodesByKey.clear();
    _micSensors.clear();
    _buttons.clear();
    _behaviourNodes.clear();
    _lastBehaviourState.clear();
    _measurements.clear();
    _boardNode = null;
    // Drop last-emitted visual state so a fresh run re-evaluates every node from
    // scratch instead of comparing against the previous run's final state.
    _lastMicHigh.clear();
    _lastAnalog.clear();
    _lastTopologyState = {};
    _lastBuiltinLedState = false;
    _runElapsedUs = 0;
    _partsPoweredOn = false;
    for (final node in _output.simulationNodes) {
      _nodesByKey[node.key] = node;

      // Parts whose behaviour is dispatched rather than hard-coded here: a
      // .pdl part with rules or a LOGIC line, or any part — hand-painted
      // included — that names a logic on its PartModel. Checked before the
      // name-based buckets below, which is the list this is meant to shrink.
      final definitionId = node.part.definitionId;
      final definition = definitionId == null ? null : PartRegistry.getPart(definitionId);
      final hasRules = definition?.behavior.isNotEmpty ?? false;
      if (hasRules || PartRegistry.logicFor(node.part) != null) {
        _behaviourNodes.add(node);
      }

      final name = node.part.name;
      if (PartRegistry.isBoard(node.part)) {
        _boardNode = node;
      } else if (name == PartNames.ky037MicSensor) {
        _micSensors.add(node);
      } else if (name == PartNames.pushButton) {
        _buttons.add(node);
      }
    }
  }

  void stop() {
    final wasSimulating = _isSimulating;
    _isSimulating = false;
    _isPaused = false;
    if (wasSimulating) onDebugLog?.call('[Run] Simulation stopped.');
    _board.buzzerPin = null;
    // Drop pulse-measurement requests: a part's logic re-registers whichever
    // pins it needs on the next run, so a stale set would have the emulator
    // measuring pins nothing is watching.
    _board.servoPins = const [];
    final stopUpdates = <LocalKey, Map<String, dynamic>>{};
    for (final node in _output.simulationNodes) {
      if (PartRegistry.isBoard(node.part)) {
        // The board's own LED goes out with the sketch.
        stopUpdates[node.key] = {ComponentProps.isOn: false};
      } else if (node.part.name == PartNames.led || node.part.name == PartNames.piezoBuzzer) {
        final props = Map<String, dynamic>.from(node.properties);
        props[ComponentProps.isOn] = false;
        props[ComponentProps.hasError] = false;
        stopUpdates[node.key] = props;
      } else if (node.part.name == PartNames.ky037MicSensor) {
        final props = Map<String, dynamic>.from(node.properties);
        props[ComponentProps.isDigitalHigh] = false;
        stopUpdates[node.key] = props;
      }
    }
    _output.applyNodeUpdates(stopUpdates);
    // Nothing is flowing once the run ends, so say so — otherwise the canvas
    // keeps the last frame's currents and the wires animate over a dead circuit.
    if (wasSimulating && _lastWireCurrents.isNotEmpty) {
      _lastWireCurrents.clear();
      onWireCurrents?.call(const {});
    }
    // An overload belongs to the run that drew it.
    if (_overloadedRails.isNotEmpty) {
      _overloadedRails.clear();
      onCircuitWarnings?.call(const []);
    }
  }

  Future<void> start(String compiledHex, {required void Function() onStop}) async {
    // Make start fully idempotent: supersede + tear down any in-flight run before
    // touching the shared AVR/ngspice state, so a quick stop→start (or a
    // double-start) can never leave two run loops ticking the emulator at once.
    final generation = ++_runGeneration;
    await _haltRunningLoop();

    _isSimulating = true;
    _isPaused = false;
    _indexNodes();
    _pickBoard();
    _buildCircuit();

    final nodes = _output.simulationNodes;
    final wires = _output.simulationWires;

    onDebugLog?.call(
      '[Run] Circuit ready: ${nodes.length} components, ${wires.length} wires '
      '(behaviour-driven: ${_behaviourNodes.length}, buttons: ${_buttons.length}, '
      'mic: ${_micSensors.length}).',
    );
    if (_boardNode == null) {
      onDebugLog?.call('[Run] Warning: no board found on the canvas.');
    }

    _connectToneDetector();

    _loopDone = _runLoop(compiledHex, generation, onStop);
  }

  /// Stops the running loop (if any) and awaits its full teardown. Called before
  /// a new run so native state is never reconfigured under a live loop.
  Future<void> _haltRunningLoop() async {
    _isSimulating = false;
    _isPaused = false;
    final done = _loopDone;
    _loopDone = null;
    if (done != null) {
      try {
        await done;
      } catch (_) {
        // A crashing loop must not block the next run from starting.
      }
    }
  }

  /// Sends [text] to the running sketch's serial receiver (Serial.read /
  /// Serial.available). No-op when the simulation is not running.
  void sendSerialInput(String text) {
    if (_isSimulating) _board.queueSerialInput(text);
  }

  /// Applies properties the user changed mid-run to the engine's own copy of
  /// each part, [byNode] keyed by node id.
  ///
  /// The engine holds copies — the isolate's, rehydrated at start, or on the
  /// web the node objects as they were when the circuit was indexed, which the
  /// canvas has since replaced — so an edit reaches it only this way. Merged
  /// rather than replaced: what the simulation itself wrote stays.
  void applyPropertyEdits(Map<String, Map<String, dynamic>> byNode) {
    if (!_isSimulating) return;
    for (final node in _nodesByKey.values) {
      final edits = byNode[nodeKeyToId(node.key)];
      if (edits != null) node.properties.addAll(edits);
    }
  }

  /// Something a part's own control did — a remote's [event] button pressed —
  /// for the part [nodeId] names. No-op when the simulation is not running.
  void handlePartEvent(String nodeId, String event) {
    if (!_isSimulating) return;
    final node = _nodesByKey.values.where((n) => nodeKeyToId(n.key) == nodeId).firstOrNull;
    if (node == null) return;
    if (node.part.name == PartNames.irRemote) {
      final command = IrRemoteKeys.commands[event];
      if (command == null) return;
      final pins = IrLink.transmit(
        address: IrRemoteKeys.address,
        command: command,
        nodes: _nodesByKey.values.toList(),
        netlist: _netlist,
        board: _board,
        boardNode: _boardNode,
      );
      onDebugLog?.call(
        '[Debug] IR $event (0x${command.toRadixString(16).padLeft(2, '0')}) → '
        '${pins.isEmpty ? 'no powered receiver' : 'pin ${pins.join(', ')}'}',
      );
    }
  }

  void pause() {
    if (_isSimulating) _isPaused = true;
  }

  void resume() {
    if (_isSimulating) _isPaused = false;
  }

  /// Rebuilds the circuit netlist and SPICE model from the current canvas
  /// state without recompiling the Arduino sketch.
  ///
  /// Safe to call while the simulation is running — Dart's single-threaded
  /// model guarantees this executes between frame await points, so the
  /// next frame sees the fresh netlist immediately.
  void rebuildCircuit() {
    if (!_isSimulating) return;

    _indexNodes();
    _buildCircuit();
    _lastTopologyState = {};
  }

  /// Builds the two netlists, the SPICE model and the wire-current solver from
  /// the current canvas snapshot. Shared by [start], [rebuildCircuit] and
  /// [prepareForFrameStepping], which must all produce the same model.
  void _buildCircuit() {
    final nodes = _output.simulationNodes;
    final wires = _output.simulationWires;

    _netlist = CircuitNetlist();
    _netlist.buildStatic(nodes, wires);

    // SPICE needs resistors as real 2-node elements (not bridged), so it gets a
    // dedicated netlist; [_netlist] stays bridged for digital connectivity.
    final spiceNetlist = CircuitNetlist()..buildStatic(nodes, wires, bridgeResistors: false);
    _spiceEngine = SpiceEngine(onLog: onSpiceLog);
    _spiceEngine.build(spiceNetlist, nodes);

    // The flow solver walks the same un-bridged graph SPICE was built from, so
    // a resistor stays a two-terminal element there too — a bridged netlist
    // would merge its legs and hide it from the current accounting entirely.
    _wireCurrents = onWireCurrents == null
        ? null
        : WireCurrentSolver(spiceNetlist, wires, boardKey: _boardNode?.key);
    _lastWireCurrents.clear();

    _recomputeSpiceActive();
  }

  /// Captures the current simulation state for debugging.
  /// Only valid while [isSimulating] is true.
  SimulationSnapshot captureSnapshot() => SimulationSnapshot(
    pinStates: {for (final p in _profile.digitalPins) p: _board.getPinState(p)},
    ledCurrents: {
      for (final key in _spiceEngine.measuredElementKeys) key: _spiceEngine.getLedCurrent(key),
    },
    cpuCycles: _board.getCycles(),
  );

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Decides whether the per-frame SPICE solve is worth running. The solve's
  /// output is only consumed via LED currents and analog-pin voltages (and mic
  /// sensors feed the analog model), so with none of those present the solve is
  /// pure overhead and is skipped. Must run after [_indexNodes] + SPICE build.
  void _recomputeSpiceActive() {
    final board = _boardNode;
    final hasAnalogInput =
        board != null &&
        _canvasProfile.analogInputPorts.any((p) => _spiceEngine.isPortConnected(board.key, p));
    // "Did the netlist produce any part element" rather than "are there LEDs":
    // the LED bucket is gone, and this is the question that was always being
    // asked through it.
    _isSpiceActive = _spiceEngine.hasPartElements || _micSensors.isNotEmpty || hasAnalogInput;
  }

  /// Solves the drawn wires' currents from the operating point just computed
  /// and reports them, but only when they moved enough to see.
  ///
  /// The threshold is relative, not absolute, because the interesting range
  /// spans five decades: a 2% wobble on 20 mA is invisible, while a whole
  /// microamp appearing where there was nothing is the difference between a
  /// dead wire and a live one. Without it a PWM pin would send a full map
  /// across the isolate boundary 60 times a second for no visible change.
  void _emitWireCurrents() {
    final solver = _wireCurrents;
    final report = onWireCurrents;
    if (solver == null || report == null) return;

    final currents = solver.solve(_spiceEngine.portInjections());
    if (currents.length == _lastWireCurrents.length) {
      var moved = false;
      for (final entry in currents.entries) {
        final previous = _lastWireCurrents[entry.key];
        if (previous == null) {
          moved = true;
          break;
        }
        final delta = (entry.value - previous).abs();
        final scale = previous.abs() > entry.value.abs() ? previous.abs() : entry.value.abs();
        if (delta > SimConstants.wireCurrentEpsilon && delta > scale * 0.02) {
          moved = true;
          break;
        }
      }
      if (!moved) return;
    }

    _lastWireCurrents
      ..clear()
      ..addAll(currents);
    // A copy: the solver reuses its result map, and this one crosses an isolate.
    report(Map<String, double>.from(currents));
  }

  /// The rails last reported over their rating, so the warning goes out once
  /// when a rail crosses its limit and once when it comes back.
  final Set<String> _overloadedRails = {};

  /// Compares each supply rail's solved current with what the board can
  /// deliver from it, and reports the set when it changes.
  ///
  /// A rail sources current out of the board, which [SpiceEngine.portCurrent]
  /// reads as negative; a rail being back-driven by something else is not an
  /// overload of it.
  void _checkSupplyRails() {
    final report = onCircuitWarnings;
    final board = _boardNode;
    if (report == null || board == null) return;
    final profile = _canvasProfile;

    final over = <String, double>{};
    for (final MapEntry(key: rail, value: limit) in profile.supplyLimits.entries) {
      if (!_spiceEngine.isPortConnected(board.key, rail)) continue;
      final amps = -_spiceEngine.portCurrent(board.key, rail);
      if (amps > limit) over[rail] = amps;
    }
    if (over.length == _overloadedRails.length && over.keys.every(_overloadedRails.contains)) {
      return;
    }
    _overloadedRails
      ..clear()
      ..addAll(over.keys);
    report([
      for (final MapEntry(key: rail, value: amps) in over.entries)
        _railWarning(profile, rail, amps),
    ]);
  }

  static String _railWarning(BoardProfile board, String rail, double amps) =>
      "The ${board.partName}'s $rail supply is delivering ${(amps * 1000).round()} mA, "
      'more than the ${(board.supplyLimits[rail]! * 1000).round()} mA it is rated for. '
      'On a real board it would sag, cut out or overheat.';

  void _queueNodeUpdate(LocalKey key, Map<String, dynamic> props) {
    _frameUpdates[key] = props;
  }

  void _flushFrameUpdates() {
    if (_frameUpdates.isEmpty) return;
    // Both [SimulationOutput] implementations consume [updates] synchronously —
    // the canvas controller iterates it into a fresh node list, and the isolate
    // output re-maps it into a new payload before sending — so neither retains
    // the reference. That lets us hand over the live map and clear it right
    // after, avoiding a per-frame defensive copy (~60 allocations/sec).
    _output.applyNodeUpdates(_frameUpdates);
    _frameUpdates.clear();
  }

  void _updateMicSensors() => MicFrameUpdater.update(
    board: _board,
    micInput: _micInput,
    micSensors: _micSensors,
    spiceEngine: _spiceEngine,
    lastMicHigh: _lastMicHigh,
    queueUpdate: _queueNodeUpdate,
  );

  /// Feeds solved circuit voltages at the board's analog pins (the Uno's A0–A5,
  /// the Pico's GP26–28) into the ADC so `analogRead()` reflects external
  /// voltages (dividers, sensors, pots). Skips channel 0 when a mic sensor owns
  /// it. Must run after [SpiceEngine.solve].
  void _updateAnalogInputs() => AnalogIoFrameUpdater.update(
    board: _board,
    boardNode: _boardNode,
    micOwnsA0: _micSensors.isNotEmpty,
    spiceEngine: _spiceEngine,
    lastAnalog: _lastAnalog,
    onDebugLog: onDebugLog,
  );

  /// Reads from the live `_output.simulationNodes` rather than the cached
  /// `_buttons` bucket: a press replaces the node object (copyWith), so the
  /// cached reference would never reflect one made mid-run.
  void _updateDigitalInputs() {
    _lastTopologyState = DigitalIoFrameUpdater.update(
      simulationNodes: _output.simulationNodes,
      lastTopologyState: _lastTopologyState,
      netlist: _netlist,
      board: _board,
      boardNode: _boardNode,
      nodesByKey: _nodesByKey,
      micIsDigitalHigh: _micInput.isDigitalHigh,
    );
  }

  void _updateBehaviourParts({bool circuitSolved = true}) {
    PartBehaviorFrameUpdater.update(
      nodes: _behaviourNodes,
      spiceEngine: _spiceEngine,
      isSpiceActive: circuitSolved && _isSpiceActive,
      lastState: _lastBehaviourState,
      elapsed: Duration(microseconds: _runElapsedUs),
      netlist: _netlist,
      board: _board,
      boardNode: _boardNode,
      measurements: _measurements,
      queueUpdate: _queueNodeUpdate,
      onDebugLog: onDebugLog,
    );
    // Push any newly requested pulse measurements to the emulator. Deferred to
    // here rather than done per call so one reconfigure covers every part that
    // asked this frame.
    _measurements.flush(_board);
  }

  /// The real-time run loop for one simulation [generation]. Exits the moment
  /// the engine is stopped OR a newer run supersedes this one (a newer
  /// [_runGeneration]); only the still-current generation reports [onStop], so a
  /// superseded loop never tears down the run that replaced it.
  Future<void> _runLoop(String compiledHex, int generation, void Function() onStop) async {
    _activeLoops++;
    // Self-enforcing invariant: if a future refactor ever lets two loops run,
    // this trips immediately in debug/tests rather than silently double-ticking
    // the emulator (the root cause of the blink-after-restart bug).
    assert(_activeLoops == 1, 'Two simulation run loops are active at once');
    try {
      final profile = _profile;
      try {
        _board.loadHex(compiledHex, onSerialPrint: onSerialPrint);
      } on FormatException catch (e) {
        onSerialPrint?.call('Error loading HEX: ${e.message}');
        _isSimulating = false;
        return;
      } catch (e) {
        onSerialPrint?.call('Error loading HEX: $e');
        _isSimulating = false;
        return;
      }

      onSerialPrint?.call('Running the sketch on the emulated ${profile.partName}...');
      onDebugLog?.call(
        '[Run] Simulation started (${profile.partName} @ ${profile.clockHz ~/ 1000000} MHz).',
      );

      bool stillCurrent() => _isSimulating && generation == _runGeneration;

      final usPerCycle = 1000000 / profile.clockHz;
      // Cap the catch-up per frame so a throttled/backgrounded tab (whose timers
      // stall for seconds) can't trigger a multi-second cycle burst that freezes
      // the UI; the sim just resumes slightly behind wall-clock instead.
      const maxStepUs = 50000; // 50ms ≈ 3 frames at 60fps
      // On the web the engine runs inline on the UI isolate, so rate-limit the
      // (heavy) SPICE solve to keep frames short; native runs in its own isolate
      // and can solve every frame.
      const spiceIntervalUs = kIsWeb ? 33000 : 0; // ~30fps on web

      final clock = Stopwatch()..start();
      var lastTickUs = clock.elapsedMicroseconds;
      var lastSpiceUs = lastTickUs - spiceIntervalUs;

      while (stillCurrent()) {
        if (_isPaused) {
          while (stillCurrent() && _isPaused) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          if (!stillCurrent()) break;
          // Don't count paused wall-time as elapsed AVR time.
          lastTickUs = clock.elapsedMicroseconds;
        }

        final nowUs = clock.elapsedMicroseconds;
        var deltaUs = nowUs - lastTickUs;
        lastTickUs = nowUs;
        if (deltaUs > maxStepUs) deltaUs = maxStepUs;
        if (deltaUs <= 0) deltaUs = AVRConfig.frameBudgetMs * 1000;

        // Advance the chip by the real time elapsed so millis()/delay() — and
        // therefore clap-interval timing and rhythm playback — track wall-clock.
        final cycles = (deltaUs / usPerCycle).round();
        _runElapsedUs += deltaUs;

        final solveSpice = nowUs - lastSpiceUs >= spiceIntervalUs;
        if (solveSpice) lastSpiceUs = nowUs;

        try {
          final workUs = runFrame(cycles: cycles, solveSpice: solveSpice);
          final remainingMs = AVRConfig.frameBudgetMs - (workUs ~/ 1000);
          await Future<void>.delayed(
            remainingMs > 0 ? Duration(milliseconds: remainingMs) : Duration.zero,
          );
        } catch (e, stack) {
          final msg = 'Emulator/SPICE crashed: $e\n$stack';
          _log.error('Emulator/SPICE crashed', error: e, stackTrace: stack);
          onSerialPrint?.call(msg);
          onSpiceLog?.call(msg);
          break;
        }
      }
    } finally {
      _activeLoops--;
    }

    // Report the stop only if we are still the active run. A superseded loop
    // (replaced by a newer start) stays silent so it can't stop the new run.
    if (generation == _runGeneration) onStop();
  }

  /// Executes a single simulation frame: digital inputs → AVR tick → SPICE
  /// solve → LED/visual updates, flushing all canvas writes once at the end.
  /// Returns the wall-clock microseconds the frame took (used by [_runLoop] to
  /// pace itself).
  ///
  /// Extracted from the run loop so the simulation can be stepped
  /// deterministically — one fixed slice (a 60th of a second by default) at a time,
  /// independent of real-time pacing — from tests (see [prepareForFrameStepping]).
  @visibleForTesting
  int runFrame({int? cycles, bool solveSpice = true}) {
    final sw = Stopwatch()..start();

    // 0. Power the parts on before the CPU's first instruction. Parts normally
    // run after the tick (step 7), which is too late for a sensor on the first
    // frame: `setup()` probes the bus straight away, and a device that has not
    // yet `serve`d its registers is NACKed, so `Adafruit_MPU6050.begin()` and
    // friends report "chip not found" and never retry. On a desk the sensor is
    // powered as soon as the board is.
    // Nothing has been solved yet, so the pass sees the analog model as off:
    // an LED asking ngspice for its current now would find no result vector.
    if (!_partsPoweredOn) {
      _partsPoweredOn = true;
      if (_behaviourNodes.isNotEmpty) _updateBehaviourParts(circuitSolved: false);
    }

    // 1. Update digital inputs (push buttons → netlist → board pins)
    _updateDigitalInputs();

    // 2. Inject mic sensor state into the ADC and SPICE
    _updateMicSensors();
    final inputsDoneUs = sw.elapsedMicroseconds;

    // 3. Tick the emulator. The cycle count is normally the wall-clock time
    // elapsed since the last frame (see [_runLoop]) so the emulator tracks real
    // time even when the host can't sustain 60fps; tests pass a fixed slice.
    final profile = _profile;
    _board.tick(cycles ?? profile.clockHz ~/ AVRConfig.targetFps);
    final avrDoneUs = sw.elapsedMicroseconds;

    // 4. Read digital pin states and update SPICE voltage sources. A PWM pin is
    // high only part of the time; we drive SPICE to the full logic level whenever
    // its duty is non-zero so the LED conducts at full current, and let the
    // measured duty modulate the rendered brightness (see _updateAnalogLeds).
    // A pin the sketch has not made an output is driven at all, so it goes
    // high-impedance rather than holding its net at 0 V.
    // Skipped entirely when nothing observes the analog model this run.
    if (_isSpiceActive) {
      for (final pin in profile.digitalPins) {
        _spiceEngine.setPinDrive(
          '$pin',
          voltage: _board.getPinDuty(pin) > 0 ? profile.logicHighVolts : SimConstants.logicLowVolts,
          isOutput: _board.isPinOutput(pin),
        );
      }
    }

    // The board's own LED (`LED_BUILTIN`). Drawn by boards whose painter
    // follows it — the Pico's — and logged for diagnostics either way. Safe to
    // write to the node: `isOn` is a runtime flag, which the `.cdl` writer
    // leaves out (an older version of this wrote a `13: "..."` key, which
    // leaked into the saved file and marked it dirty after every run).
    final isLedOn = _board.isBuiltinLedOn;
    if (isLedOn != _lastBuiltinLedState) {
      onDebugLog?.call(
        '[Debug] Built-in LED (pin ${profile.builtinLedPin}) changed to: $isLedOn'
        ' (cycles: ${_board.getCycles()})',
      );
      _lastBuiltinLedState = isLedOn;
      final board = _boardNode;
      if (board != null) {
        _queueNodeUpdate(board.key, {ComponentProps.isOn: isLedOn});
      }
    }

    // 6. Solve the analog circuit so getLedCurrent()/getPortVoltage() return a
    // fresh op result. SpiceEngine only issues alter commands for pins whose
    // voltage actually changed, keeping each op fast. Skipped when no LED,
    // analog input or mic observes the result (e.g. a bare pin-13 blink).
    // The SPICE solve is the heaviest per-frame step. It only drives analog
    // reads and LED visuals — not digital/mic input or buzzer detection — so on
    // the web it is rate-limited (see [_runLoop]) to keep frames short enough
    // for the AVR to stay real-time. Mic/clap input is injected directly into
    // the ADC every frame in [_updateMicSensors], independent of this solve.
    final spiceStartUs = sw.elapsedMicroseconds;
    if (_isSpiceActive && solveSpice) _spiceEngine.solve();
    final spiceDoneUs = sw.elapsedMicroseconds;

    // 7. Feed solved analog-pin voltages back into the ADC (analogRead) and
    //    update LED visuals from SPICE results.
    if (_isSpiceActive && solveSpice) {
      _updateAnalogInputs();
      _emitWireCurrents();
      _checkSupplyRails();
    }

    // Declarative parts run every frame, solved circuit or not: their rules
    // may depend only on properties (a user-set light level) and should still
    // show the right thing on a canvas with no Arduino on it.
    if (_behaviourNodes.isNotEmpty) _updateBehaviourParts();

    // 8. Flush all visual changes in a single canvas state update
    _flushFrameUpdates();
    final totalUs = sw.elapsedMicroseconds;
    sw.stop();

    profiler?.record(
      FrameSample(
        inputsUs: inputsDoneUs,
        avrUs: avrDoneUs - inputsDoneUs,
        spiceUs: spiceDoneUs - spiceStartUs,
        ledsUs: totalUs - spiceDoneUs,
        totalUs: totalUs,
      ),
    );

    // Emit rolling frame-stats to telemetry every ~60 frames (~1 Hz at 60fps).
    if (++_frameCount % 60 == 0) {
      final s = profiler?.stats;
      if (s != null && s.sampleCount > 0) {
        onFrameStats?.call(s);
      }
    }

    return totalUs;
  }

  /// Sets up a run exactly like [start] — builds the netlist + SPICE model and
  /// loads the compiled program — but does NOT launch the real-time loop, so a
  /// test can drive frames itself with [runFrame]. Audio/mic services are
  /// intentionally skipped (they need platform plugins unavailable in tests).
  @visibleForTesting
  void prepareForFrameStepping(String compiledHex) {
    _isSimulating = true;
    _isPaused = false;
    _lastTopologyState = {};
    _lastBuiltinLedState = false;
    _runElapsedUs = 0;
    _indexNodes();
    _pickBoard();
    _buildCircuit();
    _connectToneDetector();

    _board.loadHex(compiledHex, onSerialPrint: onSerialPrint);
  }

  /// Routes the board's tone detector to the parts and to the owner. Shared by
  /// [start] and [prepareForFrameStepping]: without it a stepped run detects
  /// every tone and tells no one, so a buzzer never sounds in a test.
  void _connectToneDetector() {
    _board.onBuzzerFrequencyChanged = (freq) {
      // Audio playback is the owner's responsibility (UI isolate) and is
      // driven straight from the detector so a tone starts the moment it is
      // heard. The on-canvas state is a part's own business: whichever part
      // asked for detection reads this on its next frame.
      onBuzzerFrequency?.call(freq);
      _measurements.lastFrequency = freq;
    };
  }
}
