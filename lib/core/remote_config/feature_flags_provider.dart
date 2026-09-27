import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'feature_flags.dart';

/// App-wide feature-flag entry point. Overridden in `app/bootstrap.dart` with
/// a live [RemoteFeatureFlags] once Remote Config has fetched; defaults to
/// [FeatureFlags.disabled] so tests and unsupported platforms just work.
/// Follows the same override-placeholder pattern as `analyticsProvider`.
final featureFlagsProvider = Provider<FeatureFlags>((ref) => const FeatureFlags.disabled());
