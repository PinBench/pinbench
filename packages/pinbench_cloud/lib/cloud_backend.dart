import 'auth/auth_service.dart';
import 'project_repository.dart';

/// A running connection to a cloud backend: who is signed in, and where their
/// projects are stored.
typedef CloudSession = ({AuthService auth, ProjectRepository? projects});

/// What a build's cloud backend provides.
///
/// The app never names a backend. It gets one, or none, from the build's
/// edition (`package:pinbench_edition_api`) at startup. A build from source
/// has none, so it is fully local, with sign-in and every cloud feature
/// hidden; builds that do have a backend change nothing above this interface.
abstract interface class CloudBackend {
  /// Connects and restores any saved session.
  ///
  /// Awaited once during startup, before the first frame — see
  /// `app/bootstrap.dart`. The session's `projects` is null when this backend
  /// has no project storage.
  Future<CloudSession> connect();
}
