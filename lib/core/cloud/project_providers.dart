import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:pinbench_cloud/project_model.dart';
import 'package:pinbench_cloud/project_repository.dart';

import '../auth/auth_provider.dart';

part 'project_providers.g.dart';

/// The [ProjectRepository], or `null` when this build has no cloud backend.
///
/// An override placeholder like [authServiceProvider]: `app/bootstrap.dart`
/// fills it with whatever the build's `CloudBackend` handed out, so this file
/// never names a backend. A plain [Provider], which is kept alive — as it must
/// be, since the `WorkspaceFiles` notifier that reads it is keep-alive too.
final projectRepositoryProvider = Provider<ProjectRepository?>((ref) => null);

/// The signed-in user's recent cloud projects, ordered most-recent-first.
/// Empty when signed out or no cloud backend is available.
@riverpod
Stream<List<RecentProject>> cloudRecentProjects(Ref ref) {
  final repo = ref.watch(projectRepositoryProvider);
  final user = ref.watch(authStateProvider).value;
  if (repo == null || user == null) return const Stream<List<RecentProject>>.empty();
  return repo.listRecentProjects(user.uid);
}
