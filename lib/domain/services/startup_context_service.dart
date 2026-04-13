import '../models/startup_context_config.dart';
import '../models/startup_context_result.dart';

/// Service contract for startup context injection.
///
/// Implementations load relevant memory and context at the
/// beginning of a session, assembling a prelude that primes
/// the agent with recent knowledge.
abstract class StartupContextService {
  /// Assemble startup context for the given session action.
  ///
  /// Returns null if startup context is disabled or the action
  /// doesn't trigger injection.
  Future<StartupContextResult?> assemble({
    required String action,
    required StartupContextConfig config,
    String? timezone,
  });

  /// Whether startup context should apply for the given action.
  bool shouldApply(String action, StartupContextConfig config) {
    return config.enabled && config.applyOn.contains(action);
  }
}
