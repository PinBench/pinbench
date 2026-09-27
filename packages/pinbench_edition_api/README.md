# pinbench_edition_api

What an edition of PinBench can add to the app, and the host API it uses to
talk to the app.

```
lib/
  edition.dart      Edition: a ProGateway, a CloudBackend and a SidePanel,
                    each optional
  side_panel.dart   SidePanel: the right-hand pane, plus its settings section
                    and welcome-screen entry
  host.dart         the app as a side panel sees it: the open workspace,
                    problems, the part catalog, and a few actions
```

The app asks `package:pinbench_edition` for an `Edition` at startup. The copy in
this repository returns none, so a build from source is the full local app with
none of these: no sign-in, no cloud projects, no right-hand pane. PinBench's
hosted builds supply their own `pinbench_edition`.

## The host API

A side panel is built outside the app and cannot import it — the app depends
on the panel, not the other way round. So everything it needs is an override
placeholder here, bound by the app in its root scope
(`app/edition_host_bindings.dart`): read `hostWorkspaceProvider`,
`hostProblemsProvider` and `hostPartsProvider` like any provider, and act
through `hostActionsProvider`.

Keep it small. Each member is a promise the app has to keep for every edition,
so add one only when a panel actually needs it.
