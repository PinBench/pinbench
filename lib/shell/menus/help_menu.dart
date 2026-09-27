import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/strings.dart';

import 'shared_menu_actions.dart';

/// [ref] comes from `GlobalMenuWrapper`, which is always mounted at the app
/// root, so it can be used directly instead of the `FocusManager` +
/// `ProviderScope.containerOf` fallback other native menu callbacks need.
PlatformMenu helpMenu(WidgetRef ref) => PlatformMenu(
  label: AppStrings.helpMenuLabel,
  menus: <PlatformMenuItem>[
    PlatformMenuItem(label: 'Welcome', onSelected: () => goToWelcomeTab(ref)),
    PlatformMenuItem(
      label: AppStrings.updatesCheckMenuLabel,
      onSelected: () => unawaited(checkForUpdates(ref)),
    ),
  ],
);
