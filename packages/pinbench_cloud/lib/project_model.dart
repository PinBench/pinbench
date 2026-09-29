import 'project_repository.dart' show ProjectRepository;

/// A collaborator's permission level on a [Project].
///
/// - [owner]: full control — can edit files, manage collaborators, delete the
///   project. A project's `ownerId` always implicitly has [owner] access even
///   if not (or no longer) present in `collaborators`.
/// - [editor]: can read/write files, cannot manage collaborators or delete.
/// - [viewer]: read-only access to files.
enum ProjectRole() {
  owner,
  editor,
  viewer;

  static ProjectRole fromName(String? name) =>
      ProjectRole.values.firstWhere((r) => r.name == name, orElse: () => ProjectRole.viewer);
}

/// Who can *read* a [Project], independently of its collaborator list.
///
/// This only ever widens read access. Writing is always restricted to the
/// owner and `editor` collaborators, whatever the visibility.
///
/// > ⚠️ [unlisted] is **not** a security boundary. No backend can tell
/// > "someone who was given the link" from "someone who guessed an id", so
/// > unlisted and [public] grant exactly the same read access. The difference
/// > is discoverability in the app, not protection. Never put anything
/// > sensitive in a project that is not [private].
enum ProjectVisibility() {
  /// Owner and collaborators only. The default, and the only setting that
  /// actually restricts reads.
  private,

  /// Anyone holding the link can open it read-only. Not listed anywhere.
  unlisted,

  /// Same read access as [unlisted], but eligible to appear in listings such
  /// as a public gallery.
  public;

  static ProjectVisibility fromName(String? name) => ProjectVisibility.values.firstWhere(
    (v) => v.name == name,
    // Unknown or missing => private. A parsing slip must never widen access,
    // and documents written before this field existed have none.
    orElse: () => ProjectVisibility.private,
  );

  /// Whether a signed-out stranger with the link may read this.
  bool get isSharedByLink => this != ProjectVisibility.private;
}

/// A cloud-backed Arduino project.
///
/// Holds the project's metadata and access lists; its source content is a set
/// of [ProjectFile]s, fetched separately.
class const Project({
  required final String id,
  required final String name,
  required final String ownerId,
  required final DateTime createdAt,
  required final DateTime updatedAt,

  /// uid -> role. Does not need to (but may) include the owner; the owner is
  /// always treated as having [ProjectRole.owner] regardless of this map.
  final Map<String, ProjectRole> collaborators = const {},

  /// Lowercased email -> role, for people invited who have not opened the
  /// project yet.
  ///
  /// The auth backend deliberately gives clients no way to resolve an email
  /// to a uid, so an invite cannot be turned into a [collaborators] entry by
  /// the person sending it. Instead the invite is stored here, and the invitee
  /// converts it themselves the first time they open the project — the
  /// backend lets a signed-in user move *their own* verified email out of this
  /// map and into [collaborators] at exactly the role recorded here, and
  /// nothing else.
  ///
  /// > ⚠️ Readable by anyone who can read the project, so a link-shared
  /// > project exposes the addresses of everyone invited to it. Keep that in
  /// > mind before inviting people to something public.
  final Map<String, ProjectRole> pendingInvites = const {},

  /// uid -> the email that uid claimed their invite with.
  ///
  /// Collaborators are keyed by uid, which is meaningless to a human, and no
  /// auth backend here lets a client look a uid up. So the only moment the app
  /// ever learns the pairing is when the invitee claims their own invite — they know
  /// their own email, and they are already writing to the document. Recording
  /// it there is what lets the share sheet list people by address instead of by
  /// an opaque id.
  ///
  /// Absent for anyone added before this existed; the UI falls back to the uid.
  final Map<String, String> collaboratorEmails = const {},

  /// Who may read this project. See [ProjectVisibility] — in particular, that
  /// `unlisted` is about discoverability, not security.
  final ProjectVisibility visibility = ProjectVisibility.private,
}) {
  /// A human label for [uid]: their email if known, otherwise the raw uid.
  String labelFor(String uid) => collaboratorEmails[uid] ?? uid;

  /// The role [email] was invited at, or `null` if there is no open invite.
  /// Comparison is case-insensitive: email local-parts are case-sensitive in
  /// theory, but no mainstream provider treats them that way, and a user typing
  /// `Bob@x.com` must match an invite stored as `bob@x.com`.
  ProjectRole? inviteFor(String email) => pendingInvites[email.trim().toLowerCase()];

  /// All uids with access to this project, owner included, deduplicated.
  Set<String> get memberUids => {ownerId, ...collaborators.keys};

  /// Effective role for [uid], or `null` if they have no access.
  ProjectRole? roleFor(String uid) {
    if (uid == ownerId) return ProjectRole.owner;
    return collaborators[uid];
  }

  Project copyWith({
    String? name,
    DateTime? updatedAt,
    Map<String, ProjectRole>? collaborators,
    Map<String, ProjectRole>? pendingInvites,
    Map<String, String>? collaboratorEmails,
    ProjectVisibility? visibility,
  }) => Project(
    id: id,
    name: name ?? this.name,
    ownerId: ownerId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    collaborators: collaborators ?? this.collaborators,
    pendingInvites: pendingInvites ?? this.pendingInvites,
    collaboratorEmails: collaboratorEmails ?? this.collaboratorEmails,
    visibility: visibility ?? this.visibility,
  );
}

/// One source file within a project.
///
/// [id] is opaque and backend-assigned (not derived from [path]); callers look
/// files up by their [path] via [ProjectRepository.watchFiles].
///
/// This model intentionally supports only last-write-wins replacement of a
/// file's full `content` on each write — there is no operational-transform or
/// CRDT merge of concurrent edits. Two collaborators editing the same file at
/// the same time will have one write clobber the other; real-time sync here
/// means "everyone sees the latest write quickly", not "conflict-free
/// concurrent editing".
class const ProjectFile({
  required final String id,
  required final String path,
  required final String content,
  required final DateTime updatedAt,
  required final String updatedBy,
});

/// Lightweight pointer used to build the "recent projects" list without
/// fetching each full [Project] document.
///
/// Re-opening a project replaces its entry instead of adding another. The
/// [name] shown here is denormalized from the project at
/// the time [ProjectRepository.addRecent] was called, so the recents list can
/// render without an extra read per entry. It may go stale if the project is
/// later renamed — feature code that needs the live name should read the
/// [Project] document itself.
class const RecentProject({
  required final String id,
  required final String name,
  required final DateTime lastOpenedAt,
});
