# pinbench_parts

The circuit-parts domain for PinBench: what a part *is*, how
one is drawn, and the catalog of them.

This is the piece of the codebase that stands alone. It has no view of the app
— no Riverpod, no routing, no logging framework, no theme — which is what lets
the canvas, the simulation engine and the assistant all share it without
depending on each other.

It is also the Flutter side of the two file formats. The formats themselves are
pure-Dart packages of their own — [`pinbench_pdl`](https://github.com/PinBench/pdl)
for a kind of part, [`pinbench_cdl`](https://github.com/PinBench/cdl) for a saved
circuit — so tools outside the app can use them. What turns their plain values
into something drawn and placed lives here.

```
lib/
  models/            part_model, component_instance, wire_model, port_model,
                     breadboard_state
  painting/          PaintNode scene graph, BaseComponentPainter, PortProvider,
                     GridSystem, PhysicalScale
  painters/          the parts themselves — LED, resistor, Arduino Uno,
                     breadboard, servo, piezo, KY-037, potentiometer, …
  part_registry.dart the catalog: standardParts + any .pdl definitions
  pdl_flutter.dart   .pdl values as Flutter types: PdlPoint -> Offset,
                     PdlColor -> Color, a pin -> ComponentPort
  cdl/               placed parts <-> a .cdl document: CircuitParser, the
                     app's property spelling, ids for new parts
  logic/             the part-behaviour contract and the built-in logics
                     (led, servo, buzzer, one_shot)
```

## Parts behave, not just draw

A part names a simulation behaviour — `logic:` on a catalog entry, or a `LOGIC`
line in a `.pdl` — and `logic/` holds both the contract and the built-in
implementations. `PartLogicRegistry` resolves the name; a test asserts every
name the catalog declares actually resolves.

What this package deliberately does *not* contain is the adapters. A logic
reads its pins through `PartPinApi` and its element current through
`PartSpiceApi`; the app implements both against the AVR emulator and ngspice.
That is what lets the behaviour live here without the package depending on a
simulator.

## Adding a part

`.pdl` files under `assets/parts/` describe parts as data — no Dart, no
rebuild. The format is specified in
[`PDL.md`](https://github.com/PinBench/pdl/blob/main/doc/PDL.md), with the
reader in `pinbench_pdl`; this package holds the shipped parts and draws them.

## Part vs component

- A **part** is a catalog entry — one LED *type*. `PartModel`, `PartDefinition`,
  `PartRegistry`, `standardParts`.
- A **component** is one placed in a circuit — the three LEDs in *this* one.
  `ComponentInstance`, and `ComponentProps` for its property map.

Both were once called `Component*`, which made `ComponentModel` and
`ComponentInstance` sit side by side meaning different things. If a new type
belongs to the catalog it is a `Part*`; if it belongs to something placed, a
`Component*`.

## Painters are domain, not decoration

The one thing to understand before moving anything here.

`PortProvider` is a *painter* mixin, so a painter is where a part's pin
geometry is defined — not merely how it looks. `CircuitNetlist.build` finds a
component's ports by asking its painter, and it does so inside the simulation
isolate, on components rebuilt from JSON.

So painters cannot be separated from the models as a "UI layer". If they were,
the simulation would find no pins: an empty netlist, nothing lit, and no error
anywhere.

## Physical scale

Parts are drawn at their real size. Every connection point sits on the
`GridSystem` lattice whose pitch is one breadboard hole — 0.1" = 2.54 mm — so
`GridSystem.pitch` (16 px) ≡ 2.54 mm, and `PhysicalScale.pxPerMm` follows.

Two rules keep that from fighting the grid:

- **Bodies** are exact real-world sizes. Fractional pixels are fine, because
  nothing snaps to a body.
- **Leads and ports** stay on the 16 px lattice, so lead spacing is always a
  whole number of hole pitches — which is what a real part gets bent to when it
  goes into a breadboard.

`test/real_world_dimensions_test.dart` pins the published body sizes. A few
parts are deliberately drawn slightly under datasheet size to read well beside
their neighbours; those record both figures as `drawn X (real Y)`.

## Assets

The Arduino board art and any `.pdl` definitions ship with this package, so
consumers do not declare them. Flutter namespaces package assets, which is why
`PartRegistry` scans the manifest for `packages/pinbench_parts/assets/parts/` and
the SVG loads from that same prefix.

## Dependencies

`flutter`, `flutter_svg` (board art), `google_fonts` (the monospace face pin
labels are set in), and the two format packages, `pinbench_pdl` and
`pinbench_cdl`. That is the whole list, and it is worth keeping short —
`test/architecture/layering_test.dart` in the app fails if this package ever
imports the app back, and if either format package ever picks up Flutter.
