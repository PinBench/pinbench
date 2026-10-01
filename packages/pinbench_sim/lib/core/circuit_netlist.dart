import 'dart:collection';

import 'package:flutter/widgets.dart';

import 'package:collection/collection.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/painting/port_provider.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

/// The circuit's electrical connectivity graph, built from wires, physical
/// overlaps (breadboard holes) and component internals.
///
/// [buildStatic] computes the fixed topology once; [updateDynamic] re-applies
/// only switch-dependent edges (a pressed button) cheaply each frame.
/// [findConnectedPorts] returns the electrical net a port belongs to via cached
/// connected-component labels (O(1) per query).
class CircuitNetlist {
  final Map<PortLocation, Set<PortLocation>> staticAdj = {};
  final Map<PortLocation, Set<PortLocation>> adj = {};

  // Connected-component labels derived from [adj], rebuilt on every adjacency
  // change (buildStatic/updateDynamic) so [findConnectedPorts] is an O(1)
  // lookup instead of a fresh BFS per call (it runs ~once per pin per frame).
  final Map<PortLocation, int> _componentOf = {};
  final Map<int, Set<PortLocation>> _componentPorts = {};

  // True when [adj] has changed since the component labels were last computed.
  // Starts true so a netlist whose [adj] is populated directly (without going
  // through buildStatic) still rebuilds lazily on the first query.
  var _componentsDirty = true;

  void _addEdge(PortLocation a, PortLocation b) {
    adj.putIfAbsent(a, () => {}).add(b);
    adj.putIfAbsent(b, () => {}).add(a);
  }

  /// Builds the static adjacency graph from [nodes] and [wires].
  ///
  /// [bridgeResistors] controls whether a resistor's two terminals are merged
  /// into one electrical net. For *digital connectivity* (pull-ups, signal
  /// routing) a resistor passes the signal through, so they should be bridged
  /// (the default). For the *SPICE* model they must stay separate nodes so the
  /// resistor is a real 2-terminal element that limits current and can form
  /// voltage dividers — pass `false` there.
  void buildStatic(
    List<ComponentInstance> nodes,
    List<WireModel> wires, {
    bool bridgeResistors = true,
  }) {
    adj.clear();

    // 1. Add explicitly drawn wires
    for (final wire in wires) {
      _addEdge(wire.start, wire.end);
    }

    // 2. Add physical overlaps (components plugged into breadboards or each other)
    for (var i = 0; i < nodes.length; i++) {
      final nodeA = nodes[i];

      // Large boards do not physically plug into other boards underneath them.
      // (They must be connected via wires). Not every board: a Pico is made
      // to straddle a breadboard's channel, and its pins land in the holes
      // under them like any other part's legs.
      if (nodeA.part.name == PartNames.arduinoUno || nodeA.part.name.contains('Breadboard')) {
        continue;
      }

      final painterA = nodeA.part.getPainter();
      if (painterA is! PortProvider) continue;

      final portsA = (painterA! as PortProvider).getPorts();

      for (final portA in portsA) {
        final portOffsetA = nodeA.getPortOffset(portA.id);
        if (portOffsetA == null) continue;

        final absolutePosA = nodeA.position + portOffsetA;
        final locA = PortLocation(nodeKey: nodeA.key, portId: portA.id);

        for (var j = 0; j < nodes.length; j++) {
          if (i == j) continue;
          final nodeB = nodes[j];
          final painterB = nodeB.part.getPainter();
          if (painterB is! PortProvider) continue;

          // Inverse-transform the absolute position into nodeB's local coordinate space
          final localPosB = nodeB.absoluteToLocal(absolutePosA);

          // Use getPortAt for dynamic ports (like Breadboards)
          var portB = (painterB! as PortProvider).getPortAt(localPosB);

          // If getPortAt didn't return anything, check static ports
          if (portB == null) {
            final staticPortsB = (painterB as PortProvider).getPorts();
            for (final pb in staticPortsB) {
              // Allow a tiny margin of error for floating point inaccuracies
              if ((pb.localOffset - localPosB).distance < 0.1) {
                portB = pb;
                break;
              }
            }
          }

          if (portB != null) {
            final locB = PortLocation(nodeKey: nodeB.key, portId: portB.id);
            _addEdge(locA, locB);
          }
        }
      }
    }

    // 3. Resolve internal Breadboard connections
    final breadboardPorts = <Key, List<PortLocation>>{};
    for (final loc in adj.keys) {
      final node = nodes.firstWhereOrNull((n) => n.key == loc.nodeKey);
      if (node == null) continue;
      if (node.part.name.contains('Breadboard')) {
        breadboardPorts.putIfAbsent(node.key, () => []).add(loc);
      }
    }

    for (final entry in breadboardPorts.entries) {
      final locations = entry.value;

      // Group by internal net ID
      final nets = <String, List<PortLocation>>{};
      for (final loc in locations) {
        final netId = _getBreadboardNetId(loc.portId);
        nets.putIfAbsent(netId, () => []).add(loc);
      }

      // Connect all ports in the same net
      for (final netPorts in nets.values) {
        for (var i = 0; i < netPorts.length; i++) {
          for (var j = i + 1; j < netPorts.length; j++) {
            _addEdge(netPorts[i], netPorts[j]);
          }
        }
      }
    }

    // 4. Resolve pass-through components like Resistors and Switches
    for (final node in nodes) {
      if (node.part.name == PartNames.resistor) {
        if (bridgeResistors) {
          final locLeft = PortLocation(nodeKey: node.key, portId: 'left');
          final locRight = PortLocation(nodeKey: node.key, portId: 'right');
          _addEdge(locLeft, locRight);
        }
      } else if (node.part.name == PartNames.pushButton) {
        final leg1 = PortLocation(nodeKey: node.key, portId: 'leg1');
        final leg2 = PortLocation(nodeKey: node.key, portId: 'leg2');
        final leg3 = PortLocation(nodeKey: node.key, portId: 'leg3');
        final leg4 = PortLocation(nodeKey: node.key, portId: 'leg4');

        // Vertical legs are permanently connected internally
        _addEdge(leg1, leg3);
        _addEdge(leg2, leg4);
      }
    }

    staticAdj.clear();
    for (final entry in adj.entries) {
      staticAdj[entry.key] = Set.from(entry.value);
    }

    _componentsDirty = true;
  }

  void updateDynamic(List<ComponentInstance> nodes) {
    adj.clear();
    for (final entry in staticAdj.entries) {
      adj[entry.key] = Set.from(entry.value);
    }

    for (final node in nodes) {
      if (node.part.name == PartNames.pushButton) {
        final isPressed =
            node.properties[ComponentProps.isPressed] == true ||
            node.properties[ComponentProps.isPressed] == 'true';
        if (isPressed) {
          final leg1 = PortLocation(nodeKey: node.key, portId: 'leg1');
          final leg2 = PortLocation(nodeKey: node.key, portId: 'leg2');
          _addEdge(leg1, leg2);
        }
      }
    }

    _componentsDirty = true;
  }

  /// Collapses a breadboard hole id onto the net it belongs to, following the
  /// board's two connection rules:
  ///  * a **power rail** is one net for the full length of the board, so the
  ///    row drops out entirely (`rail_left_plus_7` → `rail_left_plus`);
  ///  * a **terminal strip** is one net per numbered row per side, so the
  ///    column letter drops out but the side does not — the centre notch is
  ///    what keeps `a–e` and `f–j` of the same row apart (`sig_left_a_5` →
  ///    `sig_left_5`).
  String _getBreadboardNetId(String portId) {
    if (portId.startsWith('rail_')) {
      final parts = portId.split('_'); // e.g. [rail, left, plus, 0]
      if (parts.length >= 3) {
        return '${parts[0]}_${parts[1]}_${parts[2]}'; // rail_left_plus
      }
    } else if (portId.startsWith('sig_')) {
      final parts = portId.split('_'); // e.g. [sig, left, a, 5]
      if (parts.length >= 4) {
        return '${parts[0]}_${parts[1]}_${parts[3]}'; // sig_left_5
      }
    }
    return portId;
  }

  /// Recomputes connected-component labels from [adj]. One BFS per component
  /// (O(V + E) total), using a proper queue. Called whenever the adjacency
  /// changes so that [findConnectedPorts] becomes an O(1) lookup.
  void _rebuildComponents() {
    _componentOf.clear();
    _componentPorts.clear();
    var nextId = 0;
    for (final start in adj.keys) {
      if (_componentOf.containsKey(start)) continue;
      final id = nextId++;
      final members = <PortLocation>{};
      final queue = Queue<PortLocation>()..add(start);
      while (queue.isNotEmpty) {
        final current = queue.removeFirst();
        if (!members.add(current)) continue;
        _componentOf[current] = id;
        final neighbors = adj[current];
        if (neighbors != null) {
          for (final n in neighbors) {
            if (!members.contains(n)) queue.add(n);
          }
        }
      }
      _componentPorts[id] = members;
    }
    _componentsDirty = false;
  }

  /// All ports electrically connected to [start] (including [start] itself).
  ///
  /// O(1) amortized: component labels are (re)built only on the first query
  /// after [adj] changes, then reused. The returned set is shared (not a copy)
  /// and must not be mutated by callers — every current caller only iterates it.
  Set<PortLocation> findConnectedPorts(PortLocation start) {
    if (_componentsDirty) _rebuildComponents();
    return _componentPorts[_componentOf[start]] ?? {start};
  }
}
