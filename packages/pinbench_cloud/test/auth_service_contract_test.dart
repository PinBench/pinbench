import 'package:pinbench_cloud/auth/auth_service.dart';
import 'package:pinbench_cloud/auth/auth_user.dart';
import 'package:flutter_test/flutter_test.dart';

/// The [AuthService] contract is what lets the backend be swapped without
/// touching call sites, so the parts call sites actually depend on are pinned
/// here rather than left as prose in the interface doc.
void main() {
  group('DisabledAuthService', () {
    const service = DisabledAuthService();

    test('reports itself disabled', () {
      expect(service.enabled, isFalse);
      expect(service.currentUser, isNull);
    });

    test('sign-in and sign-out are no-ops rather than errors', () async {
      // The app runs fully offline with local workspaces; a build with no
      // backend must not throw its way through the cloud UI.
      await expectLater(service.signInWithGoogle(), completion(isNull));
      await expectLater(service.signOut(), completes);
    });

    test('emits no user', () {
      expect(service.onAuthChanged, emitsInOrder([emitsDone]));
    });
  });

  group('AuthUser', () {
    test('compares by value, so identical users do not spuriously rebuild', () {
      // authStateProvider is a stream of these; without value equality every
      // emission would look like a change to Riverpod.
      const a = AuthUser(uid: 'u1', email: 'a@b.com', displayName: 'A');
      const b = AuthUser(uid: 'u1', email: 'a@b.com', displayName: 'A');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differs when the uid differs', () {
      const a = AuthUser(uid: 'u1');
      const b = AuthUser(uid: 'u2');
      expect(a, isNot(equals(b)));
    });

    test('carries no avatar when the provider supplies none', () {
      // Not every provider has a photo field, so this is a normal case.
      const user = AuthUser(uid: 'u1');
      expect(user.photoUrl, isNull);
    });

    test('does not leak an email into toString beyond the fields it names', () {
      const user = AuthUser(uid: 'u1', email: 'a@b.com', displayName: 'Someone');
      expect(user.toString(), 'AuthUser(u1, a@b.com)');
    });
  });
}
