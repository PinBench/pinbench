import 'package:pinbench_entitlements/pinbench_entitlements.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pro_provider.g.dart';

/// The active [ProGateway].
///
/// Reads whatever `Pro.register` installed at startup. The open-source build
/// registers nothing, so this is [FreeProGateway]; the commercial build swaps
/// in its own implementation via `pubspec_overrides.yaml`. Feature code should
/// never construct a gateway itself — see `packages/pinbench_entitlements/README.md`.
@Riverpod(keepAlive: true)
ProGateway proGateway(Ref ref) => Pro.instance;

/// Whether [feature] may be used right now, as a [ProAccess] so the UI can say
/// *why* rather than only whether — a quota that will reset and a tier that
/// never included the feature deserve different words.
@riverpod
ProAccess proFeature(Ref ref, ProFeature feature) => ref.watch(proGatewayProvider).check(feature);
