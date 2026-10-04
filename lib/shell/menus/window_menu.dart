import 'package:flutter/widgets.dart';

import 'package:pinbench_ui/strings.dart';

PlatformMenu windowMenu() => const PlatformMenu(
  label: AppStrings.windowMenuLabel,
  menus: <PlatformMenuItem>[
    PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.minimizeWindow),
    PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.zoomWindow),
    PlatformMenuItemGroup(
      members: [PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.toggleFullScreen)],
    ),
    PlatformMenuItemGroup(
      members: [PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.arrangeWindowsInFront)],
    ),
  ],
);
