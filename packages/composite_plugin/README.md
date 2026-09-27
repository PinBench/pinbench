# composite_plugin

Composite analyzer plugin scaffold. **One** `plugins:` entry in
`analysis_options.yaml` should point at this package; use key `composite`
to match `Plugin.name`.

Copy Saropa settings (`version`, `diagnostics`, `rule_packs`, …) under
that block. See `doc/guides/composite_analyzer_plugin.md` in saropa_lints.
