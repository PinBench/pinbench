/// Opens a URL outside the app.
///
/// Split the way every other platform seam in this codebase is: importing
/// `package:web` unconditionally pulls in `dart:js_interop`, which does not
/// exist on the Dart VM, so it breaks every `flutter test` run — a `kIsWeb`
/// guard cannot save it, because the failure is in the import rather than the
/// call.
library;

export 'open_external_url_io.dart' if (dart.library.js_interop) 'open_external_url_web.dart';
