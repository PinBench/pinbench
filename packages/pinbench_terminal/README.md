# pinbench_terminal

The embedded shell terminal: an xterm view, the controller that owns a PTY
process behind it, and the platform split that keeps the web preview honest
about not having one.

```
lib/
  terminal_view.dart        the widget the app places in its bottom pane
  terminal_controller.dart  owns the Terminal and the process behind it
  terminal_state.dart
  pty/                      pty_service.dart picks _io or _web at compile time
```

The app uses two things from here: `TerminalView` (placed by
`layout/leaf_registry.dart`) and `terminalControllerProvider` (the bottom
pane's restart/kill buttons). Everything else is internal.

## `xterm` and `flutter_pty` live here and nowhere else

Neither is a dependency of the app any more. That is the same shape `pinbench_ui`
gives the widget library: a heavyweight dependency that only one screen needs
belongs to that screen's package, so nothing else can grow a use for it by
accident.

`flutter_pty` is a plugin with native code. It still registers correctly as a
transitive dependency — Flutter walks the whole graph — so moving it did not
change what the desktop builds link.

## The web has no shell, and says so

`PtyService.start()` returns null on the web, and the controller writes a
visible line into the terminal saying the embedded terminal is unavailable in
the web preview. That is deliberate: a terminal that silently does nothing
reads as a bug, and the web build is a real target here, not an afterthought.

## Two hand-written providers

`ptyServiceProvider` and `terminalControllerProvider` are plain Riverpod rather
than generated `@Riverpod(keepAlive: true)`, so this package needs no
`build_runner` step — CI's per-package loop runs `pub get`, `analyze` and
`test` and nothing else. Plain providers are keep-alive already, which is what
these want: the controller holds a live process and a stream subscription for
the lifetime of the app.
