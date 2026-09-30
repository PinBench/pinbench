import 'package:flutter/foundation.dart';

import 'package:ngspice_dart/ngspice_dart.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_pdl/pinbench_pdl.dart';
import 'package:pinbench_parts/models/port_model.dart';

import 'sim_log.dart';
import '../config/avr_config.dart';
import 'circuit_netlist.dart';

/// Builds and solves the analog (SPICE) model of the circuit each frame.
///
/// From the netlist + placed nodes it generates an ngspice netlist (resistors,
/// LED diodes with current-sense sources, per-pin GPIO drivers), then on each
/// [solve] alters only the changed pin voltages and runs an operating-point
/// analysis. Callers read results via [getLedCurrent] / [getPortVoltage].
///
/// ngspice is a process-global singleton, so a fresh [SpiceEngine] per run
/// re-loads the circuit rather than re-initializing the library.
class SpiceEngine({
  /// Sink for user-facing SPICE diagnostics (the netlist and errors that
  /// matter), surfaced in the SPICE Logs pane. Per-frame noise is kept out.
  final void Function(String)? onLog,
}) {
  this {
    if (!_ngspiceInitialized) {
      _ngspice.init();
      _ngspiceInitialized = true;
    }
  }

  static const _log = SimLog('app.simulation.spice');
  static final _sanitize = RegExp('[^a-zA-Z0-9]');
  final _ngspice = Ngspice();
  final Map<PortLocation, int> _portToNode = {};

  final Map<String, double> _pinVoltages = {};
  final Set<String> _dirtyPins = {};
  final List<String> _ledKeys = [];

  /// Every element's two terminals and how to read the current between them —
  /// the raw material for [portInjections]. Rebuilt by [build].
  final List<_ElementBranch> _branches = [];

  /// Reused by [portInjections]/[_nodeVoltage] so a 60 Hz frame loop allocates
  /// nothing to report currents.
  final Map<PortLocation, double> _injections = {};
  final Map<int, double> _nodeVoltageCache = {};

  /// SPICE element name for each PDL-defined node that has one, so a
  /// `physics.*` behaviour rule can address the element it built.
  final Map<Key, String> _pdlElements = {};

  /// Last value pushed for each of those elements, and which ones still need
  /// an `alter`. Same shape as the pin-voltage path above, for the same
  /// reason: altering an unchanged value costs a native call per frame.
  final Map<String, double> _elementValues = {};
  final Set<String> _dirtyElements = {};

  // Precomputed `i(V_led_<key>)` vector names keyed by node.key.toString(), so
  // getLedCurrent does not rebuild the string / recompile a RegExp per call.
  final Map<String, String> _ledVecName = {};

  /// Whether the last [build] produced any element belonging to a *part*, as
  /// opposed to the Uno's own pin sources.
  ///
  /// This is what decides whether the per-frame analog solve is worth running.
  /// It used to be "are there any LEDs on the canvas", which stopped being
  /// answerable once parts started declaring their own behaviour — and would
  /// have silently disabled SPICE for every blink circuit.
  var _hasPartElements = false;

  bool get hasPartElements => _hasPartElements;

  /// Node keys whose element has a current-measuring source in the netlist.
  /// The only elements `elementCurrent` can answer for.
  Iterable<String> get measuredElementKeys => _ledKeys;

  // Set when a source voltage changes (or after a rebuild) so solve() can skip
  // the ngspice `op` when nothing changed — the previous op's vectors stay valid.
  var _needsSolve = false;

  // ngspice is a global singleton native library. ngSpice_Init must be called
  // exactly once for the lifetime of the process — calling it again on a
  // subsequent simulation run corrupts the simulator so `op` yields no output
  // vectors. These statics track global ngspice state across SpiceEngine
  // instances (a new instance is created for every simulation run).
  static final _elementLine = RegExp('^[VRDCIQM]_');
  static final _unoElementLine = RegExp(r'^[VR]_uno_|^V_gnd\b');

  /// The `.model` a transistor is built with when its part says nothing: the
  /// DC parameters of a 2N3904 and 2N3906, and level-1 MOSFETs near a 2N7000
  /// and its P-channel counterpart. Only DC matters to an operating point.
  static const _modelDefaults = {
    SpiceComponentType.npn: {
      'is': 6.734e-15,
      'bf': 416.4,
      'br': 0.7371,
      'vaf': 74.03,
      'ikf': 0.06678,
      'ne': 1.259,
      'ise': 6.734e-15,
      'rb': 10,
      'rc': 1,
    },
    SpiceComponentType.pnp: {
      'is': 1.41e-15,
      'bf': 180.7,
      'br': 4.977,
      'vaf': 18.7,
      'ikf': 0.08,
      'ne': 1.5,
      'ise': 0,
      'rb': 10,
      'rc': 2.5,
    },
    // A TIP120's pair: each transistor's beta multiplies, and its 8 kΩ and
    // 120 Ω base-emitter resistors are `r1` and `r2`.
    SpiceComponentType.npnDarlington: {'is': 1e-13, 'bf': 50, 'br': 1, 'r1': 8000, 'r2': 120},
    SpiceComponentType.pnpDarlington: {'is': 1e-13, 'bf': 50, 'br': 1, 'r1': 8000, 'r2': 120},
    SpiceComponentType.nmos: {'level': 1, 'vto': 2.1, 'kp': 0.2, 'lambda': 0.01},
    SpiceComponentType.pmos: {'level': 1, 'vto': -2.1, 'kp': 0.1, 'lambda': 0.01},
  };

  /// A transistor's parameters: the defaults for its type, overridden by any
  /// numeric `PHYSICS` parameter its part declares (`bf = 300`).
  static Map<String, num> _modelValues(SpiceModelDef spiceDef) => {
    ...?_modelDefaults[spiceDef.type],
    ...spiceDef.parameters,
  };

  static String _modelCard(Map<String, num> values) =>
      values.entries.map((e) => '${e.key.toUpperCase()}=${e.value}').join(' ');

  static String _modelParameters(SpiceModelDef spiceDef) => _modelCard(_modelValues(spiceDef));

  static var _ngspiceInitialized = false;
  static var _circuitLoaded = false;

  void build(CircuitNetlist netlist, List<ComponentInstance> nodes) {
    _pinVoltages.clear();
    _dirtyPins.clear();
    _pdlElements.clear();
    _elementValues.clear();
    _dirtyElements.clear();
    _ledKeys.clear();
    _ledVecName.clear();
    _portToNode.clear();
    _branches.clear();

    var nextNodeId = 1;
    final visitedPorts = <PortLocation>{};

    // Find Ground ports
    final groundPorts = <PortLocation>{};
    for (final loc in netlist.adj.keys) {
      if (loc.portId.startsWith('GND') || loc.portId.contains('minus')) {
        groundPorts.addAll(netlist.findConnectedPorts(loc));
      }
    }

    for (final loc in groundPorts) {
      _portToNode[loc] = 0;
      visitedPorts.add(loc);
    }

    for (final loc in netlist.adj.keys) {
      if (!visitedPorts.contains(loc)) {
        final netPorts = netlist.findConnectedPorts(loc);
        for (final p in netPorts) {
          _portToNode[p] = nextNodeId;
          visitedPorts.add(p);
        }
        nextNodeId++;
      }
    }

    final circArray = <String>['* PinBench Simulation'];

    ComponentInstance? arduinoNode;

    for (final node in nodes) {
      final keyStr = node.key.toString().replaceAll(_sanitize, '_');

      // The board is the one node a simulator must single out — it hosts the
      // sketch and supplies every pin voltage, so it is not an element like
      // the parts around it. A declared flag rather than a name comparison, so
      // a second board would not mean editing this file.
      if (PartRegistry.isBoard(node.part)) {
        arduinoNode = node;
        continue;
      }

      // One path for every part, data-driven or built-in. This used to be two:
      // a PDL branch, and a fallback that recognised `led`, `resistor` and
      // `potentiometer` by display name — which is how a resistor ended up
      // hardcoded at 220 Ω no matter what the properties panel said.
      final spiceDef = PartRegistry.spiceFor(node.part);
      if (spiceDef == null) continue;

      int nodeFor(String role) => _getNode(node.key, spiceDef.pinMapping[role] ?? role);
      PortLocation portFor(String role) =>
          PortLocation(nodeKey: node.key, portId: spiceDef.pinMapping[role] ?? role);

      // A `.pdl` part's `physics.*` rule beats its static value, so the element
      // starts where the part's own behaviour says rather than being corrected
      // one frame later — a flicker with no obvious cause.
      final definitionId = node.part.definitionId;
      final definition = definitionId == null ? null : PartRegistry.getPart(definitionId);
      final physics = definition == null
          ? const <String, double>{}
          : PdlBehaviorEvaluator.physicsFor(definition, node.properties);

      switch (spiceDef.type) {
        case SpiceComponentType.resistor:
          final ohms =
              physics['resistance'] ?? spiceDef.valueFor(node.properties, 'resistance') ?? 220.0;
          _pdlElements[node.key] = 'R_$keyStr';
          circArray.add('R_$keyStr n_${nodeFor('n1')} n_${nodeFor('n2')} $ohms');
          _branches.add(
            _ElementBranch.ohmic(
              a: portFor('n1'),
              b: portFor('n2'),
              nodeA: nodeFor('n1'),
              nodeB: nodeFor('n2'),
              element: 'R_$keyStr',
              ohms: ohms,
            ),
          );

        case SpiceComponentType.diode:
          // A 0 V source in series is what makes the current measurable, which
          // is how an LED knows it is lit.
          // A part may give its own model numbers (`is`, `n`) — a 1N4148 and a
          // 1N5819 differ by half a volt. Without them, the LED's.
          circArray.add(
            '.model D_$keyStr D(${_modelCard({'is': 1e-14, 'n': 1.5, ...spiceDef.parameters})})',
          );
          circArray.add('D_$keyStr n_${nodeFor('n1')} n_int_$keyStr D_$keyStr');
          circArray.add('V_led_$keyStr n_int_$keyStr n_${nodeFor('n2')} 0');
          _ledKeys.add(node.key.toString());
          _ledVecName[node.key.toString()] = 'i(V_led_$keyStr)';
          // The sense source's branch current is defined n_int → n2, which is
          // exactly the diode's forward current: anode → cathode.
          _branches.add(
            _ElementBranch.measured(a: portFor('n1'), b: portFor('n2'), vector: 'i(V_led_$keyStr)'),
          );

        case SpiceComponentType.voltageSource:
          final volts = physics['voltage'] ?? spiceDef.valueFor(node.properties, 'voltage') ?? 5.0;
          _pdlElements[node.key] = 'V_$keyStr';
          circArray.add('V_$keyStr n_${nodeFor('n1')} n_${nodeFor('n2')} $volts');
          _branches.add(
            _ElementBranch.measured(a: portFor('n1'), b: portFor('n2'), vector: 'i(V_$keyStr)'),
          );

        case SpiceComponentType.capacitor:
          final farads =
              physics['capacitance'] ?? spiceDef.valueFor(node.properties, 'capacitance') ?? 1e-6;
          _pdlElements[node.key] = 'C_$keyStr';
          circArray.add('C_$keyStr n_${nodeFor('n1')} n_${nodeFor('n2')} $farads');

        case SpiceComponentType.potentiometer:
          // Two resistors split a fixed track around the wiper. With term1 at
          // the supply and term2 at ground, the wiper sits at
          // position x Vsupply.
          final total = spiceDef.parameters['total'] ?? 10000.0;
          final position = (spiceDef.valueFor(node.properties, 'position') ?? 0.5).clamp(0.0, 1.0);
          final top = ((1 - position) * total).clamp(1.0, total);
          final bottom = (position * total).clamp(1.0, total);
          circArray.add('R_${keyStr}_a n_${nodeFor('term1')} n_${nodeFor('wiper')} $top');
          circArray.add('R_${keyStr}_b n_${nodeFor('wiper')} n_${nodeFor('term2')} $bottom');
          _branches
            ..add(
              _ElementBranch.ohmic(
                a: portFor('term1'),
                b: portFor('wiper'),
                nodeA: nodeFor('term1'),
                nodeB: nodeFor('wiper'),
                element: 'R_${keyStr}_a',
                ohms: top,
              ),
            )
            ..add(
              _ElementBranch.ohmic(
                a: portFor('wiper'),
                b: portFor('term2'),
                nodeA: nodeFor('wiper'),
                nodeB: nodeFor('term2'),
                element: 'R_${keyStr}_b',
                ohms: bottom,
              ),
            );

        case SpiceComponentType.npn:
        case SpiceComponentType.pnp:
          // 0 V sources in series with the collector and base, as the LED has,
          // make the terminal currents measurable; the emitter's is the rest.
          final model = 'QM_$keyStr';
          final polarity = spiceDef.type == SpiceComponentType.npn ? 'NPN' : 'PNP';
          circArray.add('.model $model $polarity(${_modelParameters(spiceDef)})');
          circArray.add('V_qc_$keyStr n_${nodeFor('c')} n_qc_$keyStr 0');
          circArray.add('V_qb_$keyStr n_${nodeFor('b')} n_qb_$keyStr 0');
          circArray.add('Q_$keyStr n_qc_$keyStr n_qb_$keyStr n_${nodeFor('e')} $model');
          _branches
            ..add(
              _ElementBranch.measured(a: portFor('c'), b: portFor('e'), vector: 'i(V_qc_$keyStr)'),
            )
            ..add(
              _ElementBranch.measured(a: portFor('b'), b: portFor('e'), vector: 'i(V_qb_$keyStr)'),
            );

        case SpiceComponentType.npnDarlington:
        case SpiceComponentType.pnpDarlington:
          // Two transistors sharing a collector, the first driving the
          // second's base, with the TIP120's resistor across each base-emitter
          // junction. Sensed like a single transistor.
          final model = 'QM_$keyStr';
          final polarity = spiceDef.type == SpiceComponentType.npnDarlington ? 'NPN' : 'PNP';
          final values = _modelValues(spiceDef);
          final r1 = values.remove('r1');
          final r2 = values.remove('r2');
          final mid = 'n_qm_$keyStr';
          circArray.add('.model $model $polarity(${_modelCard(values)})');
          circArray.add('V_qc_$keyStr n_${nodeFor('c')} n_qc_$keyStr 0');
          circArray.add('V_qb_$keyStr n_${nodeFor('b')} n_qb_$keyStr 0');
          circArray.add('Q_${keyStr}_1 n_qc_$keyStr n_qb_$keyStr $mid $model');
          circArray.add('Q_${keyStr}_2 n_qc_$keyStr $mid n_${nodeFor('e')} $model');
          circArray.add('R_${keyStr}_1 n_qb_$keyStr $mid $r1');
          circArray.add('R_${keyStr}_2 $mid n_${nodeFor('e')} $r2');
          _branches
            ..add(
              _ElementBranch.measured(a: portFor('c'), b: portFor('e'), vector: 'i(V_qc_$keyStr)'),
            )
            ..add(
              _ElementBranch.measured(a: portFor('b'), b: portFor('e'), vector: 'i(V_qb_$keyStr)'),
            );

        case SpiceComponentType.rgbLed:
          // Three dies on one cathode, each with the LED's 0 V sense source.
          // Red drops about 2 V at 20 mA, green and blue about 3 V.
          circArray.add('.model DR_$keyStr D(Is=1e-18 N=2)');
          circArray.add('.model DGB_$keyStr D(Is=1e-22 N=2.5)');
          for (final (role, model) in [('r', 'DR'), ('g', 'DGB'), ('b', 'DGB')]) {
            final die = '${role}_$keyStr';
            circArray.add('D_$die n_${nodeFor(role)} n_int_$die ${model}_$keyStr');
            circArray.add('V_led_$die n_int_$die n_${nodeFor('k')} 0');
            _branches.add(
              _ElementBranch.measured(a: portFor(role), b: portFor('k'), vector: 'i(V_led_$die)'),
            );
          }

        case SpiceComponentType.nmos:
        case SpiceComponentType.pmos:
          final model = 'MM_$keyStr';
          final channel = spiceDef.type == SpiceComponentType.nmos ? 'NMOS' : 'PMOS';
          circArray.add('.model $model $channel(${_modelParameters(spiceDef)})');
          circArray.add('V_md_$keyStr n_${nodeFor('d')} n_md_$keyStr 0');
          // Body tied to source, as in a discrete MOSFET.
          circArray.add(
            'M_$keyStr n_md_$keyStr n_${nodeFor('g')} n_${nodeFor('s')} n_${nodeFor('s')} $model',
          );
          // A gate has no DC path, so one left unwired is a floating node the
          // solver cannot place. 1 GΩ to the source holds it off instead,
          // drawing nothing a real gate would not.
          circArray.add('R_mg_$keyStr n_${nodeFor('g')} n_${nodeFor('s')} 1e9');
          _branches.add(
            _ElementBranch.measured(a: portFor('d'), b: portFor('s'), vector: 'i(V_md_$keyStr)'),
          );

        case SpiceComponentType.currentSource:
        case SpiceComponentType.none:
          break;
      }
    }

    if (arduinoNode != null) {
      for (final pin in AVRConfig.spicePins) {
        final n1 = _getNode(arduinoNode.key, pin);
        const n2 = 0; // Ground
        // A 40 ohm internal resistance (typical for an ATmega328P GPIO) keeps
        // a directly-connected LED from producing infinite current and a
        // convergence failure.
        circArray.add('V_uno_$pin n_int_src_$pin n_$n2 0.0');
        circArray.add('R_uno_$pin n_$n1 n_int_src_$pin 40.0');
        _pinVoltages[pin] = 0.0;
        _dirtyPins.add(pin);
        // The pin's driver is a two-terminal element between ground and the
        // pin: source, then the 40 Ω output resistance. Its branch current is
        // defined n_int_src → ground, so a pin *sourcing* current reads
        // negative — hence the flipped terminals here, which make a positive
        // reading mean "current leaves the pin into the circuit".
        _branches.add(
          _ElementBranch.measured(
            a: null,
            b: PortLocation(nodeKey: arduinoNode.key, portId: pin),
            vector: 'i(V_uno_$pin)',
            scale: -1,
          ),
        );
      }
    }

    // Connect node 0 to spice ground (0)
    circArray.add('V_gnd n_0 0 0');

    circArray.add('.op');
    circArray.add('.end');

    _log.trace('GENERATED SPICE NETLIST:\n${circArray.join('\n')}');

    // Surface the netlist at the top of the SPICE Logs pane. The pane is cleared
    // at the start of each run, so this stays the authoritative current netlist.
    final log = onLog;

    // Uno pin sources are `V_uno_<pin>` / `R_uno_<pin>`, plus a `V_gnd`; any
    // other element line belongs to a placed part. Read off the assembled
    // netlist rather than counted in the branches above, so a new element type
    // cannot forget to register itself.
    _hasPartElements = circArray.any(
      (line) => _elementLine.hasMatch(line) && !_unoElementLine.hasMatch(line),
    );

    if (log != null) {
      log('──────── SPICE NETLIST ────────');
      circArray.forEach(log);
      log('───────────────────────────────');
    }

    // Remove the previous run's circuit so circuits don't accumulate in the
    // global ngspice instance and the newly loaded one is unambiguously current.
    if (_circuitLoaded) {
      _ngspice.command('remcirc');
    }
    // Clear old plots/vectors from the previous run.
    _ngspice.command('destroy all');
    _ngspice.circuit(circArray);
    _circuitLoaded = true;
    _needsSolve = true; // force the first solve after a (re)build
  }

  int _getNode(Key nodeKey, String portId) =>
      _portToNode[PortLocation(nodeKey: nodeKey, portId: portId)] ?? 0;

  /// Whether [portId] on [nodeKey] is wired into the solved circuit (i.e. maps
  /// to a real, non-ground node). Used to decide if an analog pin is driven.
  bool isPortConnected(Key nodeKey, String portId) =>
      _portToNode.containsKey(PortLocation(nodeKey: nodeKey, portId: portId));

  /// Returns the solved DC voltage at [portId] of [nodeKey] (0 V if it is
  /// ground or not part of the circuit). Valid after [solve].
  double getPortVoltage(Key nodeKey, String portId) {
    final nodeId = _getNode(nodeKey, portId);
    if (nodeId == 0) return 0.0;
    final vec = _ngspice.getVector('n_$nodeId');
    if (vec == null || vec.isEmpty) return 0.0;
    return vec.first;
  }

  /// The SPICE element a PDL-defined [nodeKey] contributed, if any.
  ///
  /// Only elements whose value can be changed at runtime are registered — a
  /// `physics.resistance` rule needs to name `R_<key>` in an `alter`.
  String? pdlElementFor(Key nodeKey) => _pdlElements[nodeKey];

  /// Queues `alter <element> = <value>` for the next [solve].
  ///
  /// Returns true if the value actually changed. ngspice's `alter` is the same
  /// mechanism the Arduino's pin sources use, so a declarative part that
  /// varies its resistance costs no more than a pin toggle does — and
  /// crucially avoids rebuilding the circuit, which would reset every node
  /// voltage mid-run.
  bool setElementValue(String elementName, double value) {
    if (_elementValues[elementName] == value) return false;
    _elementValues[elementName] = value;
    _dirtyElements.add(elementName);
    _needsSolve = true;
    return true;
  }

  /// Returns true if the voltage changed.
  bool setPinVoltage(String pin, double voltage) {
    if (_pinVoltages[pin] == voltage) return false;
    _pinVoltages[pin] = voltage;
    _dirtyPins.add(pin);
    _needsSolve = true;
    return true;
  }

  double getPinVoltage(String pin) => _pinVoltages[pin] ?? 0.0;

  void solve() {
    // Only alter pins whose voltage actually changed — but always run op so
    // that getVector returns fresh data every frame regardless of whether
    // any voltage changed.
    for (final pin in _dirtyPins) {
      final voltage = _pinVoltages[pin];
      if (voltage == null) continue;
      final cmd = 'alter V_uno_$pin = $voltage';
      final res = _ngspice.command(cmd);
      if (res != 0) {
        _log.error('SpiceEngine Command failed: $cmd (code $res)');
        onLog?.call('[error] command failed: $cmd (code $res)');
      }
    }
    _dirtyPins.clear();

    for (final element in _dirtyElements) {
      final value = _elementValues[element];
      if (value == null) continue;
      final cmd = 'alter $element = $value';
      final res = _ngspice.command(cmd);
      if (res != 0) {
        _log.error('SpiceEngine Command failed: $cmd (code $res)');
        onLog?.call('[error] command failed: $cmd (code $res)');
      }
    }
    _dirtyElements.clear();

    // Skip the op solve when nothing changed since the last solve — the
    // previous op's result vectors remain valid, so getLedCurrent() still
    // returns correct values without paying for a redundant re-solve.
    if (!_needsSolve) return;
    _needsSolve = false;

    // _ngspice.command('destroy all'); // DO NOT USE! Destroys the 'const' plot and breaks NGSPICE after a few cycles.
    final opRes = _ngspice.command('op');
    if (opRes != 0) {
      _log.error('SpiceEngine OP failed: code $opRes');
      onLog?.call('[error] operating-point solve failed (code $opRes)');
    }
  }

  /// The current every element pushes *into* the connectivity graph, per port,
  /// in amps. Positive means current flows out of the element and into the net
  /// at that port.
  ///
  /// This is what turns a solved operating point into something a wire can be
  /// drawn from: SPICE has no wires (see `WireCurrentSolver`), but it does know
  /// what every element's terminals are doing, and KCL does the rest.
  ///
  /// Ports belonging to the ground net are deliberately *not* balanced here —
  /// the return path through node 0 has no element to attribute it to. The flow
  /// solver absorbs the remainder at the net's ground pin instead.
  ///
  /// Valid after [solve]. The returned map is reused between calls.
  Map<PortLocation, double> portInjections() {
    _injections.clear();
    if (_branches.isEmpty) return _injections;
    _nodeVoltageCache.clear();

    for (final branch in _branches) {
      final current = _branchCurrent(branch);
      if (current == 0 || !current.isFinite) continue;

      final a = branch.a;
      final b = branch.b;
      if (a != null) _injections.update(a, (v) => v - current, ifAbsent: () => -current);
      if (b != null) _injections.update(b, (v) => v + current, ifAbsent: () => current);
    }
    return _injections;
  }

  /// Current flowing into [nodeKey]'s component at [portId]: the sum over the
  /// elements that terminal feeds, each read the way [portInjections] reads
  /// it. What a multi-element part's logic uses to tell its elements apart.
  double portCurrent(Key nodeKey, String portId) {
    _nodeVoltageCache.clear();
    var total = 0.0;
    for (final branch in _branches) {
      final into = branch.a?.nodeKey == nodeKey && branch.a?.portId == portId;
      final outOf = branch.b?.nodeKey == nodeKey && branch.b?.portId == portId;
      if (!into && !outOf) continue;
      final current = _branchCurrent(branch);
      if (!current.isFinite) continue;
      total += into ? current : -current;
    }
    return total;
  }

  /// The current through [branch], from its `a` terminal to its `b`.
  double _branchCurrent(_ElementBranch branch) => branch.isMeasured
      ? branch.scale * _vectorValue(branch.vector!)
      : (_nodeVoltage(branch.nodeA) - _nodeVoltage(branch.nodeB)) /
            (_elementValues[branch.element] ?? branch.ohms!);

  double _nodeVoltage(int nodeId) {
    if (nodeId == 0) return 0;
    final cached = _nodeVoltageCache[nodeId];
    if (cached != null) return cached;
    return _nodeVoltageCache[nodeId] = _vectorValue('n_$nodeId');
  }

  double _vectorValue(String name) {
    final vec = _ngspice.getVector(name);
    if (vec == null || vec.isEmpty) return 0;
    return vec.first;
  }

  double getLedCurrent(String key) {
    final vecName = _ledVecName[key] ??= 'i(V_led_${key.replaceAll(_sanitize, '_')})';
    final vec = _ngspice.getVector(vecName);
    if (vec == null) {
      _log.error('SpiceEngine getVector returned NULL for $vecName');
      return 0.0;
    }
    if (vec.isEmpty) {
      _log.error('SpiceEngine getVector returned EMPTY for $vecName');
      return 0.0;
    }
    return vec.first;
  }
}

/// One element's terminals plus how to read the current between them.
///
/// The convention is uniform across every element type: the value is the
/// current flowing [a] → [b] *through* the element. A null terminal is ground,
/// which is not a port and so is never injected into the graph.
class _ElementBranch {
  const new ohmic({
    required this.a,
    required this.b,
    required this.nodeA,
    required this.nodeB,
    required this.element,
    required this.ohms,
  }) : vector = null,
       scale = 1,
       isMeasured = false;

  const new measured({
    required this.a,
    required this.b,
    required String this.vector,
    this.scale = 1,
  }) : nodeA = 0,
       nodeB = 0,
       element = null,
       ohms = null,
       isMeasured = true;

  final PortLocation? a;
  final PortLocation? b;

  /// Set for elements with a real branch current in the result — anything built
  /// on a voltage source. Otherwise the current comes from Ohm's law.
  final bool isMeasured;
  final String? vector;

  /// Applied to [vector] so every branch reads as "current from [a] to [b]",
  /// whatever terminal order the netlist happened to use.
  final double scale;

  // Ohm's-law branches only: the solved nodes to difference, the element name
  // (so a `physics.*` rule that altered its value is honoured), and the value
  // it was built with.
  final int nodeA;
  final int nodeB;
  final String? element;
  final double? ohms;
}
