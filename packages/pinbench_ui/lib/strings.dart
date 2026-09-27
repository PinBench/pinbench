/// Centralized user-facing string literals.
///
/// This is prep for a real i18n layer: today every member is just a plain
/// English literal, but funneling every call site through [AppStrings] means
/// swapping in ARB-based lookups later touches this one file instead of every
/// widget again. Grouped by feature area for readability, matching the style
/// of `AppTextStyles` in `shared/theme/`.
class AppStrings {
  AppStrings._();

  // ── App ────────────────────────────────────────────────────────────────
  /// App display name (window menu label, empty-workspace heading, About dialog).
  static const appName = 'PinBench';

  // ── Common actions ─────────────────────────────────────────────────────
  // Shared across canvas tooltips, native/web menus, and context menus — the
  // text is identical everywhere it appears, so one constant covers all of them.
  static const copy = 'Copy';
  static const paste = 'Paste';
  static const delete = 'Delete';
  static const undo = 'Undo';
  static const redo = 'Redo';
  static const cancelButtonLabel = 'Cancel';
  static const okButtonLabel = 'OK';
  static const saveButtonLabel = 'Save';
  static const closeButtonLabel = 'Close';
  static const shareProjectButtonLabel = 'Share Project';
  static const openFolderMenuLabel = 'Open Folder...';

  /// Generic `Error: $x` template repeated verbatim across several async-error
  /// states (account view, parts view).
  static String genericErrorMessage(Object error) => 'Error: $error';

  // ── Title bar ───────────────────────────────────────────────────────────
  static const searchComingSoonTooltip = 'Global workspace search - Coming Soon';
  static const globalSearchPlaceholder = 'Search';
  static const themeToggleTooltipLight = 'Switch to light theme';
  static const themeToggleTooltipDark = 'Switch to dark theme';
  static const sendFeedbackTooltip = 'Send Feedback';
  static const exportCircuitTooltip = 'Export Circuit to PNG';
  static const exportSuccessTitle = 'Export Successful';
  static const exportSuccessMessage = 'Your circuit was exported to PNG.';
  static const exportFailedTitle = 'Export Failed';
  static const exportFailedMessage = 'Failed to export or export was cancelled.';
  static const backToWelcomeTooltip = 'Back to Welcome';

  static const loadingWorkspaceLabel = 'Loading workspace';
  static const workspaceSavedToastTitle = 'Workspace saved';
  static const workspaceSavedToastMessage = 'Your project was saved and added to Recent.';

  static const toggleLeftPaneTooltip = 'Toggle Left Pane';
  static const toggleBottomPaneTooltip = 'Toggle Bottom Pane';
  static const toggleRightPaneTooltip = 'Toggle Right Pane';

  // ── Cloud project open (router) ────────────────────────────────────────
  static const cloudProjectOpenFailedTitle = "Couldn't open this project";
  static const cloudProjectOpenFailedMessage =
      'Make sure you are signed in and have access to it, then try again.';

  // ── Share dialog ────────────────────────────────────────────────────────
  static const shareLinkSectionLabel = 'General access';
  static const shareLinkRestrictedTitle = 'Restricted';
  static const shareLinkRestrictedBody = 'Only people you invite can open this.';
  static const shareLinkAnyoneTitle = 'Anyone with the link';
  static const shareLinkAnyoneBody = 'Anyone with the link can view and run it. They cannot edit.';
  static const shareCopyLinkLabel = 'Copy link';
  static const shareLinkCopiedMessage = 'Link copied';
  static const shareInviteSectionLabel = 'People with access';
  static const shareEmailPlaceholder = 'Add people by email';
  static const shareInviteButtonLabel = 'Invite';
  static const shareInviteSentMessage = 'Invite added';
  static const shareInvalidEmailMessage = 'Enter a valid email address';
  static const sharePendingSuffix = 'pending';
  static const shareOwnerSuffix = 'owner';
  static const shareNobodyElseMessage = 'No one else yet.';
  static const shareRemoveCollaboratorLabel = 'Remove collaborator';
  static const embedOpenInAppLabel = 'Open in PinBench';
  static const shareEmbedLockedTitle = 'Embedding is a Pro feature';
  static const shareEmbedLockedBody =
      'Sharing a link is free and always will be. Embedding the running '
      'circuit in your own page needs Pro.';
  static const shareEmbedUnavailableBody = 'Embeds are not available in this build.';

  static const shareCopyEmbedLabel = 'Copy embed code';
  static const shareCopyLiveEmbedLabel = 'Copy live embed code';
  static const shareLiveEmbedCopiedMessage = 'Live embed code copied — it follows your edits';
  static const shareEmbedCopiedMessage = 'Embed code copied';

  static const shareDialogTitle = 'Share';
  static const shareYouSuffix = '(you)';
  static const shareDoneButtonLabel = 'Done';
  static const shareRoleViewerLabel = 'Viewer';
  static const shareRestrictedDescription = 'Only people with access can open with the link';
  static const shareAnyoneDescription = 'Anyone on the internet with the link can view and run it';
  static const shareLinkNoteForViewers =
      'A link only ever grants viewing. To let someone edit, invite them by email.';

  // ── Shared project view (banner) ────────────────────────────────────────
  static const sharedProjectBannerTitle = 'Viewing a shared circuit';
  static const sharedProjectBannerBody =
      'You can edit and run it here, but changes will not reach the original. '
      'Save a copy to keep your changes.';
  static const sharedProjectSaveCopyLabel = 'Save a copy';
  static const sharedProjectSignInToCopy = 'Sign in to save a copy';
  static const sharedProjectCopiedTitle = 'Saved your own copy';
  static const sharedProjectCopiedMessage =
      'This is now your project. Edits from here on are saved to your account.';
  static const sharedProjectCopyFailedTitle = "Couldn't save a copy";
  static const sharedProjectCopyFailedMessage = 'Make sure you are signed in, then try again.';

  // ── Account sidebar ─────────────────────────────────────────────────────
  static const cloudSaveSuccessTitle = 'Saved to the cloud';
  static const cloudSaveSuccessMessage = 'This workspace now syncs online — share it from here.';
  static const cloudSaveFailedTitle = "Couldn't save to the cloud";
  static const cloudSaveFailedMessage =
      'Open a workspace and make sure you are signed in, then try again.';
  static const defaultUserNameFallback = 'User';
  static const signOutButtonLabel = 'Sign Out';
  static const cloudSyncHintMessage = 'Workspace data syncs to the cloud.';
  static const saveToCloudButtonLabel = 'Save Workspace to Cloud';
  static String signInFailedMessage(Object e) => 'Sign-in failed: $e';
  static const signInUnavailableMessage = 'Sign-in is not available on this platform.';
  static const signInPromptMessage = 'Sign in to sync your workspaces across devices.';
  static const signInButtonLabel = 'Sign in';
  static const signInPopupHintMessage = 'Opens a Google sign-in popup.';

  // ── Explorer sidebar ─────────────────────────────────────────────────────
  static const explorerSidebarTitle = 'Explorer';
  static const newFileTooltip = 'New File';
  static const newFolderTooltip = 'New Folder';
  static const explorerEmptyStateMessage = 'You have not yet opened a folder.';
  static const openFolderButtonLabel = 'Open Folder';
  static const webPreviewUnavailableTitle = 'Not available in the web preview';
  static const webPreviewFolderUnavailableMessage =
      'Opening a local folder needs the desktop app. Try an example template instead.';
  static String fileReadErrorMessage(Object e) => 'Could not read file: $e';

  // Explorer right-click context menu items (kept distinct from the dialog
  // titles below even though several share the same text).
  static const explorerContextNewFile = 'New File';
  static const explorerContextNewFolder = 'New Folder';
  static const explorerContextRename = 'Rename';
  static const explorerContextDelete = 'Delete';
  static const newFileDialogTitle = 'New File';
  static const newFolderDialogTitle = 'New Folder';
  static const renameDialogTitle = 'Rename';

  // ── Text input dialog ────────────────────────────────────────────────────
  static const confirmDialogDefaultLabel = 'Create';

  // ── Confirm dialogs ──────────────────────────────────────────────────────
  static const confirmButtonLabel = 'Confirm';

  /// Deleting from the explorer is immediate and has no undo — a folder goes
  /// with everything in it — so the prompt names the thing and says so.
  static const deleteFileDialogTitle = 'Delete file?';
  static const deleteFolderDialogTitle = 'Delete folder?';
  static String deleteFileDialogMessage(String name) =>
      '“$name” will be deleted from your computer. This cannot be undone.';
  static String deleteFolderDialogMessage(String name) =>
      '“$name” and everything inside it will be deleted from your computer. '
      'This cannot be undone.';

  // ── Share project dialog ─────────────────────────────────────────────────
  static const shareProjectDialogDescription =
      'Give another account editable or read-only access to this project. '
      'They see your edits in real time, same as you see theirs.';
  static const collaboratorUidPlaceholder = 'Collaborator uid';
  static const roleEditorLabel = 'Editor';
  static const roleViewerLabel = 'Viewer';
  static const shareButtonLabel = 'Share';
  static String shareFailedErrorMessage(Object e) => 'Could not share: $e';
  static const collaboratorsSectionLabel = 'Collaborators';
  static const noCollaboratorsMessage = 'No collaborators yet.';

  // ── Settings tab ─────────────────────────────────────────────────────────
  static const settingsTitle = 'Settings';
  static const settingsSubtitle = 'These apply to the app, not to one project.';
  static const settingsUpdatesDescription = 'How this app finds and installs new releases.';

  // ── Empty workspace / empty editor placeholders ──────────────────────────

  static const noFileOpenHeading = 'No file is open';
  static const noFileOpenSubtext = 'Select a file from the workspace to start editing';
  static const openChatShortcutLabel = 'Open Chat';
  static const showAllCommandsShortcutLabel = 'Show All Commands';
  static const openRecentMenuLabel = 'Open Recent';
  static const openFileOrFolderShortcutLabel = 'Open File or Folder';
  static const newUntitledFileShortcutLabel = 'New Untitled Text File';
  static const untitledProjectLabel = 'Untitled';

  // ── Welcome screen ────────────────────────────────────────────────────────
  static const startSectionTitle = 'Start';
  static const templatesSectionTitle = 'Templates';
  static const recentWorkspacesSectionTitle = 'Recent Workspaces';
  static const cloudProjectsSectionTitle = 'Cloud Projects';
  static const welcomeHeaderTitle = 'PinBench';
  static const welcomeHeaderSubtitle = 'Design, simulate, and build circuits beautifully.';

  static const noTemplatesFoundMessage = 'No templates found in the registry.';
  static const templateTileSubtitle = 'Pre-configured starter circuit';
  static const templatesLoadErrorMessage = 'Error loading templates';

  static const cloudSignInPromptMessage = 'Sign in to load your cloud projects.';
  static const cloudProjectsLoadErrorMessage = 'Error loading cloud projects';
  static const noCloudProjectsMessage =
      'No cloud projects yet. Save a workspace to the cloud to see it here.';

  static const noRecentWorkspacesMessage = 'No recent workspaces';

  static const newBlankProjectTitle = 'New Blank Project';
  static const newBlankProjectSubtitle = 'Start with an empty canvas';
  static const openFolderTileSubtitle = 'Load an existing workspace';
  // Pre-existing wording inconsistency vs. explorer_view.dart's version — kept
  // verbatim as its own constant rather than merged/reworded.
  static const webPreviewFolderUnavailableMessageAlt =
      'Opening a local folder needs the desktop app. Try one of the example templates instead.';

  // ── Canvas: properties panel ──────────────────────────────────────────────
  static const propertiesSidebarTitle = 'Properties';
  static const noComponentSelectedMessage = 'No component selected';
  static const noComponentSelectedSubtext =
      'Select a component on the canvas to view and edit its properties.';
  static const propertyLabelName = 'Name';
  static const propertyLabelPositionX = 'Position X';
  static const propertyLabelPositionY = 'Position Y';
  static const propertyLabelRotation = 'Rotation (°)';
  static const propertyLabelFlipH = 'Flipped Horizontal';
  static const propertyLabelFlipV = 'Flipped Vertical';
  static const propertyLabelWidth = 'Width';
  static const propertyLabelHeight = 'Height';

  // ── Canvas: parts palette ──────────────────────────────────────────────────
  static const partsSidebarTitle = 'Parts';
  static const searchComponentsPlaceholder = 'Search components...';
  static const noComponentsFoundMessage = 'No components found.';

  // ── Canvas: toolbar / zoom controls / context menu ─────────────────────────
  static const viewCodeTooltip = 'View Code';
  static const zoomInTooltip = 'Zoom In';
  static const zoomOutTooltip = 'Zoom Out';
  static const toggleGridTooltip = 'Toggle Grid';
  static const resetViewTooltip = 'Reset View';

  static const rotateLeftMenuLabel = 'Rotate Left';
  static const rotateRightMenuLabel = 'Rotate Right';
  static const flipHorizontalMenuLabel = 'Flip Horizontal';
  static const flipVerticalMenuLabel = 'Flip Vertical';
  static const bringForwardMenuLabel = 'Bring Forward';
  static const sendBackwardMenuLabel = 'Send Backward';
  static const duplicateMenuLabel = 'Duplicate';

  static const wireColorLabel = 'Wire Color';

  static const resetToDefaultTooltip = 'Reset to default';

  // ── Bottom pane: serial monitor / plotter / problems / logs ─────────────────
  static const serialMonitorTitle = 'Serial Monitor';
  static const noSerialOutputMessage = 'No serial output received.';
  static const serialInputPlaceholderEnabled = 'Type a message and press Enter to send';
  static const serialInputPlaceholderDisabled = 'Start the simulation to send serial input';
  static const sendButtonLabel = 'Send';

  static const noPlotterDataMessage = 'No numeric serial data yet.';
  static const plotterHintMessage =
      'Print numbers with Serial.println() — e.g. "temp:23.5,humidity:60" — to plot them.';

  static const noProblemsMessage = 'No problems have been detected in the workspace.';
  static const problemSourceCircuitLabel = 'Circuit';
  static const problemSourceCompilerLabel = 'Compiler';
  static const problemSourceParserLabel = 'Parser';

  static const debugConsoleTitle = 'Debug Console';
  static const noDebugLogsMessage = 'No debug logs recorded.';

  static const spiceLogsTitle = 'SPICE Logs';
  static const noSpiceLogsMessage = 'No SPICE simulation logs recorded.';

  static const defaultEmptyLogsMessage = 'No logs available.';

  // ── Leaving a temporary project ──────────────────────────────────────────
  static const leaveTemporaryTitle = 'Save this project?';
  static const leaveTemporaryMessage =
      'It only exists in a temporary folder, so leaving now discards it.';
  static const leaveTemporaryNowhereToSave =
      'It only exists in a temporary folder, so leaving now discards it. '
      'Sign in to save it to the cloud, or use the desktop app to save it to a folder.';
  static const leaveTemporarySaveToComputer = 'Save to Computer';
  static const leaveTemporarySaveToCloud = 'Save to Cloud';
  static const leaveTemporaryDiscard = 'Discard';

  /// The way out that changes nothing. Every other button in this dialog
  /// leaves the project, so without it the only way to stay is Escape.
  static const leaveTemporaryKeepEditing = 'Keep Editing';

  // ── Updates ──────────────────────────────────────────────────────────────
  static const updatesSectionTitle = 'Updates';
  static const updatesCheckMenuLabel = 'Check for Updates…';
  static const updatesCheckButtonLabel = 'Check now';
  static const updatesCheckingLabel = 'Checking…';
  static const updatesAutomaticLabel = 'Check automatically';
  static const updatesAutomaticDescription =
      'Looks for a new release once a day, and when the app starts.';
  static const updatesUpToDate = 'You are on the latest release.';
  static const updatesUnsupported =
      'This build updates through however you installed it — the signed '
      'downloads update themselves.';
  static const updatesInstallLabel = 'Install and restart';
  static const updatesDownloadLabel = 'Get it';
  static const updatesReleaseNotesLabel = 'Release notes';
  static const updatesDialogTitle = 'Update';

  /// The banner headline. [version] is null when the platform's updater
  /// reported a version string that could not be parsed — the update is still
  /// real and still installable, so it is announced without a number rather
  /// than not announced.
  static String updatesAvailable(String? version) =>
      version == null ? 'A new version is available.' : 'Version $version is available.';

  static String updatesInstalledVersion(String version) => 'You have $version.';

  /// Shown under an available update that the platform cannot install for
  /// itself — see `UpdateConfig.linuxManifestUrl`.
  static const updatesManualInstall =
      'Downloads open in your browser; replace the app the way you installed it.';

  static const terminalClosedMessage = 'Terminal session is closed.';
  static const terminalClosedHint = 'Click the + icon in the toolbar to start a new one.';

  static const newTerminalTooltip = 'New Terminal';
  static const splitTerminalTooltip = 'Split Terminal';
  static const killTerminalTooltip = 'Kill Terminal';
  static const copyConsoleTooltip = 'Copy Console';
  static const filterTooltip = 'Filter';
  static const clearConsoleTooltip = 'Clear Console';
  static const copyLogsTooltip = 'Copy Logs';
  static const clearSpiceLogsTooltip = 'Clear Spice Logs';
  static const clearSerialMonitorTooltip = 'Clear Serial Monitor';

  // ── Menus: File ───────────────────────────────────────────────────────────
  static const fileMenuLabel = 'File';
  static const shareMenuLabel = 'Share';
  static const exportZipMenuLabel = 'Export to zip...';

  static const newTextFileMenuLabel = 'New Text File';
  static const newSketchMenuLabel = 'New Sketch (.ino)...';
  static const newSketchDialogTitle = 'New Arduino Sketch';
  static const newCircuitMenuLabel = 'New Circuit (.cdl)...';
  static const newCircuitDialogTitle = 'New Circuit';
  static const newFileMenuLabel = 'New File...';
  static const newFileNamePlaceholder = 'e.g. sketch.ino';
  static const newWindowMenuLabel = 'New Window';
  static const newWindowWithProfileMenuLabel = 'New Window with Profile';
  static const defaultProfileMenuLabel = 'Default';

  static const openMenuLabel = 'Open...';
  static const openWorkspaceFromFileMenuLabel = 'Open Workspace from File...';
  static const clearRecentlyOpenedMenuLabel = 'Clear Recently Opened';
  // Web menu bar's "Open File..." wording differs from native's "Open...".
  static const openFileMenuLabelWeb = 'Open File...';

  static const saveAsMenuLabel = 'Save As...';
  static const saveAllMenuLabel = 'Save All';
  static const autoSaveMenuLabel = 'Auto Save';

  static const revertFileMenuLabel = 'Revert File';
  static const closeEditorMenuLabel = 'Close Editor';
  static const closeFolderMenuLabel = 'Close Folder';
  static const closeWindowMenuLabel = 'Close Window';

  static const addFolderToWorkspaceMenuLabel = 'Add Folder to Workspace...';
  static const saveWorkspaceAsMenuLabel = 'Save Workspace As...';
  static const duplicateWorkspaceMenuLabel = 'Duplicate Workspace';

  // ── Menus: Edit / View / Window / Help ───────────────────────────────────
  static const editMenuLabel = 'Edit';
  static const cutMenuLabel = 'Cut';
  static const selectAllMenuLabel = 'Select All';

  static const viewMenuLabel = 'View';
  static const windowMenuLabel = 'Window';
  static const helpMenuLabel = 'Help';
  static const aboutMenuItemLabel = 'About';

  // ── Menus: Run ────────────────────────────────────────────────────────────
  static const runMenuLabel = 'Run';
  // Double space before "(F5)"/"(F8)" kept verbatim — pre-existing formatting.
  static const stopSimulationMenuLabel = 'Stop Simulation  (F5)';
  static const runSimulationMenuLabel = 'Run Simulation  (F5)';
  static const resumeSimulationMenuLabel = 'Resume Simulation  (F8)';
  static const pauseSimulationMenuLabel = 'Pause Simulation  (F8)';
  static const mainSketchMenuLabel = 'Main Sketch';
  static const autoFirstSketchMenuLabel = 'Auto (first sketch)';
  static const mainCircuitMenuLabel = 'Main Circuit';
  static const autoActiveCircuitMenuLabel = 'Auto (active circuit)';
  static String loadHexMenuLabelWithFile(String filename) =>
      'Load Compiled .hex... (using $filename)';
  static const loadHexMenuLabel = 'Load Compiled .hex...';
  static const useCompilerMenuLabel = 'Use Compiler (clear loaded .hex)';

  // Web menu bar's Run entries drop the "(F5)"/"(F8)" suffix, unlike native.
  static const stopSimulationMenuLabelWeb = 'Stop Simulation';
  static const runSimulationMenuLabelWeb = 'Run Simulation';
  static const resumeSimulationMenuLabelWeb = 'Resume Simulation';
  static const pauseSimulationMenuLabelWeb = 'Pause Simulation';
  static const loadHexMenuLabelLoadedWeb = 'Load Compiled .hex... (loaded)';

  // ── File-type groups (native file pickers) ───────────────────────────────
  static const hexFileTypeGroupLabel = 'Compiled firmware';
  static const sketchesFileTypeGroupLabel = 'Sketches & circuits';
  static const zipFileTypeGroupLabel = 'Zip archive';
  static const pngFileTypeGroupLabel = 'PNG Image';
}
