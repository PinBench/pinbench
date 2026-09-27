import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

import '../theme/tokens.dart';

/// The rules the app draws between things.
///
/// [FDivider] takes its inset and thickness from a style rather than from
/// constructor arguments, so without this every call site would carry its own
/// style delta. Naming the three kinds instead keeps them consistent and says
/// what each is for.
enum _DividerKind { menu, section, toolbar }

class AppDivider extends StatelessWidget {
  /// Between groups of items in a menu or context menu.
  const AppDivider.menu({super.key}) : _kind = _DividerKind.menu;

  /// Between sections of a panel. Heavier, because it separates regions rather
  /// than neighbouring rows.
  const AppDivider.section({super.key}) : _kind = _DividerKind.section;

  /// Upright, between groups of buttons in a toolbar. Sized by its parent.
  const AppDivider.toolbar({super.key}) : _kind = _DividerKind.toolbar;

  final _DividerKind _kind;

  @override
  Widget build(BuildContext context) => switch (_kind) {
    _DividerKind.menu => const FDivider(
      style: FDividerStyleDelta.delta(
        padding: EdgeInsetsGeometryDelta.value(EdgeInsets.symmetric(vertical: AppSpacing.xs)),
      ),
    ),
    _DividerKind.section => const FDivider(
      style: FDividerStyleDelta.delta(
        padding: EdgeInsetsGeometryDelta.value(EdgeInsets.zero),
        width: 2,
      ),
    ),
    _DividerKind.toolbar => const FDivider(
      axis: Axis.vertical,
      style: FDividerStyleDelta.delta(padding: EdgeInsetsGeometryDelta.value(EdgeInsets.zero)),
    ),
  };
}
