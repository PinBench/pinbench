# pinbench_sim

The simulation engine for PinBench: an AVR emulator bridge,
an analog (SPICE) solver, the netlist that connects them, and the per-frame
loop that drives placed parts.

It knows nothing about the app. No canvas, no Riverpod, no file system, no
audio or recording plugins. What it needs from a host it takes as a port, and
the app supplies the implementation.

```
lib/
  core/         the engine — AVR bridge, SPICE, netlist, the frame loop,
                and the per-part behaviour dispatch
  core/updaters the Arduino's own I/O bridge (ADC in, input pins out) and
                the dispatcher for part behaviours
  isolate/      the background worker the engine runs in on native
  config/       AVR timing and simulation thresholds
  models/       run state and the debug snapshot
  services/     circuit validation
  diagnostics/  frame profiling
```

## The ports

Everything the engine needs from its host, and nothing more:

| Port | The host supplies |
| --- | --- |
| `SimulationOutput` | the circuit to run, and where per-frame updates go |
| `SketchCompiler` | sketch source → Intel HEX |
| `ToneOutput` | a speaker |
| `MicrophoneDevice` | a microphone |
| `SimLog.sink` | somewhere for diagnostics to land |

Each exists because the answer is genuinely the host's. How a sketch is built
differs by platform (`arduino-cli`, a remote service, a bundled hex); a speaker
and a microphone are devices; and the engine also runs in a background isolate
where none of the app's singletons exist.

`SimLog` is the one with a fallback: with no sink, errors still reach
`FlutterError.reportError` rather than vanishing, because a sink installed in
`main()` does not exist in the isolate.

## Parts behave; the engine does not know how

The engine does not know what an LED is. A part declares a behaviour by name
and `package:pinbench_parts` holds the implementation; `PartBehaviorFrameUpdater`
runs it against a narrow capability surface (its own pins, its own SPICE
element). Adding a peripheral does not mean editing this package.

The two exceptions are deliberate and documented in that updater: the
Arduino's own I/O bridge (feeding its ADC, writing its input pins) is the
*host board*, not a peripheral, and has no part to attach to.

## Invariants worth knowing before changing anything

- **One run loop.** `SimulationEngine` asserts on `_activeLoops` and carries a
  generation counter. Two loops ticking at once is the classic
  stop-then-restart bug.
- **Node keys survive a re-parse.** Frame updates are addressed by key; a key
  minted fresh on every parse orphans a live node from its updates, and the
  symptom is an LED that stops blinking after a restart while the sketch keeps
  running.

`test/engine_lifecycle_test.dart` and `test/simulation_restart_test.dart` pin
both.
