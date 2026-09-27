import 'package:pinbench_pro/pinbench_pro.dart';
import 'package:pinbench/core/entitlements/pro_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the gateway a hosted edition registers.
final class _Paid implements ProGateway {
  const _Paid();

  @override
  ProTier get tier => ProTier.pro;

  @override
  ProLimits get limits => ProLimits.unlimited;

  @override
  ProAccess check(ProFeature feature) => const ProAllowed();

  @override
  Stream<void> get changes => const Stream<void>.empty();
}

/// The first paywall in the app. What matters is which side of the line each
/// feature sits on, and that the free tier stays a real product rather than a
/// demo — see packages/pinbench_pro/README.md.
void main() {
  late ProviderContainer container;

  setUp(() {
    Pro.reset();
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
    Pro.reset();
  });

  test('the open-source build gates embeds', () {
    expect(container.read(proFeatureProvider(ProFeature.privateShareLinks)).isAllowed, isFalse);
  });

  test('an edition that registers a gateway unlocks them', () {
    Pro.register(const _Paid());
    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    expect(container2.read(proFeatureProvider(ProFeature.privateShareLinks)).isAllowed, isTrue);
  });

  test('the denial explains itself', () {
    final access = container.read(proFeatureProvider(ProFeature.privateShareLinks));
    expect(access, isA<ProDenied>());
    // Drives which copy the dialog shows: a build from source has no checkout
    // to send anyone to.
    expect((access as ProDenied).reason, ProDenialReason.notAvailableInThisBuild);
  });

  test('sharing a link is never gated — it is the growth loop', () {
    // Nothing about plain link sharing consults the gateway. Pinned because
    // gating it later would be easy to do and very costly.
    expect(ProFeature.values.map((f) => f.name), isNot(contains('publicShareLinks')));
  });

  test('the provider reflects what was registered', () {
    expect(container.read(proGatewayProvider), isA<FreeProGateway>());
  });
}
