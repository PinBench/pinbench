import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide [SharedPreferences] handle. Overridden in `main` with the real
/// instance once `SharedPreferences.getInstance()` resolves; throws if read
/// before that override is installed (there is no sensible default — unlike
/// the telemetry providers, which default to a disabled no-op).
///
/// A plain [Provider] rather than a generated one, like every override
/// placeholder in this app. Code generation earns its keep when a provider
/// computes something; this one exists only to be replaced, so all the
/// generator produced was a second file to keep in step. It also keeps the
/// provider out of `scoped_providers_should_specify_dependencies`, which only
/// inspects generated providers and cannot tell this app's root scope — built
/// inside the closure `runMultiApp` requires — from a nested one.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);
