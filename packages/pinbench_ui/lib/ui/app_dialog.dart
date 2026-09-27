import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

import '../theme/tokens.dart';

/// Opens [builder]'s dialog and resolves to whatever it pops.
///
/// The app's own entry point for modals, so features never name the widget
/// library's `showFDialog`. Dismissing (Escape, or a tap outside) resolves to
/// null, as it does underneath.
Future<T?> showAppDialog<T>(BuildContext context, {required WidgetBuilder builder}) =>
    showFDialog<T>(context: context, builder: (context, _, _) => builder(context));

/// The title / message / actions layout every dialog in the app uses.
///
/// forui's dialog is a surface and a set of text styles — the arrangement is
/// the caller's. Owning it once here keeps every dialog identical instead of
/// each one composing its own column.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.message,
    this.child,
    this.actions = const [],
    this.actionsAxis = Axis.horizontal,
  });

  final String title;
  final String? message;

  /// Content between the message and the actions — a text field, a list.
  final Widget? child;

  final List<Widget> actions;

  /// Stack the actions instead of putting them in a row. Use it when there are
  /// more than two, or when the labels are long enough to overflow a row.
  final Axis actionsAxis;

  @override
  Widget build(BuildContext context) => FDialog(
    builder: (context, style) => Padding(
      padding: AppInsets.dialog,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: style.titleTextStyle),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(message!, style: style.bodyTextStyle),
          ],
          if (child != null) ...[const SizedBox(height: AppSpacing.xl), child!],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxl),
            if (actionsAxis == Axis.horizontal)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final (index, action) in actions.indexed) ...[
                    if (index > 0) Gap.hMd,
                    action,
                  ],
                ],
              )
            else
              // Full width, so a stack of actions reads as a column with one
              // edge rather than as buttons of three different lengths.
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, action) in actions.indexed) ...[
                    if (index > 0) Gap.vMd,
                    action,
                  ],
                ],
              ),
          ],
        ],
      ),
    ),
  );
}
