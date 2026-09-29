import 'project_model.dart';

/// The app's entire view of cloud project storage.
///
/// Every feature reaches cloud data through this interface and nothing else —
/// no widget or provider touches a database SDK directly. That was true by
/// convention before it was an interface, which is why extracting it changed
/// no call sites.
///
/// It exists so the backend is replaceable: the implementation is supplied by
/// the build's `CloudBackend`, and tests use fakes of the same surface.
///
/// ### What an implementation owes the caller
///
/// - **Reads throw rather than returning null on permission errors.** Callers
///   distinguish "not found" (`null`) from "not allowed" (an exception), and
///   `openCloudProject` depends on that difference.
/// - **Streams stay live** and emit on every change, including the caller's
///   own writes. Self-echo suppression is the caller's job — see
///   `CloudProjectSync`.
/// - **Timestamps arrive as `DateTime`.** Backend-specific time types must not
///   reach [Project] or its siblings; converting them is the implementation's
///   responsibility.
/// - **File writes are last-write-wins.** No implementation is expected to
///   merge concurrent edits to the same file.
///
/// ### Authorization is not here
///
/// Nothing in this interface enforces who may do what — that lives in the
/// backend's own rules. An implementation is free to let a call through and
/// have the backend reject it; callers must handle the resulting error either
/// way.
abstract interface class ProjectRepository {
  /// Creates a new project owned by [ownerId] and returns the created
  /// [Project]. The owner is not added to `collaborators` — ownership is
  /// tracked solely via `ownerId` and always implies [ProjectRole.owner].
  Future<Project> createProject({required String name, required String ownerId});

  /// One-shot fetch of a project, or `null` if it doesn't exist.
  Future<Project?> getProject(String projectId);

  /// Streams a project's document, emitting `null` if it doesn't (or no
  /// longer) exists.
  Stream<Project?> watchProject(String projectId);

  /// Renames a project and bumps `updatedAt`.
  Future<void> renameProject(String projectId, String name);

  /// Deletes a project. Does not cascade-delete its files, so callers that
  /// need full cleanup should delete the files first, or rely on a backend
  /// job.
  /// Backend permissions restrict this to the owner.
  Future<void> deleteProject(String projectId);

  /// Creates or updates a file at [path] within a project, overwriting the
  /// `content` of an existing file at that path or creating one if none
  /// exists yet. Last-write-wins — see class
  /// doc for the concurrency caveat.
  Future<void> updateFile(
    String projectId,
    String path,
    String content, {
    required String updatedBy,
  });

  /// Deletes a file by its backend-assigned id (as returned in
  /// [ProjectFile.id] from [watchFiles]), not by its path.
  Future<void> deleteFile(String projectId, String fileId);

  /// One-shot fetch of all files in a project.
  Future<List<ProjectFile>> getFiles(String projectId);

  /// Streams all files in a project in real time — the primary hook for
  /// cloud file persistence and multi-client sync features.
  Stream<List<ProjectFile>> watchFiles(String projectId);

  /// Records that [uid] opened [projectId] just now, denormalizing the
  /// project's current name for fast recents rendering. No-ops if the
  /// project can't be found.
  Future<void> addRecent(String uid, String projectId);

  /// Removes [projectId] from [uid]'s recents list.
  Future<void> removeRecent(String uid, String projectId);

  /// Streams [uid]'s recent projects ordered most-recently-opened first.
  Stream<List<RecentProject>> listRecentProjects(String uid, {int limit = 20});

  /// Grants [targetUid] [role] on [projectId]. Overwrites any existing role
  /// for that uid. Security rules restrict this to the project owner.
  Future<void> shareProject(String projectId, String targetUid, ProjectRole role);

  /// Invites [email] to [projectId] at [role].
  ///
  /// The invite is stored on the project keyed by lowercased email; it becomes
  /// a real collaborator entry only when that person signs in and opens the
  /// project (see [claimInvite]). Clients cannot resolve an email to a uid, so
  /// there is no way to grant access directly.
  ///
  /// Inviting an address that never signs in simply leaves a pending entry.
  Future<void> inviteByEmail(String projectId, String email, ProjectRole role);

  /// Withdraws the pending invite for [email], if any.
  Future<void> revokeInvite(String projectId, String email);

  /// Converts a pending invite for [email] into a collaborator entry for [uid],
  /// returning the granted role — or `null` if there was no invite.
  ///
  /// Called on the invitee's own behalf when they open a project. The security
  /// rules permit exactly this move and nothing else: the caller's own verified
  /// email out of `pendingInvites`, into `collaborators` under their own uid, at
  /// precisely the role the invite recorded. They cannot invent a role, claim
  /// someone else's invite, or touch any other field.
  Future<ProjectRole?> claimInvite(String projectId, String uid, String email);

  /// Sets who may read [projectId] — see [ProjectVisibility].
  ///
  /// Only the owner may call this successfully; the security rules reject a
  /// visibility change from an `editor`, because publishing someone else's
  /// project is an access-control decision, not an edit.
  ///
  /// Making a project [ProjectVisibility.unlisted] or [ProjectVisibility.public]
  /// grants read access to **anyone with the link, signed in or not**. It never
  /// grants write access.
  Future<void> setVisibility(String projectId, ProjectVisibility visibility);

  /// Revokes [uid]'s collaborator access to [projectId]. No-op if they were
  /// never a collaborator (owner access, granted via `ownerId`, is
  /// unaffected — an owner cannot be removed this way).
  Future<void> removeCollaborator(String projectId, String uid);

  /// Returns [uid]'s effective role on [projectId], or `null` if they have no
  /// access (including when the project doesn't exist).
  Future<ProjectRole?> myRole(String projectId, String uid);
}
