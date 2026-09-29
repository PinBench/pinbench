import 'package:pinbench_entitlements/pinbench_entitlements.dart';
import 'package:test/test.dart';

/// A gateway that allows everything, standing in for a commercial one.
final class _AllowAll implements ProGateway {
  const _AllowAll();

  @override
  ProTier get tier => ProTier.team;

  @override
  ProLimits get limits => ProLimits.unlimited;

  @override
  ProAccess check(ProFeature feature) => const ProAllowed();

  @override
  Stream<void> get changes => const Stream<void>.empty();
}

void main() {
  tearDown(Pro.reset);

  group('default gateway', () {
    test('is free tier when nothing is registered', () {
      expect(Pro.instance, isA<FreeProGateway>());
      expect(Pro.instance.tier, ProTier.free);
      expect(Pro.instance.tier.isPaid, isFalse);
    });

    test('denies every gateable feature as not-in-this-build', () {
      for (final feature in ProFeature.values) {
        final access = Pro.instance.check(feature);
        expect(access, isA<ProDenied>(), reason: '$feature');
        expect(
          (access as ProDenied).reason,
          ProDenialReason.notAvailableInThisBuild,
          reason: '$feature',
        );
      }
    });
  });

  group('register', () {
    test('installs the gateway', () {
      Pro.register(const _AllowAll());
      expect(Pro.instance.tier, ProTier.team);
      expect(Pro.has(ProFeature.aiAssistant), isTrue);
    });

    test('throws on a second call so entitlements have one source of truth', () {
      Pro.register(const _AllowAll());
      expect(() => Pro.register(const FreeProGateway()), throwsA(isA<StateError>()));
    });
  });

  group('unlimited quotas', () {
    test('have no limit on anything', () {
      expect(ProLimits.unlimited.cloudProjects, isNull);
      expect(ProLimits.unlimited.remoteCompilesPerDay, isNull);
    });
  });

  group('ProLimits.withinLimit', () {
    test('a null limit never blocks', () {
      expect(ProLimits.withinLimit(0, null), isTrue);
      expect(ProLimits.withinLimit(1000000, null), isTrue);
    });

    test('blocks once used reaches the limit', () {
      expect(ProLimits.withinLimit(4, 5), isTrue);
      expect(ProLimits.withinLimit(5, 5), isFalse);
      expect(ProLimits.withinLimit(6, 5), isFalse);
    });
  });

  group('free-tier quotas', () {
    test('are a real product, not a demo', () {
      // Guards against quietly ratcheting the free tier down to drive
      // conversion. Loosening these is fine; tightening needs a decision.
      expect(ProLimits.free.cloudProjects, greaterThanOrEqualTo(3));
      expect(ProLimits.free.remoteCompilesPerDay, greaterThanOrEqualTo(20));
    });
  });

  group('gating scope', () {
    test('no core local capability is gateable', () {
      // The open-core promise: local simulation, canvas, editor, components
      // and offline use are never gated. This test is the tripwire — if
      // someone adds e.g. `ProFeature.simulation`, it fails here first.
      const forbidden = <String>{
        'simulation',
        'canvas',
        'codeEditor',
        'localSave',
        'componentLibrary',
        'offlineUse',
        'undoRedo',
        'serialPlotter',
        'publicShareLinks',
      };
      final gated = ProFeature.values.map((f) => f.name).toSet();
      expect(gated.intersection(forbidden), isEmpty);
    });
  });
}
