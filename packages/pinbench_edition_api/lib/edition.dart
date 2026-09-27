import 'package:pinbench_cloud/cloud_backend.dart';
import 'package:pinbench_pro/pinbench_pro.dart';

import 'side_panel.dart';

/// Everything an edition of PinBench adds to the app.
///
/// The app asks `package:pinbench_edition` for one at startup. The copy in the
/// app repository has none, so a build from source is the full local app —
/// canvas, simulator, editor, every part — with each of these absent. Hosted
/// builds supply their own `pinbench_edition`; nothing else in the app changes
/// between the two.
abstract interface class Edition {
  /// Entitlements. Null keeps the default, [FreeProGateway].
  ProGateway? get gateway;

  /// Accounts and cloud projects. Null keeps the app signed out, with every
  /// cloud feature hidden.
  CloudBackend? get cloud;

  /// A panel in the right-hand pane, with its settings and welcome-screen
  /// entries. Null means the app has no right-hand pane at all.
  SidePanel? get panel;
}
