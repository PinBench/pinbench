import 'package:pinbench_pdl/pinbench_pdl.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

/// The declarative simulation path: `BEHAVIOR` rules turning pin voltages and
/// properties into state and SPICE element values.
///
/// Deliberately tested through the evaluator rather than a running engine —
/// the evaluator takes values in and hands values back, which is the property
/// that makes a data-driven part debuggable at all.
void main() {
  PartDefinition define(String body) {
    final result = PdlParser.parse('''
PART "Test"
ID test
SIZE 32px 16px
SVG "t.svg"

PINS
  a 4px 4px passive "A"
  b 20px 4px passive "B"

$body
''');
    // Not `expect` — this runs while groups are being declared, outside any
    // test, where matchers throw OutsideTestException instead of failing.
    if (result.definition == null || result.diagnostics.isNotEmpty) {
      throw StateError('fixture PDL did not parse cleanly:\n${result.diagnostics.join('\n')}');
    }
    return result.definition!;
  }

  group('rule ordering', () {
    final definition = define('''
STATE
  level decimal 0
  doubled decimal 0

BEHAVIOR
  state.level   = 4
  state.doubled = state.level * 2
''');

    test('a later rule sees what an earlier one wrote', () {
      // This is what lets a part read as two readable steps instead of one
      // unreadable expression — and it means rule order is load-bearing.
      final result = PdlBehaviorEvaluator.evaluate(definition, {});
      expect(result.state['level'], 4.0);
      expect(result.state['doubled'], 8.0);
    });
  });

  group('inputs', () {
    final definition = define('''
STATE
  reading decimal 0
  high boolean false

BEHAVIOR
  state.reading = map(analog(a), 0, 5, 0, 1023)
  state.high    = digital(a)
''');

    test('reads solved pin voltages', () {
      final result = PdlBehaviorEvaluator.evaluate(
        definition,
        {},
        analog: (id) => id == 'a' ? 5 : 0,
      );
      expect(result.state['reading'], closeTo(1023, 1e-9));
      expect(result.state['high'], isTrue);
    });

    test('with no circuit every pin reads 0V and the part still runs', () {
      // A part on a canvas with no Arduino should show its idle state rather
      // than freeze, so this must not throw or produce null.
      final result = PdlBehaviorEvaluator.evaluate(definition, {});
      expect(result.state['reading'], 0.0);
      expect(result.state['high'], isFalse);
    });
  });

  group('state typing survives the round trip through the property map', () {
    final definition = define('''
STATE
  count integer 0
  flag boolean false
  note string ""

BEHAVIOR
  state.count = 2.7
  state.flag  = 1
  state.note  = "v=" + 3
''');

    test('declared types are honoured, not just whatever the maths produced', () {
      final result = PdlBehaviorEvaluator.evaluate(definition, {});
      expect(result.state['count'], 3, reason: 'an integer state should round, not stay 2.7');
      expect(result.state['count'], isA<int>());
      expect(result.state['flag'], isTrue);
      expect(result.state['flag'], isA<bool>());
      expect(result.state['note'], 'v=3');
    });
  });

  group('state persists across frames via the component property map', () {
    final definition = define('''
STATE
  ticks integer 0

BEHAVIOR
  state.ticks = state.ticks + 1
''');

    test('feeding the previous result back in advances it', () {
      // This is exactly what the frame updater does: last frame's state was
      // written into the node's properties, and is read back as the starting
      // point for this one.
      var properties = <String, dynamic>{};
      for (var frame = 1; frame <= 3; frame++) {
        final result = PdlBehaviorEvaluator.evaluate(definition, properties);
        expect(result.state['ticks'], frame);
        properties = Map<String, dynamic>.from(result.state);
      }
    });

    test('an absent value starts from the declared initial, not null', () {
      final result = PdlBehaviorEvaluator.evaluate(definition, {});
      expect(result.state['ticks'], 1);
    });
  });

  group('physics rules', () {
    final definition = define('''
PROPERTIES
  dark  number 1000000
  light number 1000

STATE
  level decimal 0

BEHAVIOR
  state.level        = clamp(prop.illumination, 0, 100) / 100
  physics.resistance = max(prop.dark - state.level * (prop.dark - prop.light), prop.light)

PHYSICS resistor
  n1 = a
  n2 = b
''');

    test('a property change moves the resistance', () {
      double resistanceAt(num illumination) => PdlBehaviorEvaluator.physicsFor(definition, {
        'illumination': illumination,
      })['resistance']!;

      expect(resistanceAt(0), 1000000, reason: 'dark');
      expect(resistanceAt(100), 1000, reason: 'full light');
      expect(resistanceAt(50), closeTo(500500, 1e-6), reason: 'halfway');
    });

    test('never goes below the published light resistance, whatever the input', () {
      // The clamp matters: a negative resistance is not merely wrong, it makes
      // the operating-point solve fail for the whole circuit.
      for (final illumination in [-500, 0, 50, 100, 5000]) {
        final r = PdlBehaviorEvaluator.physicsFor(definition, {
          'illumination': illumination,
        })['resistance']!;
        expect(r, greaterThanOrEqualTo(1000));
        expect(r.isFinite, isTrue);
      }
    });

    test('physicsFor is what SpiceEngine.build uses for the starting value', () {
      // If this drifted from evaluate(), an element would start at one value
      // and be altered to another on the first frame — a visible flicker with
      // no obvious cause.
      final viaEvaluate = PdlBehaviorEvaluator.evaluate(definition, {'illumination': 25}).physics;
      final viaPhysicsFor = PdlBehaviorEvaluator.physicsFor(definition, {'illumination': 25});
      expect(viaPhysicsFor, viaEvaluate);
    });
  });

  test('a part with no BEHAVIOR produces nothing to apply', () {
    final definition = define('');
    final result = PdlBehaviorEvaluator.evaluate(definition, {});
    expect(result.physics, isEmpty);
    expect(result.visuals, isEmpty);
    expect(result.state, isEmpty);
  });

  group('the bundled parts behave like the components they model', () {
    Future<PartDefinition> load(String id) async {
      final dir = 'packages/pinbench_parts/assets/parts/$id';
      final result = PdlParser.parse(await _readAsset('$dir/$id.pdl'), assetDirectory: dir);
      expect(result.diagnostics, isEmpty, reason: result.diagnostics.join('\n'));
      return result.definition!;
    }

    double resistance(PartDefinition part, Map<String, dynamic> props) =>
        PdlBehaviorEvaluator.physicsFor(part, props)['resistance']!;

    test('the thermistor follows its Beta curve through 25 °C', () async {
      final ntc = await load('thermistor');
      // The defining point: a 10k NTC reads its nominal value at 25 °C, so if
      // the exponent is wrong in any way this is where it shows.
      expect(resistance(ntc, {'temperature': 25}), closeTo(10000, 0.5));
      expect(resistance(ntc, {'temperature': 0}), greaterThan(25000), reason: 'cold');
      expect(resistance(ntc, {'temperature': 100}), lessThan(1000), reason: 'hot');
    });

    test('the thermistor stays finite outside its rated range', () async {
      final ntc = await load('thermistor');
      for (final t in [-273, -100, 0, 25, 200, 1000]) {
        final r = resistance(ntc, {'temperature': t});
        expect(r.isFinite, isTrue, reason: 'at $t °C');
        expect(r, greaterThan(0), reason: 'a negative resistance breaks the solve');
      }
    });

    test('the slide switch is a short when closed and an open circuit when not', () async {
      final sw = await load('slide_switch');
      final closed = resistance(sw, {'closed': true});
      final open = resistance(sw, {'closed': false});
      expect(closed, lessThan(1));
      expect(open, greaterThan(1e6));
      // Far enough apart that neither is confusable with a real component.
      expect(open / closed, greaterThan(1e6));
    });

    test('the switch drives its knob colour from state', () async {
      final sw = await load('slide_switch');
      Object? knob({required bool closed}) =>
          PdlBehaviorEvaluator.evaluate(sw, {'closed': closed}).visuals['knob'];
      expect(knob(closed: true), isNotNull);
      expect(knob(closed: false), isNotNull);
      expect(
        knob(closed: true),
        isNot(knob(closed: false)),
        reason: 'the knob should change colour',
      );
    });

    test('the coin cell holds 3V and never goes negative', () async {
      final cell = await load('cr2032');
      double voltage(Map<String, dynamic> p) =>
          PdlBehaviorEvaluator.physicsFor(cell, p)['voltage']!;
      expect(voltage({}), 3);
      expect(voltage({'voltage': 1.8}), 1.8);
      expect(voltage({'voltage': -5}), 0, reason: 'a dead cell reads 0V, not a reversed one');
    });

    test('the diode is PHYSICS-only — no rules to run', () async {
      final diode = await load('diode_1n4148');
      expect(diode.behavior, isEmpty);
      expect(diode.spiceModel!.type, SpiceComponentType.diode);
      expect(diode.spiceModel!.pinMapping, {'n1': 'anode', 'n2': 'cathode'});
    });
  });

  test('the bundled photoresistor behaves as its datasheet comment claims', () async {
    // An end-to-end check against the part actually shipped, not a fixture.
    final result = PdlParser.parse(
      await _readAsset('packages/pinbench_parts/assets/parts/ldr/ldr.pdl'),
      assetDirectory: 'packages/pinbench_parts/assets/parts/ldr',
    );
    expect(result.diagnostics, isEmpty, reason: result.diagnostics.join('\n'));

    final ldr = result.definition!;
    final dark = PdlBehaviorEvaluator.physicsFor(ldr, {'illumination': 0})['resistance']!;
    final lit = PdlBehaviorEvaluator.physicsFor(ldr, {'illumination': 100})['resistance']!;
    expect(dark, greaterThan(lit), reason: 'resistance must fall as light rises');
    expect(lit, 1000);
  });
}

Future<String> _readAsset(String key) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final data = await rootBundle.loadString(key);
  return data;
}
