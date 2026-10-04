import 'package:pinbench_cloud/auth/auth_service.dart';
import 'package:pinbench_cloud/auth/auth_user.dart';

/// A build with sign-in configured and nobody signed in — the anonymous
/// visitor such a build is built to expect. The default `authServiceProvider`
/// is the disabled service, a build with no sign-in at all.
class SignedOutAuthService implements AuthService {
  @override
  bool get enabled => true;

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> get onAuthChanged => const Stream.empty();

  @override
  Future<AuthUser?> signInWithGoogle() async => null;

  @override
  Future<void> signOut() async {}
}
