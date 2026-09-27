import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:pinbench_cloud/appwrite/appwrite_project_repository.dart';
import 'package:pinbench_cloud/project_model.dart';
import 'package:pinbench_cloud/project_repository.dart';

import '../auth/auth_provider.dart';

part 'project_providers.g.dart';

/// The [ProjectRepository], or `null` when no cloud backend is available on
/// this platform/build.
// Kept alive because the things that drive it are: the `WorkspaceFiles` notifier, which is keep-alive.
// A `@Riverpod(keepAlive: true)` provider reading an autoDispose one pins it
// through a `KeepAliveLink` anyway, so this is what already happens at
// runtime — saying it out loud is what `only_use_keep_alive_inside_keep_alive`
// asks for, and it stops the lifetime depending on who happens to be watching.
@Riverpod(keepAlive: true)
ProjectRepository? projectRepository(Ref ref) {
  final client = ref.watch(appwriteClientProvider);
  if (client == null) return null;
  // The one place the backend is chosen: everything above this line talks to
  // [ProjectRepository], so a different backend is a new implementation of it
  // and a change here. (The Firestore implementation this replaced is gone —
  // it is in git history, not in the tree.)
  //
  // `.forClient` rather than assembling services here: which ones an Appwrite
  // repository is made of is `package:pinbench_cloud`'s business, and this file is
  // the seam, not the backend.
  return AppwriteProjectRepository.forClient(client);
}

/// The signed-in user's recent cloud projects, ordered most-recent-first.
/// Empty when signed out or no cloud backend is available.
@riverpod
Stream<List<RecentProject>> cloudRecentProjects(Ref ref) {
  final repo = ref.watch(projectRepositoryProvider);
  final user = ref.watch(authStateProvider).value;
  if (repo == null || user == null) return const Stream<List<RecentProject>>.empty();
  return repo.listRecentProjects(user.uid);
}
