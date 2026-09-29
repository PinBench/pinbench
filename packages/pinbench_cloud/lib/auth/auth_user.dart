import 'package:flutter/foundation.dart' show immutable;

/// The signed-in user, as the app needs them — independent of which backend
/// authenticated them.
///
/// Deliberately four fields rather than a passthrough of the provider's user
/// object. Everything the app actually reads is here; carrying the rest would
/// tie the UI to one provider's model and make swapping backends a change to
/// every widget that shows a name.
@immutable
class const AuthUser({
  /// Stable per-provider identifier. This is what project ownership,
  /// collaborator maps and access checks are keyed on, so it must come from
  /// whichever backend is actually authenticating — a uid from one provider is
  /// meaningless to another.
  required final String uid,
  final String? email,
  final String? displayName,

  /// Avatar URL, or null when the provider doesn't supply one, in which case
  /// the UI falls back to a placeholder icon.
  final String? photoUrl,
}) {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthUser &&
          other.uid == uid &&
          other.email == email &&
          other.displayName == displayName &&
          other.photoUrl == photoUrl;

  @override
  int get hashCode => Object.hash(uid, email, displayName, photoUrl);

  @override
  String toString() => 'AuthUser($uid, $email)';
}
