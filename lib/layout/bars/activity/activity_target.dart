import 'package:flutter/widgets.dart';

import 'package:plat/plat.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

const List<ActivityBarTab> topTabs = [.explorer, .parts, .properties];

/// Settings is deliberately absent: it is not a sidebar any more but a
/// center-pane document, opened by `SettingsTabButton` rather than by a slot.
const List<ActivityBarTab> bottomTabs = [.account];

enum ActivityBarTab {
  explorer(slotId: 'left_slot', leafId: 'explorer', title: 'Explorer', icon: AppIcons.folder),
  parts(slotId: 'left_slot', leafId: 'parts', title: 'Parts', icon: AppIcons.parts),
  properties(
    slotId: 'left_slot',
    leafId: 'properties',
    title: 'Properties',
    icon: AppIcons.properties,
  ),
  account(slotId: 'left_slot', leafId: 'account', title: 'Account', icon: AppIcons.account);

  final String slotId;
  final String leafId;
  final String title;
  final IconData icon;

  const ActivityBarTab({
    required this.slotId,
    required this.leafId,
    required this.title,
    required this.icon,
  });

  Plat get pane => .leaf(id: leafId, title: title, locked: true);
}
