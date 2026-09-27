import { Account, Client, Permission, Query, Role, TablesDB } from 'node-appwrite';

/**
 * Turns a pending email invitation into real collaborator access.
 *
 * ## Why this has to be server-side
 *
 * The client cannot do this, and that is the security model working rather
 * than a limitation to route around. A user with no permission on a row cannot
 * update that row to grant themselves permission — if they could, row-level
 * security would mean nothing. So the grant is made here, by a function
 * holding an API key, after it has verified the caller is who they claim.
 *
 * ## What it trusts
 *
 * Only the JWT. `x-appwrite-user-id` is *not* trusted on its own: it says who
 * the caller claims to be, and this endpoint's whole job is granting access,
 * so an unverified claim would let anyone assume any identity. The JWT is
 * verified by using it to call `account.get()` — if it is forged or expired,
 * Appwrite rejects that call and nothing is granted.
 *
 * The invitation is keyed by email, so the caller's email must also be
 * verified; otherwise anyone could sign up claiming a victim's address and
 * collect invitations meant for them.
 */

const DB = process.env.APPWRITE_DATABASE_ID || 'playground';
const PROJECTS = 'projects';
const FILES = 'files';

export default async ({ req, res, log, error }) => {
  const endpoint = process.env.APPWRITE_FUNCTION_API_ENDPOINT;
  const project = process.env.APPWRITE_FUNCTION_PROJECT_ID;

  let projectId;
  try {
    ({ projectId } = JSON.parse(req.body || '{}'));
  } catch {
    return res.json({ error: 'Body must be JSON' }, 400);
  }
  if (!projectId) return res.json({ error: 'projectId is required' }, 400);

  const jwt = req.headers['x-appwrite-user-jwt'];
  if (!jwt) return res.json({ error: 'Not signed in' }, 401);

  // Identity, established by the JWT rather than asserted by the caller.
  let user;
  try {
    const asUser = new Client().setEndpoint(endpoint).setProject(project).setJWT(jwt);
    user = await new Account(asUser).get();
  } catch (e) {
    error(`JWT rejected: ${e.message}`);
    return res.json({ error: 'Not signed in' }, 401);
  }

  if (!user.emailVerification) {
    // Invitations are addressed to an email. Accepting one from an account
    // that has not proven it owns that address would let anyone sign up as
    // someone else and collect their invitations.
    return res.json({ error: 'Verify your email address first' }, 403);
  }

  const email = (user.email || '').trim().toLowerCase();
  if (!email) return res.json({ error: 'Account has no email' }, 403);

  const admin = new Client()
    .setEndpoint(endpoint)
    .setProject(project)
    .setKey(req.headers['x-appwrite-key'] || process.env.APPWRITE_API_KEY);
  const tables = new TablesDB(admin);

  const row = await tables.getRow({ databaseId: DB, tableId: PROJECTS, rowId: projectId });

  const pendingInvites = parseMap(row.pendingInvites);
  const role = pendingInvites[email];
  if (!role) {
    // Not an error worth alarming the user about: the common cause is opening
    // a link twice, where the first visit already consumed the invitation.
    log(`No pending invite for ${email} on ${projectId}`);
    return res.json({ role: null });
  }

  const collaborators = { ...parseMap(row.collaborators), [user.$id]: role };
  const collaboratorEmails = { ...parseMap(row.collaboratorEmails), [user.$id]: email };
  delete pendingInvites[email];

  const permissions = permissionsFor(row.ownerId, collaborators, row.visibility);

  await tables.updateRow({
    databaseId: DB,
    tableId: PROJECTS,
    rowId: projectId,
    data: {
      collaborators: JSON.stringify(collaborators),
      collaboratorEmails: JSON.stringify(collaboratorEmails),
      pendingInvites: JSON.stringify(pendingInvites),
      updatedAt: new Date().toISOString(),
    },
    permissions,
  });

  // Files carry their own permissions — Appwrite rows inherit nothing — so a
  // collaborator who could read the project but not its files would see an
  // empty workspace, which looks exactly like data loss.
  let cursor;
  for (;;) {
    const page = await tables.listRows({
      databaseId: DB,
      tableId: FILES,
      queries: cursorQueries(projectId, cursor),
    });
    for (const file of page.rows) {
      await tables.updateRow({
        databaseId: DB,
        tableId: FILES,
        rowId: file.$id,
        permissions,
      });
    }
    if (page.rows.length < 100) break;
    cursor = page.rows[page.rows.length - 1].$id;
  }

  log(`Granted ${role} on ${projectId} to ${user.$id}`);
  return res.json({ role });
};

/** Appwrite has no map column, so the role maps travel as JSON strings. */
function parseMap(raw) {
  if (typeof raw !== 'string' || raw === '') return {};
  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

/**
 * Must stay in step with `AppwriteProjectRepository._permissionsFor`. The two
 * are the only places that decide access, and a row written with the wrong
 * permissions simply has the wrong access — nothing downstream catches it.
 */
function permissionsFor(ownerId, collaborators, visibility) {
  const permissions = [
    Permission.read(Role.user(ownerId)),
    Permission.update(Role.user(ownerId)),
    Permission.delete(Role.user(ownerId)),
  ];
  for (const [uid, role] of Object.entries(collaborators)) {
    permissions.push(Permission.read(Role.user(uid)));
    if (role === 'editor') permissions.push(Permission.update(Role.user(uid)));
  }
  if (visibility === 'unlisted' || visibility === 'public') {
    permissions.push(Permission.read(Role.any()));
  }
  return permissions;
}

function cursorQueries(projectId, cursor) {
  const queries = [Query.equal('projectId', projectId), Query.limit(100)];
  if (cursor) queries.push(Query.cursorAfter(cursor));
  return queries;
}
