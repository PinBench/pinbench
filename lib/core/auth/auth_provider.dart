import 'package:appwrite/appwrite.dart' show Client;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:pinbench_cloud/auth/auth_service.dart';
import 'package:pinbench_cloud/auth/auth_user.dart';

part 'auth_provider.g.dart';

/// Provider for the [AuthService]. Defaults to [DisabledAuthService] (every
/// method is a no-op), and is overridden in `app/bootstrap.dart` when an auth
/// backend is available.
/// A plain [Provider], like every override placeholder here — see
/// `sharedPreferencesProvider`.
final authServiceProvider = Provider<AuthService>((ref) => const DisabledAuthService());

/// Provider for the authenticated Appwrite [Client]. Defaults to `null`;
/// overridden in `app/bootstrap.dart`.
///
/// The client, not the individual services, because the session lives on it —
/// a separately-constructed `TablesDB` would read unauthenticated and every row
/// permission would deny it. Services are built from this where needed.
final appwriteClientProvider = Provider<Client?>((ref) => null);

/// Streams the current auth state. Emits `null` when signed out or disabled.
@riverpod
Stream<AuthUser?> authState(Ref ref) {
  final service = ref.watch(authServiceProvider);
  if (!service.enabled) return const Stream<AuthUser?>.empty();
  return service.onAuthChanged;
}
