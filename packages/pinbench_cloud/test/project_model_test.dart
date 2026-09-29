import 'package:pinbench_cloud/project_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Visibility and roles are access-control fields: they decide who can read
/// or edit someone's project. Every default and every fallback here must fail
/// *closed*, because the failure mode is silent — an over-permissive value
/// publishes a private project and nothing visibly breaks.
void main() {
  Project project({
    Map<String, ProjectRole> collaborators = const {'editor-uid': ProjectRole.editor},
    Map<String, ProjectRole> pendingInvites = const {},
    Map<String, String> collaboratorEmails = const {},
    ProjectVisibility visibility = ProjectVisibility.private,
  }) => Project(
    id: 'p1',
    name: 'Blink',
    ownerId: 'owner-uid',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    collaborators: collaborators,
    pendingInvites: pendingInvites,
    collaboratorEmails: collaboratorEmails,
    visibility: visibility,
  );

  group('parsing fails closed', () {
    test('a missing or unrecognised visibility is private', () {
      for (final bad in [null, 'PUBLIC', 'Public', 'world', 'everyone', '', 'true']) {
        expect(
          ProjectVisibility.fromName(bad),
          ProjectVisibility.private,
          reason: 'visibility="$bad" must not widen access',
        );
      }
    });

    test('each recognised visibility parses back to itself', () {
      for (final visibility in ProjectVisibility.values) {
        expect(ProjectVisibility.fromName(visibility.name), visibility, reason: visibility.name);
      }
    });

    test('an unrecognised role is viewer, the least privileged', () {
      expect(ProjectRole.fromName('superuser'), ProjectRole.viewer);
      expect(ProjectRole.fromName(null), ProjectRole.viewer);
    });

    test('the constructor defaults to private', () {
      final bare = Project(
        id: 'p1',
        name: 'Blink',
        ownerId: 'owner-uid',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(bare.visibility, ProjectVisibility.private);
    });
  });

  group('isSharedByLink', () {
    test('only private is not shared', () {
      expect(ProjectVisibility.private.isSharedByLink, isFalse);
      expect(ProjectVisibility.unlisted.isSharedByLink, isTrue);
      expect(ProjectVisibility.public.isSharedByLink, isTrue);
    });
  });

  group('visibility is independent of roles', () {
    test('sharing by link does not grant anyone a role', () {
      // A stranger opening a shared link must still have no role, so any UI
      // gated on "can I edit?" stays closed for them.
      final shared = project(visibility: ProjectVisibility.public);
      expect(shared.roleFor('stranger-uid'), isNull);
      expect(shared.roleFor('owner-uid'), ProjectRole.owner);
      expect(shared.roleFor('editor-uid'), ProjectRole.editor);
    });

    test('memberUids does not grow when a project is published', () {
      expect(project(visibility: ProjectVisibility.public).memberUids, project().memberUids);
    });
  });

  group('pending invites', () {
    test('inviteFor is case- and whitespace-insensitive', () {
      final invited = project(pendingInvites: const {'bob@example.com': ProjectRole.editor});
      for (final typed in ['bob@example.com', 'Bob@Example.com', '  BOB@EXAMPLE.COM  ']) {
        expect(invited.inviteFor(typed), ProjectRole.editor, reason: typed);
      }
    });

    test('returns null when there is no invite for that address', () {
      final invited = project(pendingInvites: const {'bob@example.com': ProjectRole.editor});
      expect(invited.inviteFor('someone-else@example.com'), isNull);
    });

    test('an invite grants no access until claimed', () {
      // The whole security model: a pending invite is a promise, not a grant.
      final invited = project(
        collaborators: const {},
        pendingInvites: const {'bob@example.com': ProjectRole.editor},
      );
      expect(invited.roleFor('bob-uid'), isNull);
      expect(invited.memberUids, {'owner-uid'});
    });
  });

  group('collaborator emails', () {
    test('labelFor prefers the recorded email', () {
      final labelled = project(collaboratorEmails: const {'editor-uid': 'bob@example.com'});
      expect(labelled.labelFor('editor-uid'), 'bob@example.com');
    });

    test('labelFor falls back to the uid when no email was recorded', () {
      // A raw uid is poor, but a blank row would be worse — it would read as
      // a broken entry.
      expect(project().labelFor('editor-uid'), 'editor-uid');
    });

    test('recording an email grants no access by itself', () {
      final labelled = project(
        collaborators: const {},
        collaboratorEmails: const {'stranger-uid': 'stranger@example.com'},
      );
      expect(labelled.roleFor('stranger-uid'), isNull);
      expect(labelled.memberUids, {'owner-uid'});
    });
  });

  group('copyWith', () {
    test('changes visibility without disturbing anything else', () {
      final original = project();
      final published = original.copyWith(visibility: ProjectVisibility.unlisted);

      expect(published.visibility, ProjectVisibility.unlisted);
      expect(published.id, original.id);
      expect(published.name, original.name);
      expect(published.ownerId, original.ownerId);
      expect(published.collaborators, original.collaborators);
      expect(published.createdAt, original.createdAt);
    });

    test('omitting visibility preserves it rather than resetting to private', () {
      final published = project(visibility: ProjectVisibility.public);
      expect(published.copyWith(name: 'Renamed').visibility, ProjectVisibility.public);
    });
  });
}
