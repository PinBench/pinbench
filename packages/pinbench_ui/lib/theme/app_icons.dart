import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Every icon the app draws, named for what it *means* here.
///
/// The same rule as `shared/widgets`: nothing outside this file names an icon
/// library, so swapping one is this file and nothing else.
/// `test/architecture/ui_library_boundary_test.dart` enforces that.
///
/// Names describe the role, not the glyph — [delete] rather than `trash2`,
/// [stop] rather than `square`. A glyph name only survives a library swap by
/// luck; a role name survives it by construction, and it is also what the call
/// site actually meant. Where two roles share a glyph today ([code] and
/// [fileCode], [locked] and [privateLink]) they are still separate entries, so
/// they can diverge later without hunting through call sites.
abstract final class AppIcons {
  // ── Files and folders ─────────────────────────────────────────────────────

  static const file = LucideIcons.file;
  static const fileText = LucideIcons.fileText;
  static const fileCode = LucideIcons.fileCode;
  static const fileJson = LucideIcons.braces;
  static const fileConfig = LucideIcons.settings;

  /// An Arduino sketch (`.ino`).
  static const sketch = LucideIcons.microchip;

  /// A circuit document (`.cdl`).
  static const circuit = LucideIcons.workflow;

  static const folder = LucideIcons.folder;
  static const folderOpen = LucideIcons.folderOpen;
  static const newFile = LucideIcons.filePlus;
  static const newFolder = LucideIcons.folderPlus;

  // ── Editing ───────────────────────────────────────────────────────────────

  static const copy = LucideIcons.copy;
  static const paste = LucideIcons.clipboardPaste;
  static const delete = LucideIcons.trash2;
  static const rename = LucideIcons.squarePen;
  static const undo = LucideIcons.undo2;
  static const redo = LucideIcons.redo2;
  static const clear = LucideIcons.eraser;
  static const add = LucideIcons.plus;
  static const remove = LucideIcons.minus;
  static const close = LucideIcons.x;

  // ── Canvas ────────────────────────────────────────────────────────────────

  static const rotateLeft = LucideIcons.rotateCcw;
  static const rotateRight = LucideIcons.rotateCw;
  static const flipHorizontal = LucideIcons.flipHorizontal2;
  static const flipVertical = LucideIcons.flipVertical2;
  static const bringForward = LucideIcons.arrowUp;
  static const sendBackward = LucideIcons.arrowDown;
  static const fitToScreen = LucideIcons.scaling;
  static const gridShown = LucideIcons.grid2x2;
  static const gridHidden = LucideIcons.grid2x2X;
  static const nothingSelected = LucideIcons.mousePointerClick;
  static const board = LucideIcons.circuitBoard;
  static const parts = LucideIcons.boxes;
  static const properties = LucideIcons.slidersHorizontal;

  // ── Running a sketch ──────────────────────────────────────────────────────

  static const run = LucideIcons.play;
  static const pause = LucideIcons.pause;
  static const stop = LucideIcons.square;
  static const upload = LucideIcons.rocket;
  static const refresh = LucideIcons.refreshCw;

  /// An action that is unavailable, as opposed to one that failed.
  static const blocked = LucideIcons.ban;

  // ── Panels and chrome ─────────────────────────────────────────────────────

  static const panelLeft = LucideIcons.panelLeft;
  static const panelBottom = LucideIcons.panelBottom;
  static const panelRight = LucideIcons.panelRight;
  static const splitEditor = LucideIcons.splitSquareHorizontal;
  static const terminal = LucideIcons.terminal;
  static const serialPlotter = LucideIcons.chartLine;
  static const serialMonitor = LucideIcons.usb;
  static const memory = LucideIcons.memoryStick;
  static const problems = LucideIcons.bug;
  static const history = LucideIcons.history;
  static const filter = LucideIcons.filter;
  static const templates = LucideIcons.layoutGrid;
  static const recent = LucideIcons.inbox;
  static const blankProject = LucideIcons.squarePlus;
  static const expanded = LucideIcons.chevronDown;
  static const collapsed = LucideIcons.chevronRight;

  // ── Status ────────────────────────────────────────────────────────────────

  static const error = LucideIcons.circleAlert;
  static const warning = LucideIcons.triangleAlert;
  static const info = LucideIcons.info;
  static const success = LucideIcons.circleCheck;
  static const hint = LucideIcons.lightbulb;

  // ── Cloud and sharing ─────────────────────────────────────────────────────

  static const cloud = LucideIcons.cloud;
  static const cloudSynced = LucideIcons.cloudCheck;
  static const link = LucideIcons.link;
  static const publicLink = LucideIcons.globe;

  /// A share or embed that is locked behind a paid feature.
  static const locked = LucideIcons.lock;
  static const privateLink = LucideIcons.radio;
  static const preview = LucideIcons.eye;
  static const code = LucideIcons.code;

  // ── Account, app chrome ───────────────────────────────────────────────────

  static const home = LucideIcons.house;
  static const settings = LucideIcons.settings2;
  static const account = LucideIcons.circleUser;
  static const user = LucideIcons.user;
  static const signIn = LucideIcons.logIn;
  static const feedback = LucideIcons.messageSquare;
  static const exportImage = LucideIcons.image;
  static const themeLight = LucideIcons.sun;
  static const themeDark = LucideIcons.moon;

  /// A newer release is available. Deliberately the download arrow rather
  /// than a badge or a bell: on Linux it genuinely is a download, and on
  /// macOS/Windows the update has to come down before it can install.
  static const update = LucideIcons.arrowDownToLine;
  static const releaseNotes = LucideIcons.scrollText;

  /// Reads one icon so the library's module is resolved here, on a shallow
  /// stack, before anything builds a widget.
  ///
  /// `lucide_icons_flutter` is one class holding ~28,000 static fields across
  /// 125,000 lines. Dart's web *debug* compiler resolves a module the first
  /// time something inside it is read, and when that first read happens deep
  /// inside a widget build the loader recurses past the stack limit: the app
  /// comes up as a red "Stack Overflow" screen with every icon-bearing widget
  /// failing to build.
  ///
  /// Called from `main`. Nothing will tell you it mattered — dart2js and AOT
  /// link the library ahead of time, so release web, native and the whole test
  /// suite pass without it while `flutter run -d chrome` is unusable.
  static void resolveModule() => board.codePoint;
}
