import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/models/wire_model.dart';

import 'circuit_netlist.dart';

/// Turns per-element currents into a current for every drawn wire.
///
/// SPICE never sees a wire: `SpiceEngine` collapses each electrical net into a
/// single node, so a wire is an ideal short with no branch of its own and no
/// `i(...)` vector to read. What the solver *does* give us is the current in
/// and out of every element's terminals. That is enough, because a net is a
/// conductor graph and current on it obeys KCL: the current in any edge that
/// bridges the graph equals the total current injected on one side of it.
///
/// So this walks the connectivity graph rather than the matrix. It roots each
/// net at the point where current leaves it (the board's GND pin, when there is
/// one), builds a spanning tree, and sums injections up that tree — the flow in
/// the edge above a vertex is the sum of everything injected beneath it.
///
/// The one place this is an approximation rather than an answer is a net with a
/// *cycle*: two wires drawn in parallel between the same two points. Nothing in
/// the model says how the current divides between two ideal shorts, so the
/// spanning tree carries it all and the redundant wire reads zero. Tree edges
/// are chosen preferring wires, and wires between two different parts are
/// bridges in practice, so this only shows up on deliberately doubled wiring.
class WireCurrentSolver(CircuitNetlist netlist, List<WireModel> wires, {Key? boardKey}) {
  /// Builds the flow graph for one circuit topology. [netlist] must be the
  /// *un-bridged* netlist the SPICE model was built from — a bridged one merges
  /// a resistor's two legs into one vertex, which would hide the resistor from
  /// the graph and short its two nets together.
  ///
  /// [boardKey] is the Arduino's node key, used to root the ground net where
  /// current physically leaves the circuit.
  this {
    _build(netlist, wires, boardKey);
  }

  final Map<PortLocation, int> _index = {};
  final List<PortLocation> _verts = [];

  /// Neighbour lists, with wire-connected neighbours first so a BFS prefers
  /// wire edges when choosing its spanning tree (see the class doc).
  final List<List<int>> _adj = [];

  /// Spanning-forest parent per vertex (-1 at a root), and the BFS discovery
  /// order. Summing in reverse [_order] visits every child before its parent.
  late Int32List _parent;
  late Int32List _order;

  /// Per wire: the endpoint that sits *below* the tree edge the wire forms, and
  /// whether flow toward the parent runs `start → end` (+1) or `end → start`
  /// (-1). A wire that is not a tree edge has child -1 and never gets a value.
  final List<String> _wireIds = [];
  late Int32List _wireChild;
  late Float64List _wireSign;

  /// Reused across solves so a 60 Hz frame loop allocates nothing here.
  late Float64List _subtree;
  final Map<String, double> _result = {};

  /// Number of vertices in the flow graph. Exposed for tests.
  @visibleForTesting
  int get vertexCount => _verts.length;

  int _vertexFor(PortLocation loc) {
    final existing = _index[loc];
    if (existing != null) return existing;
    final id = _verts.length;
    _index[loc] = id;
    _verts.add(loc);
    _adj.add([]);
    return id;
  }

  void _build(CircuitNetlist netlist, List<WireModel> wires, Key? boardKey) {
    // Wire edges first, so they land at the head of each neighbour list.
    final wireEdges = <int, Set<int>>{};
    for (final wire in wires) {
      final a = _vertexFor(wire.start);
      final b = _vertexFor(wire.end);
      if (a == b) continue;
      wireEdges.putIfAbsent(a, () => {}).add(b);
      wireEdges.putIfAbsent(b, () => {}).add(a);
    }

    for (final entry in netlist.adj.entries) {
      final a = _vertexFor(entry.key);
      for (final neighbour in entry.value) {
        final b = _vertexFor(neighbour);
        if (a == b) continue;
        if (wireEdges[a]?.contains(b) ?? false) continue;
        _adj[a].add(b);
      }
    }
    for (final entry in wireEdges.entries) {
      _adj[entry.key].insertAll(0, entry.value);
    }

    _spanningForest(boardKey);
    _indexWires(wires);
    _subtree = Float64List(_verts.length);
  }

  /// One BFS per connected component, rooted where current leaves that net.
  void _spanningForest(Key? boardKey) {
    final n = _verts.length;
    _parent = Int32List(n)..fillRange(0, n, -1);
    _order = Int32List(n);
    final seen = Uint8List(n);
    var written = 0;

    final queue = Queue<int>();
    for (var start = 0; start < n; start++) {
      if (seen[start] != 0) continue;

      // Collect the component first so its root can be chosen deliberately
      // rather than being whichever vertex the outer loop reached first.
      final members = <int>[];
      final found = Uint8List(n);
      queue
        ..clear()
        ..add(start);
      found[start] = 1;
      while (queue.isNotEmpty) {
        final v = queue.removeFirst();
        members.add(v);
        for (final w in _adj[v]) {
          if (found[w] == 0) {
            found[w] = 1;
            queue.add(w);
          }
        }
      }

      final root = _pickRoot(members, boardKey);

      queue
        ..clear()
        ..add(root);
      seen[root] = 1;
      _parent[root] = -1;
      while (queue.isNotEmpty) {
        final v = queue.removeFirst();
        _order[written++] = v;
        for (final w in _adj[v]) {
          if (seen[w] != 0) continue;
          seen[w] = 1;
          _parent[w] = v;
          queue.add(w);
        }
      }
    }
  }

  /// Where a net's current leaves it: the board's own ground pin if this net
  /// reaches one, otherwise any ground pin, otherwise an arbitrary vertex.
  ///
  /// The root is where the tree sum's remainder lands, and every net that
  /// touches ground has a remainder — SPICE ties the whole ground net to node 0
  /// and the return current simply vanishes into it, with no element to account
  /// for it. Rooting at the GND pin puts that return exactly where the wires
  /// actually carry it.
  int _pickRoot(List<int> members, Key? boardKey) {
    var fallback = -1;
    for (final v in members) {
      final loc = _verts[v];
      if (!_isGroundPort(loc.portId)) continue;
      if (boardKey != null && loc.nodeKey == boardKey) return v;
      if (fallback < 0) fallback = v;
    }
    return fallback >= 0 ? fallback : members.first;
  }

  static bool _isGroundPort(String portId) => portId.startsWith('GND') || portId.contains('minus');

  void _indexWires(List<WireModel> wires) {
    _wireChild = Int32List(wires.length)..fillRange(0, wires.length, -1);
    _wireSign = Float64List(wires.length);
    for (var i = 0; i < wires.length; i++) {
      final wire = wires[i];
      _wireIds.add(wire.id);
      final a = _index[wire.start];
      final b = _index[wire.end];
      if (a == null || b == null || a == b) continue;
      if (_parent[a] == b) {
        // `a` (the wire's start) hangs below `b`, so its subtree total is the
        // current running start → end.
        _wireChild[i] = a;
        _wireSign[i] = 1;
      } else if (_parent[b] == a) {
        _wireChild[i] = b;
        _wireSign[i] = -1;
      }
    }
  }

  /// Per-wire current in amps, keyed by wire id and signed so that a positive
  /// value means current runs from the wire's `start` port to its `end` port.
  ///
  /// [injections] is the current flowing *out of every element and into the
  /// graph* at each port (see `SpiceEngine.portInjections`). The returned map is
  /// reused between calls — copy it before handing it across an isolate.
  Map<String, double> solve(Map<PortLocation, double> injections) {
    _result.clear();
    if (_verts.isEmpty) return _result;

    _subtree.fillRange(0, _subtree.length, 0);
    for (final entry in injections.entries) {
      final v = _index[entry.key];
      if (v != null) _subtree[v] += entry.value;
    }

    // Reverse BFS order visits every child before its parent, so each vertex
    // holds its whole subtree's injection by the time it is added upward.
    for (var i = _order.length - 1; i >= 0; i--) {
      final v = _order[i];
      final p = _parent[v];
      if (p >= 0) _subtree[p] += _subtree[v];
    }

    for (var i = 0; i < _wireIds.length; i++) {
      final child = _wireChild[i];
      if (child < 0) continue;
      _result[_wireIds[i]] = _subtree[child] * _wireSign[i];
    }
    return _result;
  }
}
