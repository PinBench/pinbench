# pinbench_cloud

Who the user is, and where their projects live — as interfaces. There is no
backend in this package.

```
lib/
  cloud_backend.dart          CloudBackend: what a build's backend provides
  auth/auth_service.dart      the interface, plus DisabledAuthService
  auth/auth_user.dart
  project_repository.dart     the interface
  project_model.dart          Project, ProjectFile, RecentProject, …
  cloud_log.dart              where cloud diagnostics go
```

## Where the backend comes from

The app gets a `CloudBackend`, or none, from the build's edition at startup
(see `package:pinbench_edition_api`). A build from source has no edition, so it
runs fully local: sign-in, cloud projects and sharing stay hidden, and
`authServiceProvider` is a `DisabledAuthService`.

Everything above `AuthService` and `ProjectRepository` talks to those and
nothing else, so serving a backend is an implementation of those interfaces
plus a `CloudBackend` that hands them out — never a change spread through the
app.

## What is *not* here

The Riverpod providers — `authServiceProvider`, `authStateProvider`,
`projectRepositoryProvider`, `cloudRecentProjectsProvider` — stay in the app
under `lib/core/`. Same split as `pinbench_sim`: the
interfaces stand alone, the wiring that makes them reactive belongs to the app
that is reactive.

It also means this package needs no `build_runner`, which matters because CI's
per-package loop runs `pub get`, `analyze` and `test` and nothing else.

## Logging

`CloudLog` is a port with a static sink, installed by `app/bootstrap.dart`
(`installCloudLogSink`). With no sink, errors still reach
`FlutterError.reportError` — and therefore Crashlytics — while info and warning
lines are dropped.

This is the second copy of a shape `pinbench_sim`'s `SimLog` already has. Two is
tolerable and three is not: if a third package needs it, the answer is a shared
`pinbench_log`, not another of these.
