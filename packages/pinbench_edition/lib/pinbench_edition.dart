import 'package:pinbench_edition_api/edition.dart';

/// The edition this build runs as, or null for none.
///
/// This copy returns null: the app starts signed out, with no cloud features
/// and no right-hand pane, and works entirely on local workspaces. PinBench's
/// hosted builds replace this package; nothing else in the app changes.
Edition? createEdition() => null;
