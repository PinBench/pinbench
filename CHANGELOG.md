# Changelog

Notable changes to PinBench.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the
project uses [semantic versioning](https://semver.org/) once releases begin.

**This file starts here.** The project has no release tags yet, so what follows
is the state of `Unreleased` rather than a reconstruction of everything that led
to it. Anything older is summarised at the end.

## How entries are written

- **Added / Changed / Fixed / Removed** are what a *user* would notice.
- **Internal** is everything else, kept short. A reader scanning for whether to
  upgrade does not need the refactors.
- One line per change, in the user's words, not the commit's. "The web preview
  no longer opens the browser's menu over the app's" beats
  "fix(web): stop the browser's menu opening over ours".

---

## [Unreleased]

### Added

- **You can see the current.** While a simulation runs, every wire carries
  moving dots showing which way the current flows and, by how fast and how
  brightly they travel, how much of it there is — from a microamp trickle to a
  hundred milliamps. A dim LED and a bright one now look different on the wire
  as well as on the part.
- **An OLED display that really displays.** A 0.96" SSD1306 module on the I²C
  bus, showing what the sketch actually draws: the emulator's I²C hardware is
  wired up, the display decodes the protocol `Adafruit_SSD1306` and `U8g2`
  speak, and the panel renders its 128 × 64 pixels. Wire it to `A4`/`A5` — a
  display on the wrong pins stays dark, as it would on a desk. New **OLED**
  template, and compiling your own display sketches locally needs
  `arduino-cli lib install "Adafruit SSD1306"`.
- **Parts without Dart.** A part can be described entirely by data — an SVG
  body, pins, properties and declarative behaviour — in the `.pdl` format. See
  [`PDL.md`](packages/pinbench_pdl/doc/PDL.md).
- **Cloud projects and sharing** in the hosted builds. Save projects to the
  cloud, share a view link, invite collaborators by email, and open a share link
  as a detached read-only copy.
- **Embeddable circuits** via `?embed=1` — a chrome-less view for an `<iframe>`,
  optionally live.
- **Signed desktop downloads that update themselves.** macOS and Windows
  install updates in place; Linux says a new version exists and links to it.
  Settings has a version, a "check now" button, and a switch to stop the app
  checking on its own. Builds are pay-what-you-want with a $10 minimum, and the
  source stays free and buildable.
- **Screen-reader names for icon-only buttons.**
- **The build from this repository is the full local app.** Accounts, cloud
  projects, sharing and the circuit assistant belong to the hosted builds and
  are absent from it.

### Changed

- **The breadboard is drawn landscape with real anatomy** — a 0.3" centre notch,
  centred row numbering, and power rails on the connection lattice, so DIP parts
  and buttons land where they do on a real board.
- **Parts snap on every grid cell**, with Figma-style alignment guides, and a
  part's legs align to another part's pins so wires run straight.
- **Moving a wire's end keeps the wire** — its identity, its selection and its
  handles — instead of creating a new one.
- **The interface was rebuilt on a single widget kit** with a design-token layer
  and a palette retuned to clear WCAG AA. Several pairs were below it before;
  the worst made active toolbar buttons nearly unreadable.

### Fixed

- The web preview no longer opens the browser's context menu over the app's.
- The web loader matches the app's colours instead of flashing black.
- The window no longer shrinks into a broken title bar.
- Global keyboard shortcuts keep working when focus leaves the app.
- A resistor's value now reaches SPICE, and the netlist stops identifying parts
  by their display name.

### Internal

- The codebase is now an app plus standalone packages — `pinbench_parts`,
  `pinbench_pdl`, `pinbench_cdl`, `pinbench_sim`, `pinbench_ui`,
  `pinbench_terminal`, `pinbench_cloud`, `pinbench_pro` and the edition seam
  (`pinbench_edition_api`, `pinbench_edition`) — none able to import the app.
  Each has a README.
- Features no longer reach into each other or up into the app chrome; where they
  need something another owns, it goes through a port bound in `lib/app/`. The
  layering rules that used to grandfather those imports are now empty.
- The analyzer plugin was unpinned, and CI now fails when a plugin does not
  load — it used to print a stack trace and exit 0.

---

## Before this file

Roughly a year of work, summarised: the canvas and its part painters, the AVR +
SPICE simulation engine, the `.cdl` save format, the code editor, the embedded
terminal, templates, telemetry, the web build and its remote compile service.
That history predates this repository, which starts from a single snapshot of
it.
