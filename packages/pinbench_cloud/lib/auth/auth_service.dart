import 'auth_user.dart';

/// Sign-in, sign-out, and who is currently signed in.
///
/// An interface rather than a concrete class so the backend can be swapped
/// without touching call sites. The implementation comes from the build's
/// `CloudBackend`; [DisabledAuthService] stands in when there is none.
///
/// The contract, which call sites rely on and implementations must honour:
///
/// - **Disabled is a valid state, not an error.** When [enabled] is false every
///   method is a safe no-op, so callers never need their own guards. This is
///   what lets the app run with no backend at all.
/// - **[onAuthChanged] emits the current value on listen**, then on every
///   change. A widget that subscribes after sign-in still learns who is signed
///   in, rather than waiting for a change that may never come.
/// - **[signInWithGoogle] throws on failure** rather than returning null, so
///   callers can tell the user why it didn't complete. It returns null only
///   when sign-in is unavailable on this platform.
/// - **[signOut] never throws.** A failed sign-out is logged, not surfaced —
///   there is nothing useful for a user to do about it, and blocking them on a
///   screen they are trying to leave is worse.
abstract interface class AuthService {
  /// Whether a backend is configured. False means every method is a no-op.
  bool get enabled;

  /// The signed-in user, or null when signed out or disabled.
  AuthUser? get currentUser;

  /// The signed-in user over time, emitting null when signed out.
  Stream<AuthUser?> get onAuthChanged;

  /// Runs the Google sign-in flow, returning the signed-in user, or null when
  /// sign-in is unavailable on this platform.
  ///
  /// Must be called from a user-gesture handler so the browser allows the
  /// popup. The same call covers sign-up: an unrecognised Google identity gets
  /// an account created for it, so the UI needs one button rather than two.
  Future<AuthUser?> signInWithGoogle();

  /// Signs the current user out. Does not throw.
  Future<void> signOut();
}

/// [AuthService] for builds with no auth backend configured.
///
/// Exists so "no backend" is expressed once, here, rather than as a null check
/// at every call site — the app runs fully offline with local workspaces, and
/// only the cloud features are absent.
class DisabledAuthService implements AuthService {
  const DisabledAuthService();

  @override
  bool get enabled => false;

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> get onAuthChanged => const Stream.empty();

  @override
  Future<AuthUser?> signInWithGoogle() async => null;

  @override
  Future<void> signOut() async {}
}
