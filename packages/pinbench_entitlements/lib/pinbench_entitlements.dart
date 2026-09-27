/// Entitlement and feature-gating seam for PinBench.
///
/// This package is the *boundary* between the open-source core and the
/// commercial edition. It is itself fully open source (Apache-2.0) and
/// contains no proprietary logic — only the interface that a proprietary
/// implementation may satisfy, plus a free-tier stub that the open-source
/// build uses.
///
/// The design goal: **a fork with no proprietary package must build, run,
/// and be genuinely useful.** Everything gated here is either something
/// that costs the maintainer money to run (cloud storage, hosted compiles)
/// or something that only makes sense with a hosted backend. Local
/// simulation, the canvas, the editor, and all core components are never
/// gated and must never appear in [ProFeature].
///
/// ## How the swap works
///
/// The app calls [Pro.instance] and never constructs an implementation
/// directly. The open-source build registers nothing, so the default,
/// [FreeProGateway], is in force. A build that offers the hosted, paid
/// features calls [Pro.register] once at startup with its own gateway. No
/// `#ifdef`, no dead proprietary code in the public tree.
library;

import 'package:meta/meta.dart';

/// A capability that may be restricted by tier.
///
/// Every value here must pass the gating test:
/// it costs real money to operate, or it is inherently multi-user. If a
/// feature is neither, it belongs in the free core, not in this enum.
enum ProFeature {
  /// Storing projects in the hosted cloud. Costs storage + reads. Free tier
  /// gets a small quota; see [ProLimits.cloudProjects].
  cloudProjects,

  /// Per-save version history for cloud projects.
  cloudVersionHistory,

  /// Compiling sketches through the hosted compile service. Costs compute per
  /// build. Free tier is rate-limited and de-prioritised.
  remoteCompile,

  /// Priority (non-queued) lane on the hosted compile service.
  priorityCompile,

  /// Private share links and `<iframe>` embeds of a running simulation.
  /// Public share links are free — they are the growth loop.
  privateShareLinks,

  /// The circuit assistant. Metered; costs inference spend per call.
  aiAssistant,

  /// Classroom: rosters, assignment distribution, submission collection.
  classroom,

  /// Headless assertion harness used to auto-grade student circuits.
  autoGrading,

  /// Organisation-scoped private libraries of custom components.
  orgComponentLibrary,

  /// SSO / SAML sign-in for institutions.
  ssoSignIn,
}

/// Subscription tier. Ordered: a higher [rank] includes everything below it.
enum ProTier {
  /// No subscription. The default, and a real product in its own right.
  free(0, 'Free'),

  /// Individual paid tier.
  pro(1, 'Pro'),

  /// Organisation tier: seats, shared libraries, SSO.
  team(2, 'Team'),

  /// Institutional tier. Same rank as [team]; differs in pricing, not access.
  education(2, 'Education');

  const ProTier(this.rank, this.label);

  /// Ordering only. A higher rank includes everything below it; never gate on
  /// this directly, use [ProGateway.check] so quotas are accounted for too.
  final int rank;

  /// Human-readable name for UI.
  final String label;

  /// Whether this tier is paid for. `false` only for [free].
  bool get isPaid => rank > 0;
}

/// Numeric quotas that vary by tier. Unlimited is represented by `null`,
/// never by a sentinel like `-1` or `9999`.
@immutable
class ProLimits {
  /// Creates a set of quotas. Any omitted value means unlimited.
  const ProLimits({
    this.cloudProjects,
    this.remoteCompilesPerDay,
    this.aiRequestsPerMonth,
    this.collaboratorsPerProject,
  });

  /// The quotas an unauthenticated or free-tier user gets.
  ///
  /// These numbers are deliberately generous enough that the free tier is a
  /// real product, not a demo. Revisit them against actual infrastructure
  /// cost, not against conversion targets.
  static const free = ProLimits(
    cloudProjects: 5,
    remoteCompilesPerDay: 30,
    aiRequestsPerMonth: 0,
    collaboratorsPerProject: 1,
  );

  /// No quotas at all. Used by paid tiers.
  static const unlimited = ProLimits();

  /// Maximum projects stored in the hosted cloud. `null` = unlimited.
  final int? cloudProjects;

  /// Hosted compiles per rolling 24h. `null` = unlimited.
  final int? remoteCompilesPerDay;

  /// AI assistant requests per billing month. `null` = unlimited.
  final int? aiRequestsPerMonth;

  /// Collaborators invitable to a single cloud project, excluding the
  /// owner. `null` = unlimited.
  final int? collaboratorsPerProject;

  /// Whether [used] is still within [limit]. A `null` limit never blocks.
  static bool withinLimit(int used, int? limit) => limit == null || used < limit;
}

/// Why a feature was denied — lets the UI say something useful instead of a
/// generic "upgrade" wall.
enum ProDenialReason {
  /// The tier does not include this feature at all.
  notInTier,

  /// The tier includes it, but a quota is exhausted (e.g. daily compiles).
  quotaExhausted,

  /// Requires an account and the user is signed out.
  signInRequired,

  /// This build has no commercial implementation registered — i.e. a build
  /// from source. There is no checkout page to point at.
  notAvailableInThisBuild,
}

/// The result of an entitlement check.
@immutable
sealed class ProAccess {
  const ProAccess();

  /// Convenience: `true` only for [ProAllowed].
  bool get isAllowed => this is ProAllowed;
}

/// The caller may proceed.
@immutable
final class ProAllowed extends ProAccess {
  /// Creates an allow result.
  const ProAllowed();
}

/// The caller may not proceed. [reason] should drive the UI copy.
@immutable
final class ProDenied extends ProAccess {
  /// Creates a denial carrying [reason], and optionally copy and a link.
  const ProDenied(this.reason, {this.message, this.upgradeUrl});

  /// Why access was denied. Should drive the wording the user sees.
  final ProDenialReason reason;

  /// Human-readable explanation, if the implementation has a better one
  /// than the caller could generate from [reason] alone.
  final String? message;

  /// Where to send a user who wants to unlock this. `null` for
  /// [ProDenialReason.notAvailableInThisBuild].
  final String? upgradeUrl;
}

/// The interface a commercial implementation satisfies.
///
/// Implementations must be cheap to call — the UI will hit [check] on every
/// rebuild. Do no I/O here; resolve entitlements asynchronously elsewhere
/// and cache them.
abstract interface class ProGateway {
  /// The current tier. Drives labelling; do not use it for gating —
  /// use [check], which also accounts for quotas.
  ProTier get tier;

  /// Quotas in force for the current tier.
  ProLimits get limits;

  /// Whether [feature] may be used right now.
  ProAccess check(ProFeature feature);

  /// Emits whenever [tier] or [limits] change (sign-in, purchase, refresh)
  /// so the UI can rebuild.
  Stream<void> get changes;
}

/// The free-tier implementation shipped by the open-source build.
///
/// Everything that costs the maintainer money is denied with
/// [ProDenialReason.notAvailableInThisBuild] — because a build from source
/// has no maintainer-run backend to charge for.
final class FreeProGateway implements ProGateway {
  /// Creates the free-tier gateway.
  const FreeProGateway();

  @override
  ProTier get tier => ProTier.free;

  @override
  ProLimits get limits => ProLimits.free;

  @override
  ProAccess check(ProFeature feature) => const ProDenied(
    ProDenialReason.notAvailableInThisBuild,
    message:
        'This feature is part of the hosted commercial edition. '
        'A build from source has no backend to provide it.',
  );

  @override
  Stream<void> get changes => const Stream<void>.empty();
}

/// Global access point for the registered [ProGateway].
///
/// Deliberately a tiny service locator rather than a Riverpod provider: this
/// package must stay Flutter-free so it can be used from isolates, CLI
/// tools, and tests. The app wraps [instance] in a provider of its own.
abstract final class Pro {
  static ProGateway _gateway = const FreeProGateway();
  static bool _registered = false;

  /// The active gateway. Defaults to [FreeProGateway] when nothing was
  /// registered, so the app is always safe to run.
  static ProGateway get instance => _gateway;

  /// Install the gateway. Call once, from `main()`, before `runApp`.
  ///
  /// Throws [StateError] on a second call — a silent double-register would
  /// mean two sources of truth for entitlements, which is exactly the class
  /// of bug that ends with a paying user being denied a feature.
  static void register(ProGateway gateway) {
    if (_registered) {
      throw StateError(
        'Pro.register() called twice. Entitlements must have a single '
        'source of truth; register exactly once from main().',
      );
    }
    _gateway = gateway;
    _registered = true;
  }

  /// Reset to the default gateway. Tests only.
  @visibleForTesting
  static void reset() {
    _gateway = const FreeProGateway();
    _registered = false;
  }

  /// Shorthand for `Pro.instance.check(feature).isAllowed`.
  static bool has(ProFeature feature) => _gateway.check(feature).isAllowed;
}
