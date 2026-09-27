import 'package:flutter/widgets.dart';

import 'package:pinbench_ui/strings.dart';

PlatformMenu appMainMenu() => const PlatformMenu(
  label: AppStrings.appName,
  menus: [
    PlatformMenuItemGroup(
      members: [
        PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
        // PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.settings),
      ],
    ),
    PlatformMenuItemGroup(
      members: [PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.servicesSubmenu)],
    ),
    PlatformMenuItemGroup(
      members: [
        PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
        PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hideOtherApplications),
        PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.showAllApplications),
      ],
    ),
    PlatformMenuItemGroup(
      members: [PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit)],
    ),
  ],
);
