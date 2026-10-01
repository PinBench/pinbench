import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/ui/app_toast.dart';

import '../core/parts/part_registry_provider.dart';
import '../core/telemetry/telemetry_providers.dart';
import '../features/workspace/providers/workspace_files_provider.dart';
import '../features/workspace/providers/workspace_loading_provider.dart';
import '../features/workspace/services/part_link.dart';
import '../features/workspace/services/share_link.dart';
import '../features/workspace/services/template_service.dart';
import '../layout/controllers/app_layout_controller.dart';
import 'embed_page.dart';
import 'home_page.dart';

part 'router.g.dart';

/// Routes shared by every window, on every platform.
///
/// The app is a single-page IDE, so routing is intentionally thin: `/` is the
/// welcome screen, `/t/<template>` deep-links a bundled example template and
/// `/part/<name>` opens an empty circuit with one part on it.
/// On the web, navigating between them also drives the browser URL and
/// back/forward history; native desktop (one [GoRouter] per
/// `multiview_desktop` window, no URL bar) uses the same route definitions
/// for in-app navigation, so both platforms share one code path.
GoRouter createAppRouter() => GoRouter(routes: $appRoutes);

/// Every route here renders the same thing: the IDE shell. `/` shows it with
/// the welcome screen up, `/t/<template>` and `/p/<id>` show it with a
/// workspace opening into it — the route is which document is open, not which
/// screen you are looking at.
///
/// So none of them animate. A page transition between two identical shells
/// slides the whole window against itself for no information, and while it
/// runs there are *two* live IDE trees — two Layouts, two PlatViews, two
/// canvases — being laid out and painted every frame of it. What the user
/// should see is the workspace appearing, which the loading overlay already
/// covers.

/// Holds the IDE mounted across every navigation.
///
/// The routes under here do not render screens — they render *nothing*, and
/// exist to run one side effect each: close the workspace, open this template,
/// download that project. The screen is this shell, and it is the same screen
/// before and after. Without it, going from `/` to `/t/blink` built a second
/// copy of the entire IDE — a second `Layout`, `PlatView` and canvas — and
/// threw the first away, to end up looking identical.
///
/// The exception is an embed (`/p/<id>?embed=1` or `/t/<template>?embed=1`),
/// which is a chrome-less view of a circuit rather than the IDE. That one *is*
/// the page, so the shell steps out of its way.
@TypedShellRoute<WorkspaceShellRoute>(
  routes: [
    TypedGoRoute<HomeRoute>(path: '/'),
    TypedGoRoute<TemplateRoute>(path: '/t/:template'),
    TypedGoRoute<PartRoute>(path: '/part/:part'),
    TypedGoRoute<ProjectRoute>(path: '/p/:projectId'),
  ],
)
class const WorkspaceShellRoute() extends ShellRouteData {
  @override
  Widget builder(BuildContext context, GoRouterState state, Widget navigator) =>
      ShareLinkOptions.fromQuery(state.uri.queryParameters).embed
      ? navigator
      : _WorkspaceShell(navigator: navigator);
}

class const _WorkspaceShell({required final Widget navigator}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const HomePage(),
      // Offstage, because the routes below this shell draw nothing: they are
      // side effects with a URL. They still have to be *mounted* — that is
      // what runs them, and what lets `initState` fire again when the user
      // comes back to `/`.
      Offstage(child: navigator),
    ],
  );
}

class const HomeRoute() extends GoRouteData with $HomeRoute {
  @override
  Widget build(BuildContext context, GoRouterState state) => const _HomeView();

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      const NoTransitionPage(child: _HomeView());
}

// Sibling (not child) of HomeRoute so navigating between `/` and `/t/...`
// replaces the page — this rebuilds `_HomeView` on browser-back, closing the
// workspace so the welcome screen matches the URL.
class const TemplateRoute({required final String template})
    extends GoRouteData
    with $TemplateRoute {
  // `?embed=1` works here as on a project: the circuit and a Run button, for
  // putting an example in an article. See [ProjectRoute].
  @override
  Widget build(BuildContext context, GoRouterState state) => _TemplateView(
    template: template,
    embed: ShareLinkOptions.fromQuery(state.uri.queryParameters).embed,
  );

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      NoTransitionPage(child: build(context, state));
}

// `/part/<name>` — a fresh workspace with that part on the canvas. What the
// website's part pages link to; see [partForLink] for which names it takes.
class const PartRoute({required final String part}) extends GoRouteData with $PartRoute {
  @override
  Widget build(BuildContext context, GoRouterState state) => _PartView(part: part);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      NoTransitionPage(child: build(context, state));
}

// `/p/<projectId>` — opens a cloud project by id, so the browser URL (and
// back/forward/refresh) always reflects which project is open.
class const ProjectRoute({required final String projectId}) extends GoRouteData with $ProjectRoute {
  // `?embed=1` renders the chrome-less view meant to sit in an <iframe> on
  // someone else's page, and `?live=1` subscribes it to the author's edits.
  // Query parameters rather than separate routes, so an embed URL is the share
  // URL plus a flag — the same link, one way or the other. Parsed by
  // [ShareLinkOptions], which is also what writes them into an embed snippet.
  @override
  Widget build(BuildContext context, GoRouterState state) {
    final options = ShareLinkOptions.fromQuery(state.uri.queryParameters);
    return _ProjectView(projectId: projectId, embed: options.embed, live: options.live);
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      NoTransitionPage(child: build(context, state));
}

/// `/` — shows the welcome screen. Entering this route (including via browser
/// back) closes any open workspace so the view matches the URL.
class const _HomeView() extends ConsumerStatefulWidget {
  @override
  ConsumerState<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<_HomeView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(analyticsProvider).logScreen('home');
        ref.read(workspaceFilesProvider.notifier).closeFolder();
      }
    });
  }

  /// Nothing: the IDE is the shell above this, which stays mounted. See
  /// [WorkspaceShellRoute].
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// `/t/<template>` — opens the named template as a temporary workspace.
class const _TemplateView({required final String template, final bool embed = false})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<_TemplateView> createState() => _TemplateViewState();
}

class _TemplateViewState extends ConsumerState<_TemplateView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(analyticsProvider).logScreen(widget.embed ? 'template_embed' : 'template');
        // Use the container, not `ref`/`context` — openTemplateWorkspace closes
        // the welcome tab as part of its own work, which can unmount this very
        // widget (and invalidate `ref`) before the function returns. The
        // container is scoped to the whole app, so it stays valid regardless.
        unawaited(
          openTemplateWorkspace(ProviderScope.containerOf(context, listen: false), widget.template),
        );
      }
    });
  }

  // The embed *is* the page, as for a project: [WorkspaceShellRoute] has
  // already stepped aside for it.
  @override
  Widget build(BuildContext context) => widget.embed ? const EmbedPage() : const HomePage();
}

/// Creates a temporary workspace from [template] and dismisses the welcome
/// screen. Called from [TemplateRoute]'s `_TemplateView` on every platform.
///
/// Takes a [ProviderContainer] rather than a `WidgetRef` — this function
/// closes the welcome tab partway through (see [AppLayoutController.closeWelcome]),
/// which can unmount the widget that triggered the call before this
/// `Future` resolves. A `WidgetRef` throws "used after unmount" once that
/// happens; a container read stays valid for the app's whole lifetime, so
/// every step here — including the `finally` that clears the loading
/// spinner — keeps working even after the original caller is gone.
Future<void> openTemplateWorkspace(ProviderContainer container, String template) async {
  container.read(analyticsProvider).templateOpened(template);
  // Show the loading overlay from the moment the template is picked, covering
  // the asset-loading phase too (openWorkspace's own begin/end nests under this).
  container.read(workspaceLoadingProvider.notifier).begin();
  try {
    final path = await container
        .read(templateServiceProvider)
        .createTempWorkspaceFromTemplate(template);
    await container.read(workspaceFilesProvider.notifier).openWorkspace(path, isTemporary: true);
    container.read(appLayoutControllerProvider).closeWelcome();
  } finally {
    container.read(workspaceLoadingProvider.notifier).end();
  }
}

/// `/part/<name>` — opens a temporary workspace holding the named part.
class const _PartView({required final String part}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_PartView> createState() => _PartViewState();
}

class _PartViewState extends ConsumerState<_PartView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(analyticsProvider).logScreen('part');
        // The container, not `ref`, for the same reason as [_TemplateView].
        unawaited(
          openPartWorkspace(
            ProviderScope.containerOf(context, listen: false),
            widget.part,
            context: context,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => const HomePage();
}

/// Creates a temporary workspace with the part [name] names on its canvas,
/// and dismisses the welcome screen. A name that is no part still opens a
/// workspace, an empty one, and says why: the link was followed to build
/// something, and a blank canvas is closer to that than the welcome screen.
///
/// Takes a [ProviderContainer] for the reason [openTemplateWorkspace] does;
/// [context] is only for the toast, guarded by `context.mounted`.
Future<void> openPartWorkspace(
  ProviderContainer container,
  String name, {
  required BuildContext context,
}) async {
  container.read(workspaceLoadingProvider.notifier).begin();
  PartModel? part;
  try {
    final catalog = await container.read(partRegistryProvider.future);
    part = partForLink(catalog, name);
    final templates = container.read(templateServiceProvider);
    final path = part == null
        ? await templates.createBlankWorkspace()
        : await templates.createWorkspaceWithPart(part);
    await container.read(workspaceFilesProvider.notifier).openWorkspace(path, isTemporary: true);
    container.read(appLayoutControllerProvider).closeWelcome();
  } finally {
    container.read(workspaceLoadingProvider.notifier).end();
  }
  if (part != null || !context.mounted) return;
  showAppToast(
    context,
    title: AppStrings.partLinkUnknownTitle,
    message: AppStrings.partLinkUnknownMessage(name),
    isError: true,
  );
}

/// `/p/<projectId>` — downloads and opens the named cloud project.
class const _ProjectView({
  required final String projectId,
  final bool embed = false,
  final bool live = false,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ProjectView> createState() => _ProjectViewState();
}

class _ProjectViewState extends ConsumerState<_ProjectView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(analyticsProvider).logScreen(widget.embed ? 'project_embed' : 'project');
        unawaited(
          openCloudProjectWorkspace(
            ProviderScope.containerOf(context, listen: false),
            widget.projectId,
            context: context,
            live: widget.live,
          ),
        );
      }
    });
  }

  // The embed *is* the page — see [WorkspaceShellRoute], which hands the
  // whole screen over for it. Everything else draws nothing.
  @override
  Widget build(BuildContext context) => widget.embed ? const EmbedPage() : const SizedBox.shrink();
}

/// Opens cloud project [projectId] into a local workspace and dismisses the
/// welcome screen. Called from [ProjectRoute]'s `_ProjectView` on every
/// platform.
///
/// Takes a [ProviderContainer] rather than a `WidgetRef` for the same reason
/// as [openTemplateWorkspace] — `closeWelcome()` can unmount the caller
/// mid-flight. [context] is only used for the failure-toast fallback (a real
/// `BuildContext` with an `Overlay` ancestor is unavoidable there), guarded
/// by `context.mounted` since it stays widget-bound.
Future<void> openCloudProjectWorkspace(
  ProviderContainer container,
  String projectId, {
  required BuildContext context,
  bool live = false,
}) async {
  final opened = await container
      .read(workspaceFilesProvider.notifier)
      .openCloudProject(projectId, live: live);
  if (opened) {
    container.read(appLayoutControllerProvider).closeWelcome();
    return;
  }
  if (!context.mounted) return;
  showAppToast(
    context,
    title: AppStrings.cloudProjectOpenFailedTitle,
    message: AppStrings.cloudProjectOpenFailedMessage,
    isError: true,
  );
}
