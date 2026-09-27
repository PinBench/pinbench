import 'package:flutter/widgets.dart';

import 'package:pinbench_ui/strings.dart';

PlatformMenu viewMenu() => const PlatformMenu(
  label: AppStrings.viewMenuLabel,
  menus: <PlatformMenuItem>[
    PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.toggleFullScreen),
  ],
);
