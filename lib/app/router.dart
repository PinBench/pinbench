import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/ui/app_toast.dart';

import '../core/telemetry/telemetry_providers.dart';
import '../features/workspace/providers/workspace_files_provider.dart';
import '../features/workspace/providers/workspace_loading_provider.dart';
import '../features/workspace/services/share_link.dart';
import '../features/workspace/services/template_service.dart';
import '../layout/controllers/app_layout_controller.dart';
import 'embed_page.dart';
import 'home_page.dart';

part 'router.g.dart';

/// Routes shared by every window, on every platform.
///
/// The app is a single-page IDE, so routing is intentionally thin: `/` is the
/// welcome screen and `/t/<template>` deep-links a bundled example template.
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
/// The exception is an embedded project (`/p/<id>?embed=1`), which is a
/// chrome-less view of a circuit rather than the IDE. That one *is* the page,
/// so the shell steps out of its way.
@TypedShellRoute<WorkspaceShellRoute>(
  routes: [
    TypedGoRoute<HomeRoute>(path: '/'),
    TypedGoRoute<TemplateRoute>(path: '/t/:template'),
    TypedGoRoute<ProjectRoute>(path: '/p/:projectId'),
  ],
)
class WorkspaceShellRoute extends ShellRouteData {
  const WorkspaceShellRoute();

  @override
  Widget builder(BuildContext context, GoRouterState state, Widget navigator) =>
      ShareLinkOptions.fromQuery(state.uri.queryParameters).embed
      ? navigator
      : _WorkspaceShell(navigator: navigator);
}

class _WorkspaceShell extends StatelessWidget {
  const _WorkspaceShell({required this.navigator});

  final Widget navigator;

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

class HomeRoute extends GoRouteData with $HomeRoute {
  const HomeRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) => const _HomeView();

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      const NoTransitionPage(child: _HomeView());
}

// Sibling (not child) of HomeRoute so navigating between `/` and `/t/...`
// replaces the page — this rebuilds `_HomeView` on browser-back, closing the
// workspace so the welcome screen matches the URL.
class TemplateRoute extends GoRouteData with $TemplateRoute {
  const TemplateRoute({required this.template});

  final String template;

  @override
  Widget build(BuildContext context, GoRouterState state) => _TemplateView(template: template);

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      NoTransitionPage(child: build(context, state));
}

// `/p/<projectId>` — opens a cloud project by id, so the browser URL (and
// back/forward/refresh) always reflects which project is open.
class ProjectRoute extends GoRouteData with $ProjectRoute {
  const ProjectRoute({required this.projectId});

  final String projectId;

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
class _HomeView extends ConsumerStatefulWidget {
  const _HomeView();

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
class _TemplateView extends ConsumerStatefulWidget {
  const _TemplateView({required this.template});

  final String template;

  @override
  ConsumerState<_TemplateView> createState() => _TemplateViewState();
}

class _TemplateViewState extends ConsumerState<_TemplateView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(analyticsProvider).logScreen('template');
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

  @override
  Widget build(BuildContext context) => const HomePage();
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

/// `/p/<projectId>` — downloads and opens the named cloud project.
class _ProjectView extends ConsumerStatefulWidget {
  const _ProjectView({required this.projectId, this.embed = false, this.live = false});

  final String projectId;
  final bool embed;
  final bool live;

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
