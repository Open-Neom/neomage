// Sandbox Settings — full port of neom_claw/src/components/sandbox/.
// Ports: SandboxSettings.tsx, SandboxOverridesTab.tsx, SandboxConfigTab.tsx,
//        SandboxDependenciesTab.tsx, SandboxDoctorSection.tsx.
//
// Uses Sint (GetX-like) state management:
//   - SintController with .obs observables
//   - Obx(() => Widget) reactive wrappers
//   - Sint.find<T>() / Sint.put()

import 'package:neom_claw/core/platform/claw_io.dart' show Platform;

import 'package:flutter/material.dart';
import 'package:sint/sint.dart';

import 'design_system.dart';

// ────────────────────────────────────────────────────────────────────────────
// MODELS
// ────────────────────────────────────────────────────────────────────────────

/// Sandbox execution mode — mirrors TS `SandboxMode`.
enum SandboxMode {
  autoAllow('auto-allow'),
  regular('regular'),
  disabled('disabled');

  const SandboxMode(this.value);
  final String value;

  String get label {
    switch (this) {
      case SandboxMode.autoAllow:
        return 'Sandbox BashTool, with auto-allow';
      case SandboxMode.regular:
        return 'Sandbox BashTool, with regular permissions';
      case SandboxMode.disabled:
        return 'No Sandbox';
    }
  }

  String get confirmationMessage {
    switch (this) {
      case SandboxMode.autoAllow:
        return '✓ Sandbox enabled with auto-allow for bash commands';
      case SandboxMode.regular:
        return '✓ Sandbox enabled with regular bash permissions';
      case SandboxMode.disabled:
        return '○ Sandbox disabled';
    }
  }
}

/// Override mode for unsandboxed fallback — mirrors TS `OverrideMode`.
enum OverrideMode {
  open('open'),
  closed('closed');

  const OverrideMode(this.value);
  final String value;

  String get label {
    switch (this) {
      case OverrideMode.open:
        return 'Allow unsandboxed fallback';
      case OverrideMode.closed:
        return 'Strict sandbox mode';
    }
  }

  String get confirmationMessage {
    switch (this) {
      case OverrideMode.open:
        return '✓ Unsandboxed fallback allowed – commands can run outside sandbox when necessary';
      case OverrideMode.closed:
        return '✓ Strict sandbox mode – all commands must run in sandbox or be excluded via the excludedCommands option';
    }
  }

  String get description {
    switch (this) {
      case OverrideMode.open:
        return 'When a command fails due to sandbox restrictions, NeomClaw can retry '
            'with dangerouslyDisableSandbox to run outside the sandbox (falling '
            'back to default permissions).';
      case OverrideMode.closed:
        return 'All bash commands invoked by the model must run in the sandbox '
            'unless they are explicitly listed in excludedCommands.';
    }
  }
}

/// Result of a dependency check — mirrors TS `SandboxDependencyCheck`.
class SandboxDependencyCheck {
  final List<String> errors;
  final List<String> warnings;

  const SandboxDependencyCheck({
    this.errors = const [],
    this.warnings = const [],
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
  bool get isClean => !hasErrors && !hasWarnings;
}

/// Filesystem read restriction config — mirrors TS sandbox adapter.
class FsReadConfig {
  final List<String> denyOnly;
  final List<String> allowWithinDeny;

  const FsReadConfig({
    this.denyOnly = const [],
    this.allowWithinDeny = const [],
  });
}

/// Filesystem write restriction config.
class FsWriteConfig {
  final List<String> allowOnly;
  final List<String> denyWithinAllow;

  const FsWriteConfig({
    this.allowOnly = const [],
    this.denyWithinAllow = const [],
  });
}

/// Network restriction config.
class NetworkRestrictionConfig {
  final List<String> allowedHosts;
  final List<String> deniedHosts;

  const NetworkRestrictionConfig({
    this.allowedHosts = const [],
    this.deniedHosts = const [],
  });

  bool get hasRestrictions => allowedHosts.isNotEmpty || deniedHosts.isNotEmpty;
}

/// Full sandbox configuration snapshot used by the Config tab.
class SandboxConfigSnapshot {
  final List<String> excludedCommands;
  final FsReadConfig fsReadConfig;
  final FsWriteConfig fsWriteConfig;
  final NetworkRestrictionConfig networkConfig;
  final List<String> allowUnixSockets;
  final List<String> globPatternWarnings;
  final bool isManagedDomainsOnly;

  const SandboxConfigSnapshot({
    this.excludedCommands = const [],
    this.fsReadConfig = const FsReadConfig(),
    this.fsWriteConfig = const FsWriteConfig(),
    this.networkConfig = const NetworkRestrictionConfig(),
    this.allowUnixSockets = const [],
    this.globPatternWarnings = const [],
    this.isManagedDomainsOnly = false,
  });
}

// ────────────────────────────────────────────────────────────────────────────
// SANDBOX MANAGER (stub adapter)
// ────────────────────────────────────────────────────────────────────────────

/// Stub sandbox adapter — in production these would delegate to the actual
/// sandbox runtime. Mirrors the TS `SandboxManager` static API.
class SandboxManagerAdapter {
  SandboxManagerAdapter._();

  static bool _enabled = false;
  static bool _autoAllowBash = false;
  static bool _allowUnsandboxedCommands = false;
  static final bool _lockedByPolicy = false;

  // ── Query state ──

  static bool isSupportedPlatform() {
    return Platform.isMacOS || Platform.isLinux;
  }

  static bool isSandboxingEnabled() => _enabled;

  static bool isSandboxEnabledInSettings() => _enabled;

  static bool isAutoAllowBashIfSandboxedEnabled() => _autoAllowBash;

  static bool areUnsandboxedCommandsAllowed() => _allowUnsandboxedCommands;

  static bool areSandboxSettingsLockedByPolicy() => _lockedByPolicy;

  static SandboxMode getCurrentMode() {
    if (!_enabled) return SandboxMode.disabled;
    if (_autoAllowBash) return SandboxMode.autoAllow;
    return SandboxMode.regular;
  }

  // ── Mutations ──

  static Future<void> setSandboxMode(SandboxMode mode) async {
    switch (mode) {
      case SandboxMode.autoAllow:
        _enabled = true;
        _autoAllowBash = true;
        break;
      case SandboxMode.regular:
        _enabled = true;
        _autoAllowBash = false;
        break;
      case SandboxMode.disabled:
        _enabled = false;
        _autoAllowBash = false;
        break;
    }
  }

  static Future<void> setAllowUnsandboxedCommands(bool allow) async {
    _allowUnsandboxedCommands = allow;
  }

  // ── Dependency checks ──

  static SandboxDependencyCheck checkDependencies() {
    // Stub: real implementation probes for bwrap, socat, rg, etc.
    return const SandboxDependencyCheck();
  }

  // ── Config queries ──

  static SandboxConfigSnapshot getConfigSnapshot() {
    // Stub: real implementation reads sandbox-adapter config.
    return const SandboxConfigSnapshot();
  }
}

// ────────────────────────────────────────────────────────────────────────────
// TAB ENUM
// ────────────────────────────────────────────────────────────────────────────

/// Tabs for the sandbox settings dialog — mirrors TS Tabs children.
enum SandboxTab {
  mode('Mode'),
  overrides('Overrides'),
  config('Config'),
  dependencies('Dependencies');

  const SandboxTab(this.title);
  final String title;
}

// ────────────────────────────────────────────────────────────────────────────
// CONTROLLER
// ────────────────────────────────────────────────────────────────────────────

class SandboxSettingsController extends SintController {
  final void Function([String? result])? onComplete;

  SandboxSettingsController({this.onComplete});

  // ── Observable state ──
  late final currentTab = SandboxTab.mode.obs;
  late final currentMode = SandboxManagerAdapter.getCurrentMode().obs;
  late final overrideMode = Rx<OverrideMode>(
    SandboxManagerAdapter.areUnsandboxedCommandsAllowed()
        ? OverrideMode.open
        : OverrideMode.closed,
  );
  late final depCheck = SandboxManagerAdapter.checkDependencies().obs;
  late final configSnapshot = SandboxManagerAdapter.getConfigSnapshot().obs;
  late final isLoading = false.obs;
  late final statusMessage = Rxn<String>();
  late final isLockedByPolicy =
      SandboxManagerAdapter.areSandboxSettingsLockedByPolicy().obs;
  late final isSandboxEnabled = SandboxManagerAdapter.isSandboxingEnabled().obs;

  // Derived — available tabs change based on error/warning state.
  List<SandboxTab> get availableTabs {
    final check = depCheck.value;
    if (check.hasErrors) {
      // Only show the Dependencies tab when there are blocking errors.
      return [SandboxTab.dependencies];
    }
    final tabs = <SandboxTab>[SandboxTab.mode];
    if (check.hasWarnings) {
      tabs.add(SandboxTab.dependencies);
    }
    tabs.addAll([SandboxTab.overrides, SandboxTab.config]);
    return tabs;
  }

  // ── Settings queries ──

  bool get showSocketWarning {
    // Mirrors TS: hasWarnings && !allowAllUnixSockets
    return depCheck.value.hasWarnings &&
        configSnapshot.value.allowUnixSockets.isEmpty;
  }

  // ── Actions ──

  Future<void> selectMode(SandboxMode mode) async {
    isLoading.value = true;
    try {
      await SandboxManagerAdapter.setSandboxMode(mode);
      currentMode.value = mode;
      isSandboxEnabled.value = SandboxManagerAdapter.isSandboxingEnabled();
      statusMessage.value = mode.confirmationMessage;
      onComplete?.call(mode.confirmationMessage);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> selectOverrideMode(OverrideMode mode) async {
    isLoading.value = true;
    try {
      await SandboxManagerAdapter.setAllowUnsandboxedCommands(
        mode == OverrideMode.open,
      );
      overrideMode.value = mode;
      statusMessage.value = mode.confirmationMessage;
      onComplete?.call(mode.confirmationMessage);
    } finally {
      isLoading.value = false;
    }
  }

  void dismiss() {
    onComplete?.call();
  }

  void refreshDependencies() {
    depCheck.value = SandboxManagerAdapter.checkDependencies();
    configSnapshot.value = SandboxManagerAdapter.getConfigSnapshot();
  }

  @override
  void onInit() {
    super.onInit();
    refreshDependencies();
  }
}

// ────────────────────────────────────────────────────────────────────────────
// TOP-LEVEL WIDGET — SandboxSettings
// ────────────────────────────────────────────────────────────────────────────

/// Main sandbox settings dialog.
/// Mirrors TS `SandboxSettings` — tabbed pane with Mode, Overrides, Config,
/// Dependencies tabs (tab set varies based on error state).
class SandboxSettings extends StatelessWidget {
  final void Function([String? result])? onComplete;

  const SandboxSettings({super.key, this.onComplete});

  @override
  Widget build(BuildContext context) {
    final controller = Sint.put(
      SandboxSettingsController(onComplete: onComplete),
      tag: 'sandbox_settings',
    );

    return Obx(() {
      final tabs = controller.availableTabs;
      // Ensure current tab is in the available set.
      if (!tabs.contains(controller.currentTab.value)) {
        controller.currentTab.value = tabs.first;
      }

      return Container(
        decoration: BoxDecoration(
          color: ClawColors.darkSurface,
          border: Border.all(color: ClawColors.darkBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Tab bar ──
            _SandboxTabBar(
              tabs: tabs,
              current: controller.currentTab.value,
              onChanged: (tab) => controller.currentTab.value = tab,
            ),
            const Divider(height: 1, color: ClawColors.darkBorder),
            // ── Status banner ──
            if (controller.statusMessage.value != null)
              _StatusBanner(message: controller.statusMessage.value!),
            // ── Tab body ──
            Flexible(child: _tabBody(controller)),
          ],
        ),
      );
    });
  }

  Widget _tabBody(SandboxSettingsController c) {
    switch (c.currentTab.value) {
      case SandboxTab.mode:
        return _SandboxModeTab(controller: c);
      case SandboxTab.overrides:
        return _SandboxOverridesTab(controller: c);
      case SandboxTab.config:
        return _SandboxConfigTab(controller: c);
      case SandboxTab.dependencies:
        return _SandboxDependenciesTab(controller: c);
    }
  }
}

// ────────────────────────────────────────────────────────────────────────────
// TAB BAR
// ────────────────────────────────────────────────────────────────────────────

class _SandboxTabBar extends StatelessWidget {
  final List<SandboxTab> tabs;
  final SandboxTab current;
  final ValueChanged<SandboxTab> onChanged;

  const _SandboxTabBar({
    required this.tabs,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(
            'Sandbox:',
            style: TextStyle(
              color: ClawColors.amber,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 12),
          ...tabs.map((tab) {
            final isActive = tab == current;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                onTap: () => onChanged(tab),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? ClawColors.amber.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: isActive
                        ? Border.all(
                            color: ClawColors.amber.withValues(alpha: 0.4),
                          )
                        : null,
                  ),
                  child: Text(
                    tab.title,
                    style: TextStyle(
                      color: isActive
                          ? ClawColors.amber
                          : ClawColors.darkTextSecondary,
                      fontWeight: isActive
                          ? FontWeight.w600
                          : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// STATUS BANNER
// ────────────────────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final String message;

  const _StatusBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final isSuccess = message.startsWith('✓');
    final color = isSuccess ? ClawColors.codeGreen : ClawColors.amber;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: color.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(
            isSuccess ? Icons.check_circle_outline : Icons.info_outline,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// MODE TAB — mirrors TS SandboxModeTab
// ────────────────────────────────────────────────────────────────────────────

class _SandboxModeTab extends StatelessWidget {
  final SandboxSettingsController controller;

  const _SandboxModeTab({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final current = controller.currentMode.value;

      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Socket warning — mirrors TS showSocketWarning
            if (controller.showSocketWarning)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ClawColors.codeYellow.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: ClawColors.codeYellow.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: ClawColors.codeYellow,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Cannot block unix domain sockets (see Dependencies tab)',
                        style: TextStyle(
                          color: ClawColors.codeYellow,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Header
            const Text(
              'Configure Mode:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: ClawColors.darkTextPrimary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),

            // Mode options — mirrors TS Select with three options
            ...SandboxMode.values.map((mode) {
              final isSelected = mode == current;
              return _ModeOptionTile(
                mode: mode,
                isSelected: isSelected,
                isCurrent: mode == current,
                onTap: () => controller.selectMode(mode),
              );
            }),

            const SizedBox(height: 16),

            // Description — mirrors TS auto-allow description text
            Text(
              'Auto-allow mode: Commands will try to run in the sandbox '
              'automatically, and attempts to run outside of the sandbox '
              'fallback to regular permissions. Explicit ask/deny rules '
              'are always respected.',
              style: TextStyle(
                color: ClawColors.darkTextSecondary.withValues(alpha: 0.7),
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Learn more: code.neomclaw.com/docs/en/sandboxing',
              style: TextStyle(
                color: ClawColors.darkTextSecondary.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// A single mode option tile with radio-style selection.
class _ModeOptionTile extends StatelessWidget {
  final SandboxMode mode;
  final bool isSelected;
  final bool isCurrent;
  final VoidCallback onTap;

  const _ModeOptionTile({
    required this.mode,
    required this.isSelected,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? ClawColors.amber.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected
                  ? ClawColors.amber.withValues(alpha: 0.4)
                  : ClawColors.darkBorder,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: isSelected
                    ? ClawColors.amber
                    : ClawColors.darkTextSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  mode.label,
                  style: TextStyle(
                    color: isSelected
                        ? ClawColors.darkTextPrimary
                        : ClawColors.darkTextSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              if (isCurrent)
                Text(
                  '(current)',
                  style: TextStyle(color: ClawColors.codeGreen, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// OVERRIDES TAB — mirrors TS SandboxOverridesTab + OverridesSelect
// ────────────────────────────────────────────────────────────────────────────

class _SandboxOverridesTab extends StatelessWidget {
  final SandboxSettingsController controller;

  const _SandboxOverridesTab({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Early return: sandbox not enabled
      if (!controller.isSandboxEnabled.value) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Sandbox is not enabled. Enable sandbox to configure override settings.',
            style: TextStyle(color: ClawColors.darkTextSecondary, fontSize: 13),
          ),
        );
      }

      // Early return: locked by policy
      if (controller.isLockedByPolicy.value) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Override settings are managed by a higher-priority configuration '
                'and cannot be changed locally.',
                style: TextStyle(
                  color: ClawColors.darkTextSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Current setting: ${controller.overrideMode.value == OverrideMode.open ? "Allow unsandboxed fallback" : "Strict sandbox mode"}',
                style: TextStyle(
                  color: ClawColors.darkTextSecondary.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      }

      // Normal state: show the override select
      return _OverridesSelectBody(controller: controller);
    });
  }
}

/// The override select body — split out so keyboard focus only runs when
/// the Select renders. Mirrors TS `OverridesSelect` split component.
class _OverridesSelectBody extends StatelessWidget {
  final SandboxSettingsController controller;

  const _OverridesSelectBody({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final current = controller.overrideMode.value;

      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configure Overrides:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: ClawColors.darkTextPrimary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),

            // Override options
            ...OverrideMode.values.map((mode) {
              final isSelected = mode == current;
              return _OverrideOptionTile(
                mode: mode,
                isSelected: isSelected,
                isCurrent: mode == current,
                onTap: () => controller.selectOverrideMode(mode),
              );
            }),
            const SizedBox(height: 16),

            // Descriptions — mirrors the two dimColor text blocks
            _OverrideDescription(
              title: 'Allow unsandboxed fallback:',
              description: OverrideMode.open.description,
            ),
            const SizedBox(height: 12),
            _OverrideDescription(
              title: 'Strict sandbox mode:',
              description: OverrideMode.closed.description,
            ),
            const SizedBox(height: 12),

            Text(
              'Learn more: code.neomclaw.com/docs/en/sandboxing#configure-sandboxing',
              style: TextStyle(
                color: ClawColors.darkTextSecondary.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// A single override option tile.
class _OverrideOptionTile extends StatelessWidget {
  final OverrideMode mode;
  final bool isSelected;
  final bool isCurrent;
  final VoidCallback onTap;

  const _OverrideOptionTile({
    required this.mode,
    required this.isSelected,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? ClawColors.amber.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected
                  ? ClawColors.amber.withValues(alpha: 0.4)
                  : ClawColors.darkBorder,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: isSelected
                    ? ClawColors.amber
                    : ClawColors.darkTextSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  mode.label,
                  style: TextStyle(
                    color: isSelected
                        ? ClawColors.darkTextPrimary
                        : ClawColors.darkTextSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              if (isCurrent)
                Text(
                  '(current)',
                  style: TextStyle(color: ClawColors.codeGreen, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Description block for an override mode.
class _OverrideDescription extends StatelessWidget {
  final String title;
  final String description;

  const _OverrideDescription({required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$title ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: ClawColors.darkTextSecondary.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
          TextSpan(
            text: description,
            style: TextStyle(
              color: ClawColors.darkTextSecondary.withValues(alpha: 0.7),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// CONFIG TAB — mirrors TS SandboxConfigTab
// ────────────────────────────────────────────────────────────────────────────

class _SandboxConfigTab extends StatelessWidget {
  final SandboxSettingsController controller;

  const _SandboxConfigTab({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final depCheck = controller.depCheck.value;
      final warningsNote = depCheck.hasWarnings
          ? _WarningsNote(warnings: depCheck.warnings)
          : null;

      if (!controller.isSandboxEnabled.value) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sandbox is not enabled',
                style: TextStyle(
                  color: ClawColors.darkTextSecondary,
                  fontSize: 13,
                ),
              ),
              ?warningsNote,
            ],
          ),
        );
      }

      final config = controller.configSnapshot.value;

      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Excluded Commands
            _ConfigSection(
              title: 'Excluded Commands:',
              content: config.excludedCommands.isNotEmpty
                  ? config.excludedCommands.join(', ')
                  : 'None',
            ),

            // Filesystem Read Restrictions
            if (config.fsReadConfig.denyOnly.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ConfigSection(
                title: 'Filesystem Read Restrictions:',
                lines: [
                  'Denied: ${config.fsReadConfig.denyOnly.join(', ')}',
                  if (config.fsReadConfig.allowWithinDeny.isNotEmpty)
                    'Allowed within denied: ${config.fsReadConfig.allowWithinDeny.join(', ')}',
                ],
              ),
            ],

            // Filesystem Write Restrictions
            if (config.fsWriteConfig.allowOnly.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ConfigSection(
                title: 'Filesystem Write Restrictions:',
                lines: [
                  'Allowed: ${config.fsWriteConfig.allowOnly.join(', ')}',
                  if (config.fsWriteConfig.denyWithinAllow.isNotEmpty)
                    'Denied within allowed: ${config.fsWriteConfig.denyWithinAllow.join(', ')}',
                ],
              ),
            ],

            // Network Restrictions
            if (config.networkConfig.hasRestrictions) ...[
              const SizedBox(height: 12),
              _ConfigSection(
                title: config.isManagedDomainsOnly
                    ? 'Network Restrictions (Managed):'
                    : 'Network Restrictions:',
                lines: [
                  if (config.networkConfig.allowedHosts.isNotEmpty)
                    'Allowed: ${config.networkConfig.allowedHosts.join(', ')}',
                  if (config.networkConfig.deniedHosts.isNotEmpty)
                    'Denied: ${config.networkConfig.deniedHosts.join(', ')}',
                ],
              ),
            ],

            // Allowed Unix Sockets
            if (config.allowUnixSockets.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ConfigSection(
                title: 'Allowed Unix Sockets:',
                content: config.allowUnixSockets.join(', '),
              ),
            ],

            // Glob pattern warnings (Linux)
            if (config.globPatternWarnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              _GlobPatternWarning(warnings: config.globPatternWarnings),
            ],

            // General warnings note
            if (warningsNote != null) ...[
              const SizedBox(height: 12),
              warningsNote,
            ],
          ],
        ),
      );
    });
  }
}

/// A titled section in the Config tab.
class _ConfigSection extends StatelessWidget {
  final String title;
  final String? content;
  final List<String>? lines;

  const _ConfigSection({required this.title, this.content, this.lines});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: ClawColors.amber,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        if (content != null)
          Text(
            content!,
            style: TextStyle(
              color: ClawColors.darkTextSecondary.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
        if (lines != null)
          ...lines!.map(
            (line) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                line,
                style: TextStyle(
                  color: ClawColors.darkTextSecondary.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Glob pattern warning block — mirrors TS glob pattern warning section.
class _GlobPatternWarning extends StatelessWidget {
  final List<String> warnings;

  const _GlobPatternWarning({required this.warnings});

  @override
  Widget build(BuildContext context) {
    final displayed = warnings.take(3).toList();
    final remaining = warnings.length - displayed.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 14,
              color: ClawColors.codeYellow,
            ),
            const SizedBox(width: 6),
            Text(
              'Warning: Glob patterns not fully supported on Linux',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: ClawColors.codeYellow,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'The following patterns will be ignored: '
          '${displayed.join(', ')}'
          '${remaining > 0 ? ' ($remaining more)' : ''}',
          style: TextStyle(
            color: ClawColors.darkTextSecondary.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

/// Renders dependency check warnings.
class _WarningsNote extends StatelessWidget {
  final List<String> warnings;

  const _WarningsNote({required this.warnings});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: warnings
            .map(
              (w) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  w,
                  style: TextStyle(
                    color: ClawColors.darkTextSecondary.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// DEPENDENCIES TAB — mirrors TS SandboxDependenciesTab
// ────────────────────────────────────────────────────────────────────────────

class _SandboxDependenciesTab extends StatelessWidget {
  final SandboxSettingsController controller;

  const _SandboxDependenciesTab({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final check = controller.depCheck.value;
      final isMac = Platform.isMacOS;

      // Detect specific missing dependencies — mirrors TS logic
      final rgMissing = check.errors.any((e) => e.contains('ripgrep'));
      final bwrapMissing = check.errors.any((e) => e.contains('bwrap'));
      final socatMissing = check.errors.any((e) => e.contains('socat'));
      final seccompMissing = check.hasWarnings;
      final otherErrors = check.errors
          .where(
            (e) =>
                !e.contains('ripgrep') &&
                !e.contains('bwrap') &&
                !e.contains('socat'),
          )
          .toList();

      final rgInstallHint = isMac
          ? 'brew install ripgrep'
          : 'apt install ripgrep';

      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // macOS: seatbelt built-in
            if (isMac)
              _DependencyRow(
                name: 'seatbelt',
                status: 'built-in (macOS)',
                isOk: true,
              ),

            // ripgrep
            _DependencyRow(
              name: 'ripgrep (rg)',
              status: rgMissing ? 'not found' : 'found',
              isOk: !rgMissing,
              hint: rgMissing ? rgInstallHint : null,
            ),

            // Linux-only dependencies
            if (!isMac) ...[
              _DependencyRow(
                name: 'bubblewrap (bwrap)',
                status: bwrapMissing ? 'not installed' : 'installed',
                isOk: !bwrapMissing,
                hint: bwrapMissing ? 'apt install bubblewrap' : null,
              ),
              _DependencyRow(
                name: 'socat',
                status: socatMissing ? 'not installed' : 'installed',
                isOk: !socatMissing,
                hint: socatMissing ? 'apt install socat' : null,
              ),
              _SeccompDependencyRow(isMissing: seccompMissing),
            ],

            // Other errors
            ...otherErrors.map(
              (err) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  err,
                  style: TextStyle(color: ClawColors.codeRed, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// A single dependency status row.
class _DependencyRow extends StatelessWidget {
  final String name;
  final String status;
  final bool isOk;
  final String? hint;

  const _DependencyRow({
    required this.name,
    required this.status,
    required this.isOk,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = isOk ? ClawColors.codeGreen : ClawColors.codeRed;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$name: ',
                  style: const TextStyle(
                    color: ClawColors.darkTextPrimary,
                    fontSize: 13,
                  ),
                ),
                TextSpan(
                  text: status,
                  style: TextStyle(color: statusColor, fontSize: 13),
                ),
              ],
            ),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 2),
              child: Text(
                '· $hint',
                style: TextStyle(
                  color: ClawColors.darkTextSecondary.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Seccomp dependency row with multi-line install hints — mirrors TS.
class _SeccompDependencyRow extends StatelessWidget {
  final bool isMissing;

  const _SeccompDependencyRow({required this.isMissing});

  @override
  Widget build(BuildContext context) {
    final statusColor = isMissing
        ? ClawColors.codeYellow
        : ClawColors.codeGreen;
    final statusText = isMissing ? 'not installed' : 'installed';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              children: [
                const TextSpan(
                  text: 'seccomp filter: ',
                  style: TextStyle(
                    color: ClawColors.darkTextPrimary,
                    fontSize: 13,
                  ),
                ),
                TextSpan(
                  text: statusText,
                  style: TextStyle(color: statusColor, fontSize: 13),
                ),
                if (isMissing)
                  TextSpan(
                    text: ' (required to block unix domain sockets)',
                    style: TextStyle(
                      color: ClawColors.darkTextSecondary.withValues(
                        alpha: 0.7,
                      ),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          if (isMissing) ...[
            _HintLine('· npm install -g @anthropic-ai/sandbox-runtime'),
            _HintLine(
              '· or copy vendor/seccomp/* from sandbox-runtime and set',
            ),
            _HintLine(
              '  sandbox.seccomp.bpfPath and applyPath in settings.json',
            ),
          ],
        ],
      ),
    );
  }
}

/// A single dimmed hint line.
class _HintLine extends StatelessWidget {
  final String text;

  const _HintLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 2),
      child: Text(
        text,
        style: TextStyle(
          color: ClawColors.darkTextSecondary.withValues(alpha: 0.7),
          fontSize: 12,
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// DOCTOR SECTION — mirrors TS SandboxDoctorSection
// ────────────────────────────────────────────────────────────────────────────

/// Standalone sandbox doctor diagnostics widget — shown in the status/
/// diagnostics area outside the settings dialog. Returns `SizedBox.shrink()`
/// when sandbox is unsupported, not enabled, or all dependencies are clean.
class SandboxDoctorSection extends StatelessWidget {
  const SandboxDoctorSection({super.key});

  @override
  Widget build(BuildContext context) {
    if (!SandboxManagerAdapter.isSupportedPlatform()) {
      return const SizedBox.shrink();
    }
    if (!SandboxManagerAdapter.isSandboxEnabledInSettings()) {
      return const SizedBox.shrink();
    }

    final depCheck = SandboxManagerAdapter.checkDependencies();
    if (depCheck.isClean) {
      return const SizedBox.shrink();
    }

    final statusColor = depCheck.hasErrors
        ? ClawColors.codeRed
        : ClawColors.codeYellow;
    final statusText = depCheck.hasErrors
        ? 'Missing dependencies'
        : 'Available (with warnings)';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sandbox',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: ClawColors.darkTextPrimary,
              fontSize: 13,
            ),
          ),
          Row(
            children: [
              const Text(
                '└ Status: ',
                style: TextStyle(
                  color: ClawColors.darkTextPrimary,
                  fontSize: 13,
                ),
              ),
              Text(
                statusText,
                style: TextStyle(color: statusColor, fontSize: 13),
              ),
            ],
          ),
          // Errors
          ...depCheck.errors.map(
            (e) => Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '└ $e',
                style: TextStyle(color: ClawColors.codeRed, fontSize: 13),
              ),
            ),
          ),
          // Warnings
          ...depCheck.warnings.map(
            (w) => Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '└ $w',
                style: TextStyle(color: ClawColors.codeYellow, fontSize: 13),
              ),
            ),
          ),
          // Install hint
          if (depCheck.hasErrors)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '└ Run /sandbox for install instructions',
                style: TextStyle(
                  color: ClawColors.darkTextSecondary.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
