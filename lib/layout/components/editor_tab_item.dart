import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:plat/plat.dart';
import 'package:pinbench_ui/ui/app_icon_button.dart';
import 'package:pinbench_ui/ui/app_context_menu.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/theme/app_icons.dart';
import 'package:pinbench_ui/theme/theme.dart';

import '../../features/workspace/providers/dirty_files_provider.dart';
import '../../features/editor/providers/editor_provider.dart';
import '../../features/workspace/providers/workspace_files_provider.dart';
import '../../features/workspace/providers/editor_state_provider.dart';
import 'chrome_tab.dart';
import '../../core/chrome/chrome_commands.dart';

class const EditorTab({super.key, required final PlatTabDetails tab})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<EditorTab> createState() => _EditorTabItemState();
}

class _EditorTabItemState extends ConsumerState<EditorTab> {
  final _contextMenuController = AppContextMenuController();

  @override
  void initState() {
    super.initState();
    _contextMenuController.addListener(_onMenuStateChanged);
  }

  void _onMenuStateChanged() {
    if (_contextMenuController.isOpen) {
      if (ref.read(activeContextMenuIdProvider) != widget.tab.snapshot.id) {
        unawaited(
          Future.microtask(() {
            if (mounted) {
              ref.read(activeContextMenuIdProvider.notifier).updateId(widget.tab.snapshot.id);
            }
          }),
        );
      }
    } else {
      if (ref.read(activeContextMenuIdProvider) == widget.tab.snapshot.id) {
        unawaited(
          Future.microtask(() {
            if (mounted) {
              ref.read(activeContextMenuIdProvider.notifier).updateId(null);
            }
          }),
        );
      }
    }
  }

  @override
  void dispose() {
    _contextMenuController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final isActive = widget.tab.states.contains(WidgetState.selected);

    final colors = context.appColors;
    final color = isActive ? colors.primary : colors.foreground;

    final isMenuVisible = ref.watch(activeContextMenuIdProvider) == tab.snapshot.id;

    final isWelcome = widget.tab.snapshot.title == 'Welcome';
    final isCanvas = widget.tab.snapshot.data == 'canvas_view';
    final isSettings = widget.tab.snapshot.id == AppTabs.settings;
    final isReleaseNotes = widget.tab.snapshot.id == AppTabs.releaseNotes;

    final trackedPath = _trackedPath();
    final isDirty =
        trackedPath != null && ref.watch(dirtyFilesProvider.select((s) => s.contains(trackedPath)));
    final isHovered = tab.states.contains(WidgetState.hovered);

    // Only one tab's menu may be open at a time, which the provider arbitrates;
    // a tab that is no longer the active one closes itself.
    if (!isMenuVisible && _contextMenuController.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _contextMenuController.hide();
      });
    }

    return AppContextMenu(
      controller: _contextMenuController,
      entries: [
        AppContextMenuItem(onPressed: () => _closeTab(tab.snapshot.id), text: 'Close'),
        AppContextMenuItem(onPressed: () => _closeOtherTabs(tab.snapshot.id), text: 'Close Others'),
        AppContextMenuItem(onPressed: _closeAllTabs, text: 'Close All'),
      ],
      child: GestureDetector(
        onSecondaryTapDown: (details) => _contextMenuController.showAt(details.globalPosition),
        child: ChromeTab(
          tab: tab,
          child: Row(
            spacing: 4,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Icon(
                  switch (true) {
                    _ when isWelcome => AppIcons.home,
                    _ when isSettings => AppIcons.settings,
                    _ when isReleaseNotes => AppIcons.releaseNotes,
                    _ when isCanvas => AppIcons.circuit,
                    _ => AppIcons.code,
                  },
                  size: AppIconSize.sm,
                  color: color,
                ),
              ),
              Text(tab.snapshot.title, style: TextStyle(color: color)),
              // VS Code-style: show an unsaved dot while dirty, swapping to the
              // close (×) button on hover so the file can still be closed.
              //
              // The dot and the close button MUST occupy the same footprint. If
              // they differ, swapping them on hover changes the tab's width, and
              // when the cursor sits in the trailing band the tab keeps growing
              // (dot) and shrinking (button) under it — un-hovering and
              // re-hovering in a rapid flicker loop. A fixed-size slot keeps the
              // width constant so hover state can't move the boundary.
              SizedBox(
                width: AppIconButtonSize.small.size,
                height: AppIconButtonSize.small.size,
                child: (isDirty && !isHovered)
                    ? GestureDetector(
                        onTap: () => _closeTab(tab.snapshot.id),
                        child: Center(
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                          ),
                        ),
                      )
                    : AppIconButton(
                        color: color,
                        icon: AppIcons.close,
                        tooltip: 'Close',
                        shortcutLabel: '⌘W',
                        size: AppIconButtonSize.small,
                        onPressed: () => _closeTab(tab.snapshot.id),
                        hoverBackgroundColor: isActive ? colors.accent : AppPalette.transparent,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Whether closing this tab should release editor state for a file. The
  /// welcome screen, the settings tab and the release notes are chrome, not
  /// documents — asking
  /// the editor to close a file called `settings` finds nothing, but says
  /// something untrue about what the tab is.
  static bool _holdsAFile(String tabId) =>
      tabId != 'Welcome' &&
      tabId != 'welcome' &&
      tabId != AppTabs.settings &&
      tabId != AppTabs.releaseNotes;

  /// The workspace file path this tab maps to (for dirty tracking / cleanup),
  /// or null for non-file tabs like Welcome. Editor tabs carry the path in
  /// `data`; canvas tabs derive it from their `canvas_<path>` id.
  String? _trackedPath() {
    if (widget.tab.snapshot.title == 'Welcome') return null;
    final data = widget.tab.snapshot.data;
    if (data is String && data != 'canvas_view') return data;
    final id = widget.tab.snapshot.id;
    return AppTabs.canvasFileOf(id);
  }

  void _closeTab(String tabId) {
    final chrome = ref.read(chromeCommandsProvider);
    final groupTabs = widget.tab.group.tabs;

    // Closing an empty, never-saved `untitled-*.txt` scratch file should discard
    // it rather than leave a stray empty file behind (VS Code behaviour).
    final trackedPath = _trackedPath();
    String? emptyUntitledToDelete;
    if (trackedPath != null) {
      final controller = ref.read(editorStateControllerProvider).openFileControllers[trackedPath];
      final base = p.basename(trackedPath).toLowerCase();
      if (controller != null &&
          controller.text.trim().isEmpty &&
          base.startsWith('untitled') &&
          base.endsWith('.txt')) {
        emptyUntitledToDelete = trackedPath;
      }
    }

    final tabs = List<String>.from(ref.read(tabsListProvider))..remove(tabId);
    if (groupTabs.length == 1) {
      tabs.add('Welcome');
    }

    ref.read(tabsListProvider.notifier).updateTabs(tabs);
    if (ref.read(activeTabProvider) == tabId) {
      ref.read(activeTabProvider.notifier).setActive(tabs.isEmpty ? '' : tabs.last);
    }

    if (_holdsAFile(tabId)) {
      final data = widget.tab.snapshot.data;
      if (data is String) {
        ref.read(editorStateControllerProvider).closeFile(data);
      } else {
        ref.read(editorStateControllerProvider).closeFile(tabId);
      }
    }

    chrome.closeTab(tabId);

    if (emptyUntitledToDelete != null) {
      unawaited(
        ref.read(workspaceFilesProvider.notifier).deleteWorkspaceFile(emptyUntitledToDelete),
      );
    }
  }

  void _closeOtherTabs(String tabId) {
    final chrome = ref.read(chromeCommandsProvider);
    final groupTabs = widget.tab.group.tabs;
    for (final t in groupTabs) {
      if (t.id != tabId) {
        if (_holdsAFile(t.id)) {
          final data = t.data;
          if (data is String) {
            ref.read(editorStateControllerProvider).closeFile(data);
          } else {
            ref.read(editorStateControllerProvider).closeFile(t.id);
          }
        }
        chrome.closeTab(t.id);
      }
    }
    ref.read(tabsListProvider.notifier).updateTabs([tabId]);
    ref.read(activeTabProvider.notifier).setActive(tabId);
  }

  void _closeAllTabs() {
    final chrome = ref.read(chromeCommandsProvider);
    final groupTabs = widget.tab.group.tabs;

    for (final t in groupTabs) {
      if (_holdsAFile(t.id)) {
        final data = t.data;
        if (data is String) {
          ref.read(editorStateControllerProvider).closeFile(data);
        } else {
          ref.read(editorStateControllerProvider).closeFile(t.id);
        }
        chrome.closeTab(t.id);
      }
    }

    ref.read(tabsListProvider.notifier).updateTabs([]);
    ref.read(activeTabProvider.notifier).setActive('');
  }
}
