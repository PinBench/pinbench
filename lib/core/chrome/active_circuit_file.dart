import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The `.cdl` file the canvas is currently showing, or null when none is.
///
/// This lived on `CanvasCodeSyncService` as `activeCdlPath`, which meant
/// anything that wanted to know *which circuit is on screen* had to reach for
/// the sync machinery to ask — the canvas toolbar's View Code button did
/// exactly that, and it is the reason `canvas` imported `workspace` at all.
///
/// It sits beside `AppTabs` because it answers the same kind of question: not
/// how the file is kept in sync, but what the user is looking at. The sync
/// service still owns *when* it changes, and publishes it here.
final activeCircuitFileProvider = NotifierProvider<ActiveCircuitFile, String?>(
  ActiveCircuitFile.new,
);

class ActiveCircuitFile extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? filePath) => state = filePath;
}
