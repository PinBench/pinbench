# pinbench_pro

The seam between the open-source core of PinBench and the
commercial edition.

**This package is open source (Apache-2.0) and contains no proprietary
code.** It defines an interface (`ProGateway`), a set of gateable
capabilities (`ProFeature`), and `FreeProGateway`, the default a build from
source runs with.

## The rule this package enforces

> **A fork with no proprietary implementation must build, run, and be
> genuinely useful.**

Concretely: local simulation, the canvas, the code editor, `.cdl` save/load,
every component, offline desktop use, and public share links are **never**
gated and must never appear in `ProFeature`. If you are adding a value to
that enum, it must pass one of two tests:

1. **It costs the maintainer money per use** — hosted storage, hosted
   compiles, LLM inference. Gating these is honest cost recovery.
2. **It is inherently multi-user or institutional** — classrooms, SSO,
   org libraries. These have budgets behind them and no hobbyist misses
   them.

Anything else — a component, a keyboard shortcut, an export format, a board
— stays free. Artificial limits on local features are both trivially
patched by forkers and corrosive to the community that makes open source
worth doing in the first place.

## Usage

```dart
import 'package:pinbench_pro/pinbench_pro.dart';

// The open-source build registers nothing — free is the default. A hosted
// build registers its own gateway once, before runApp.

// At a call site:
final access = Pro.instance.check(ProFeature.remoteCompile);
switch (access) {
  case ProAllowed():
    await compiler.compileRemote(sketch);
  case ProDenied(reason: ProDenialReason.quotaExhausted, :final upgradeUrl):
    showQuotaSheet(upgradeUrl);
  case ProDenied(reason: ProDenialReason.notAvailableInThisBuild):
    hideTheFeature();
  case ProDenied(:final reason):
    showUpgradeSheet(reason);
}

// Or, when you only need a bool:
if (Pro.has(ProFeature.aiAssistant)) { ... }
```

## In the app

The app reads access through `proFeatureProvider` (`lib/core/entitlements/`).
A build that offers the hosted, paid features registers its own `ProGateway`
before `runApp`; nothing in the open-source tree depends on it, and the tests
here keep a build without one fully usable.
