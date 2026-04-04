// Teleport view — comprehensive port of openneomclaw/src/utils/teleport.tsx
// and openneomclaw/src/utils/teleport/*.ts.
// Remote session / teleport UI with Flutter widgets and Sint reactive state.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sint/sint.dart';

// ════════════════════════════════════════════════════════════════════════════
// Teleport types and enums
// ════════════════════════════════════════════════════════════════════════════

/// Session status from the Sessions API.
enum SessionStatus { requiresAction, running, idle, archived }

/// Progress steps during teleport operations.
enum TeleportProgressStep {
  validating,
  fetchingLogs,
  fetchingBranch,
  checkingOut,
  creatingSession,
  uploadingBundle,
  done,
}

/// Result of repository validation for teleport.
enum RepoValidationStatus { match, mismatch, notInRepo, noRepoRequired, error }

/// Kind of remote environment.
enum EnvironmentKind { anthropicCloud, byoc, bridge }

/// State of a remote environment.
enum EnvironmentState { active }

/// Scope of a git bundle (all refs, HEAD only, or squashed to single commit).
enum BundleScope { all, head, squashed }

/// Reason a git bundle failed.
enum BundleFailReason { gitError, tooLarge, emptyRepo }

// ════════════════════════════════════════════════════════════════════════════
// Data models
// ════════════════════════════════════════════════════════════════════════════

/// A remote environment resource.
class EnvironmentResource {
  final EnvironmentKind kind;
  final String environmentId;
  final String name;
  final String createdAt;
  final EnvironmentState state;

  const EnvironmentResource({
    required this.kind,
    required this.environmentId,
    required this.name,
    required this.createdAt,
    required this.state,
  });

  factory EnvironmentResource.fromJson(Map<String, dynamic> json) {
    return EnvironmentResource(
      kind: _parseEnvironmentKind(json['kind'] as String),
      environmentId: json['environment_id'] as String,
      name: json['name'] as String,
      createdAt: json['created_at'] as String,
      state: EnvironmentState.active,
    );
  }
}

EnvironmentKind _parseEnvironmentKind(String kind) => switch (kind) {
      'anthropic_cloud' => EnvironmentKind.anthropicCloud,
      'byoc' => EnvironmentKind.byoc,
      'bridge' => EnvironmentKind.bridge,
      _ => EnvironmentKind.anthropicCloud,
    };

/// Session context sources.
sealed class SessionContextSource {
  const SessionContextSource();
}

class GitSource extends SessionContextSource {
  final String url;
  final String? revision;
  final bool allowUnrestrictedGitPush;

  const GitSource({
    required this.url,
    this.revision,
    this.allowUnrestrictedGitPush = false,
  });

  factory GitSource.fromJson(Map<String, dynamic> json) {
    return GitSource(
      url: json['url'] as String,
      revision: json['revision'] as String?,
      allowUnrestrictedGitPush:
          json['allow_unrestricted_git_push'] as bool? ?? false,
    );
  }
}

class KnowledgeBaseSource extends SessionContextSource {
  final String knowledgeBaseId;

  const KnowledgeBaseSource({required this.knowledgeBaseId});

  factory KnowledgeBaseSource.fromJson(Map<String, dynamic> json) {
    return KnowledgeBaseSource(
      knowledgeBaseId: json['knowledge_base_id'] as String,
    );
  }
}

/// Outcome types for git repositories.
class GitRepositoryOutcome {
  final String repo;
  final List<String> branches;

  const GitRepositoryOutcome({required this.repo, required this.branches});

  factory GitRepositoryOutcome.fromJson(Map<String, dynamic> json) {
    final gitInfo = json['git_info'] as Map<String, dynamic>;
    return GitRepositoryOutcome(
      repo: gitInfo['repo'] as String,
      branches: (gitInfo['branches'] as List).cast<String>(),
    );
  }
}

/// Session context containing sources, cwd, and outcomes.
class SessionContext {
  final List<SessionContextSource> sources;
  final String cwd;
  final List<GitRepositoryOutcome>? outcomes;
  final String? customSystemPrompt;
  final String? appendSystemPrompt;
  final String? model;
  final String? seedBundleFileId;

  const SessionContext({
    required this.sources,
    required this.cwd,
    this.outcomes,
    this.customSystemPrompt,
    this.appendSystemPrompt,
    this.model,
    this.seedBundleFileId,
  });

  factory SessionContext.fromJson(Map<String, dynamic> json) {
    final sources = <SessionContextSource>[];
    for (final s in (json['sources'] as List?) ?? []) {
      final src = s as Map<String, dynamic>;
      if (src['type'] == 'git_repository') {
        sources.add(GitSource.fromJson(src));
      } else if (src['type'] == 'knowledge_base') {
        sources.add(KnowledgeBaseSource.fromJson(src));
      }
    }
    final outcomes = <GitRepositoryOutcome>[];
    for (final o in (json['outcomes'] as List?) ?? []) {
      final out = o as Map<String, dynamic>;
      if (out['type'] == 'git_repository') {
        outcomes.add(GitRepositoryOutcome.fromJson(out));
      }
    }
    return SessionContext(
      sources: sources,
      cwd: json['cwd'] as String? ?? '/home/user',
      outcomes: outcomes.isEmpty ? null : outcomes,
      customSystemPrompt: json['custom_system_prompt'] as String?,
      appendSystemPrompt: json['append_system_prompt'] as String?,
      model: json['model'] as String?,
      seedBundleFileId: json['seed_bundle_file_id'] as String?,
    );
  }
}

/// A session resource from the Sessions API.
class SessionResource {
  final String id;
  final String? title;
  final SessionStatus sessionStatus;
  final String environmentId;
  final String createdAt;
  final String updatedAt;
  final SessionContext sessionContext;

  const SessionResource({
    required this.id,
    this.title,
    required this.sessionStatus,
    required this.environmentId,
    required this.createdAt,
    required this.updatedAt,
    required this.sessionContext,
  });

  factory SessionResource.fromJson(Map<String, dynamic> json) {
    return SessionResource(
      id: json['id'] as String,
      title: json['title'] as String?,
      sessionStatus: _parseSessionStatus(json['session_status'] as String),
      environmentId: json['environment_id'] as String,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
      sessionContext:
          SessionContext.fromJson(json['session_context'] as Map<String, dynamic>),
    );
  }

  /// Extracts the first branch name from session's git repository outcomes.
  String? get branch {
    final gitOutcome = sessionContext.outcomes?.firstWhere(
      (_) => true,
      orElse: () => const GitRepositoryOutcome(repo: '', branches: []),
    );
    return (gitOutcome?.branches.isNotEmpty ?? false) ? gitOutcome!.branches.first : null;
  }
}

SessionStatus _parseSessionStatus(String status) => switch (status) {
      'requires_action' => SessionStatus.requiresAction,
      'running' => SessionStatus.running,
      'idle' => SessionStatus.idle,
      'archived' => SessionStatus.archived,
      _ => SessionStatus.idle,
    };

/// A code session (simplified view for lists).
class CodeSession {
  final String id;
  final String title;
  final String description;
  final String status;
  final String? repoName;
  final String? repoOwner;
  final String? defaultBranch;
  final String createdAt;
  final String updatedAt;

  const CodeSession({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    this.repoName,
    this.repoOwner,
    this.defaultBranch,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CodeSession.fromSessionResource(SessionResource session) {
    String? repoName;
    String? repoOwner;
    String? defaultBranch;
    final gitSource = session.sessionContext.sources
        .whereType<GitSource>()
        .firstOrNull;
    if (gitSource != null) {
      final parts = _parseRepoFromUrl(gitSource.url);
      if (parts != null) {
        repoOwner = parts.$1;
        repoName = parts.$2;
        defaultBranch = gitSource.revision;
      }
    }
    return CodeSession(
      id: session.id,
      title: session.title ?? 'Untitled',
      description: '',
      status: session.sessionStatus.name,
      repoName: repoName,
      repoOwner: repoOwner,
      defaultBranch: defaultBranch,
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
    );
  }
}

(String, String)? _parseRepoFromUrl(String url) {
  // Match github.com URLs (HTTPS or SSH).
  final httpsMatch = RegExp(r'github\.com[/:]([^/]+)/([^/.]+)').firstMatch(url);
  if (httpsMatch != null) {
    return (httpsMatch.group(1)!, httpsMatch.group(2)!);
  }
  return null;
}

/// Result of repo validation for teleport.
class RepoValidationResult {
  final RepoValidationStatus status;
  final String? sessionRepo;
  final String? currentRepo;
  final String? sessionHost;
  final String? currentHost;
  final String? errorMessage;

  const RepoValidationResult({
    required this.status,
    this.sessionRepo,
    this.currentRepo,
    this.sessionHost,
    this.currentHost,
    this.errorMessage,
  });
}

/// Result of the teleport operation.
class TeleportResult {
  final List<dynamic> messages;
  final String? branchName;

  const TeleportResult({required this.messages, this.branchName});
}

/// Result of a git bundle upload.
sealed class BundleUploadResult {
  const BundleUploadResult();
}

class BundleUploadSuccess extends BundleUploadResult {
  final String fileId;
  final int bundleSizeBytes;
  final BundleScope scope;
  final bool hasWip;

  const BundleUploadSuccess({
    required this.fileId,
    required this.bundleSizeBytes,
    required this.scope,
    required this.hasWip,
  });
}

class BundleUploadFailure extends BundleUploadResult {
  final String error;
  final BundleFailReason? failReason;

  const BundleUploadFailure({required this.error, this.failReason});
}

/// Information about environment selection.
class EnvironmentSelectionInfo {
  final List<EnvironmentResource> availableEnvironments;
  final EnvironmentResource? selectedEnvironment;
  final String? selectedEnvironmentSource;

  const EnvironmentSelectionInfo({
    required this.availableEnvironments,
    this.selectedEnvironment,
    this.selectedEnvironmentSource,
  });
}

/// Types of local teleport errors.
enum TeleportLocalErrorType {
  needsLogin,
  needsGitStash,
  needsGitRepo,
  needsGithubApp,
}

// ════════════════════════════════════════════════════════════════════════════
// Retry configuration
// ════════════════════════════════════════════════════════════════════════════

/// Retry delays for teleport API requests (exponential backoff).
const List<Duration> teleportRetryDelays = [
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 16),
];

/// Maximum default bundle size (100 MB).
const int defaultBundleMaxBytes = 100 * 1024 * 1024;

// ════════════════════════════════════════════════════════════════════════════
// TeleportController — reactive state management with Sint
// ════════════════════════════════════════════════════════════════════════════

/// Controller for teleport / remote session operations.
class TeleportController extends SintController {
  // ── Observable state ──
  final isLoading = false.obs;
  final progressStep = Rx<TeleportProgressStep?>(null);
  final progressMessage = ''.obs;
  final errorMessage = Rx<String?>(null);
  final sessions = <CodeSession>[].obs;
  final selectedSessionId = Rx<String?>(null);
  final environments = <EnvironmentResource>[].obs;
  final selectedEnvironment = Rx<EnvironmentResource?>(null);
  final isPolling = false.obs;
  final sessionStatus = Rx<SessionStatus?>(null);
  final lastEventId = Rx<String?>(null);
  final localErrors = <TeleportLocalErrorType>{}.obs;
  final repoValidation = Rx<RepoValidationResult?>(null);

  Timer? _pollTimer;

  @override
  void onClose() {
    _pollTimer?.cancel();
    super.onClose();
  }

  /// Update progress with a step and optional message.
  void setProgress(TeleportProgressStep step, [String message = '']) {
    progressStep.value = step;
    progressMessage.value = message;
  }

  /// Clear any error state.
  void clearError() => errorMessage.value = null;

  /// Set error message and stop loading.
  void setError(String message) {
    errorMessage.value = message;
    isLoading.value = false;
    progressStep.value = null;
  }

  /// Start polling for remote session events.
  void startPolling(String sessionId, {Duration interval = const Duration(seconds: 3)}) {
    _pollTimer?.cancel();
    isPolling.value = true;
    selectedSessionId.value = sessionId;
    _pollTimer = Timer.periodic(interval, (_) {
      // In a real implementation, this would call pollRemoteSessionEvents.
      // The actual API call would be injected via a service/repository pattern.
    });
  }

  /// Stop polling.
  void stopPolling() {
    _pollTimer?.cancel();
    isPolling.value = false;
  }

  /// Select an environment by ID.
  void selectEnvironment(String environmentId) {
    final env = environments.firstWhereOrNull(
      (e) => e.environmentId == environmentId,
    );
    if (env != null) {
      selectedEnvironment.value = env;
    }
  }

  /// Determine the display label for the selected environment.
  String get environmentLabel {
    final env = selectedEnvironment.value;
    if (env == null) return 'Default';
    return switch (env.kind) {
      EnvironmentKind.anthropicCloud => 'Cloud (${env.name})',
      EnvironmentKind.byoc => 'BYOC (${env.name})',
      EnvironmentKind.bridge => 'Bridge (${env.name})',
    };
  }

  /// Format a progress step for display.
  String get progressLabel => switch (progressStep.value) {
        TeleportProgressStep.validating => 'Validating...',
        TeleportProgressStep.fetchingLogs => 'Fetching session logs...',
        TeleportProgressStep.fetchingBranch => 'Fetching branch...',
        TeleportProgressStep.checkingOut => 'Checking out branch...',
        TeleportProgressStep.creatingSession => 'Creating remote session...',
        TeleportProgressStep.uploadingBundle => 'Uploading git bundle...',
        TeleportProgressStep.done => 'Done',
        null => '',
      };
}

// ════════════════════════════════════════════════════════════════════════════
// TeleportView — main teleport UI widget
// ════════════════════════════════════════════════════════════════════════════

/// Main teleport / remote session view widget.
class TeleportView extends StatelessWidget {
  const TeleportView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Sint.find<TeleportController>();
    final theme = Theme.of(context);

    return Obx(() {
      // Show error state.
      if (controller.errorMessage.value != null) {
        return _TeleportErrorView(
          message: controller.errorMessage.value!,
          localErrors: controller.localErrors.toSet(),
          onRetry: () {
            controller.clearError();
            controller.localErrors.clear();
          },
          onDismiss: () => Navigator.of(context).maybePop(),
        );
      }

      // Show loading / progress.
      if (controller.isLoading.value) {
        return _TeleportProgressView(
          step: controller.progressStep.value,
          message: controller.progressMessage.value,
          label: controller.progressLabel,
        );
      }

      // Show session list or polling state.
      if (controller.isPolling.value) {
        return _TeleportPollingView(
          sessionId: controller.selectedSessionId.value ?? '',
          sessionStatus: controller.sessionStatus.value,
          onStop: () => controller.stopPolling(),
        );
      }

      // Default: session selection view.
      return _TeleportSessionListView(
        sessions: controller.sessions,
        environments: controller.environments,
        selectedEnvironment: controller.selectedEnvironment.value,
        onSelectSession: (id) => controller.selectedSessionId.value = id,
        onSelectEnvironment: (id) => controller.selectEnvironment(id),
        repoValidation: controller.repoValidation.value,
      );
    });
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Sub-views
// ════════════════════════════════════════════════════════════════════════════

/// Error view for teleport errors.
class _TeleportErrorView extends StatelessWidget {
  final String message;
  final Set<TeleportLocalErrorType> localErrors;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  const _TeleportErrorView({
    required this.message,
    required this.localErrors,
    required this.onRetry,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error, size: 20),
                const SizedBox(width: 8),
                Text('Teleport Error',
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            Text(message, style: theme.textTheme.bodyMedium),
            if (localErrors.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...localErrors.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber, size: 16,
                            color: theme.colorScheme.error.withValues(alpha: 0.7)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _localErrorMessage(e),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
                const SizedBox(width: 8),
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _localErrorMessage(TeleportLocalErrorType type) => switch (type) {
        TeleportLocalErrorType.needsLogin =>
          'Authentication required. Run /login to authenticate.',
        TeleportLocalErrorType.needsGitStash =>
          'Git working directory is not clean. Commit or stash changes.',
        TeleportLocalErrorType.needsGitRepo =>
          'Not in a git repository. Navigate to a repo first.',
        TeleportLocalErrorType.needsGithubApp =>
          'GitHub app not installed for this repository.',
      };
}

/// Progress view showing teleport operation status.
class _TeleportProgressView extends StatelessWidget {
  final TeleportProgressStep? step;
  final String message;
  final String label;

  const _TeleportProgressView({
    required this.step,
    required this.message,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = TeleportProgressStep.values;
    final currentIndex = step != null ? steps.indexOf(step!) : -1;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(label,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(message,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 16),
            // Step indicators.
            ...List.generate(steps.length, (i) {
              final isDone = i < currentIndex;
              final isCurrent = i == currentIndex;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      isDone
                          ? Icons.check_circle
                          : isCurrent
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                      size: 16,
                      color: isDone
                          ? theme.colorScheme.primary
                          : isCurrent
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _stepLabel(steps[i]),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isCurrent
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: isCurrent ? FontWeight.w600 : null,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _stepLabel(TeleportProgressStep step) => switch (step) {
        TeleportProgressStep.validating => 'Validate prerequisites',
        TeleportProgressStep.fetchingLogs => 'Fetch session logs',
        TeleportProgressStep.fetchingBranch => 'Fetch branch info',
        TeleportProgressStep.checkingOut => 'Check out branch',
        TeleportProgressStep.creatingSession => 'Create remote session',
        TeleportProgressStep.uploadingBundle => 'Upload git bundle',
        TeleportProgressStep.done => 'Complete',
      };
}

/// Polling view for monitoring active remote sessions.
class _TeleportPollingView extends StatelessWidget {
  final String sessionId;
  final SessionStatus? sessionStatus;
  final VoidCallback onStop;

  const _TeleportPollingView({
    required this.sessionId,
    this.sessionStatus,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text('Remote Session Active',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            _InfoRow(label: 'Session', value: sessionId),
            if (sessionStatus != null)
              _InfoRow(label: 'Status', value: _statusLabel(sessionStatus!)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.stop, size: 18),
              label: const Text('Stop Monitoring'),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(SessionStatus status) => switch (status) {
        SessionStatus.requiresAction => 'Requires Action',
        SessionStatus.running => 'Running',
        SessionStatus.idle => 'Idle',
        SessionStatus.archived => 'Archived',
      };
}

/// Session list view for selecting / creating remote sessions.
class _TeleportSessionListView extends StatelessWidget {
  final List<CodeSession> sessions;
  final List<EnvironmentResource> environments;
  final EnvironmentResource? selectedEnvironment;
  final ValueChanged<String> onSelectSession;
  final ValueChanged<String> onSelectEnvironment;
  final RepoValidationResult? repoValidation;

  const _TeleportSessionListView({
    required this.sessions,
    required this.environments,
    this.selectedEnvironment,
    required this.onSelectSession,
    required this.onSelectEnvironment,
    this.repoValidation,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header.
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.cloud_outlined,
                  color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Text('Remote Sessions',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),

        // Repo validation warning.
        if (repoValidation != null &&
            repoValidation!.status == RepoValidationStatus.mismatch)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber,
                    size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Repository mismatch: session is for ${repoValidation!.sessionRepo}, '
                    'but current repo is ${repoValidation!.currentRepo}.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
          ),

        // Environment selector.
        if (environments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _EnvironmentSelector(
              environments: environments,
              selected: selectedEnvironment,
              onSelect: onSelectEnvironment,
            ),
          ),

        const Divider(height: 1),

        // Session list.
        Expanded(
          child: sessions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.3)),
                      const SizedBox(height: 12),
                      Text('No remote sessions',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    return _SessionTile(
                      session: session,
                      onTap: () => onSelectSession(session.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Reusable sub-widgets
// ════════════════════════════════════════════════════════════════════════════

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final CodeSession session;
  final VoidCallback onTap;

  const _SessionTile({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = switch (session.status) {
      'running' => Colors.green,
      'idle' => theme.colorScheme.onSurfaceVariant,
      'requires_action' => Colors.orange,
      'archived' => theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      _ => theme.colorScheme.onSurfaceVariant,
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      session.title,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _formatDate(session.updatedAt),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              if (session.repoOwner != null && session.repoName != null)
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 4),
                  child: Text(
                    '${session.repoOwner}/${session.repoName}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return iso;
    }
  }
}

class _EnvironmentSelector extends StatelessWidget {
  final List<EnvironmentResource> environments;
  final EnvironmentResource? selected;
  final ValueChanged<String> onSelect;

  const _EnvironmentSelector({
    required this.environments,
    this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text('Environment:',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isDense: true,
              isExpanded: true,
              value: selected?.environmentId ?? environments.first.environmentId,
              style: theme.textTheme.bodySmall,
              items: environments.map((env) {
                final kindLabel = switch (env.kind) {
                  EnvironmentKind.anthropicCloud => 'Cloud',
                  EnvironmentKind.byoc => 'BYOC',
                  EnvironmentKind.bridge => 'Bridge',
                };
                return DropdownMenuItem(
                  value: env.environmentId,
                  child: Text('$kindLabel: ${env.name}'),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) onSelect(value);
              },
            ),
          ),
        ),
      ],
    );
  }
}
