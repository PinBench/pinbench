import 'package:pinbench_pro/pinbench_pro.dart';
import 'package:pinbench/core/entitlements/pro_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('a self-hosted build unlocks them', () {
    // Standing up your own backend is a supported path, not something to be
    // upsold out of. The share sheet says so rather than offering checkout.
    Pro.register(const SelfHostedProGateway());
    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    expect(container2.read(proFeatureProvider(ProFeature.privateShareLinks)).isAllowed, isTrue);
  });

  test('the denial explains itself', () {
    final access = container.read(proFeatureProvider(ProFeature.privateShareLinks));
    expect(access, isA<ProDenied>());
    // Drives which copy the dialog shows: "upgrade" is the wrong thing to say
    // to someone running their own instance.
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
