// Tips service — port of neom_claw/src/services/tips.
// Shows contextual tips during spinner/loading states.

/// A tip that can be shown to the user.
class Tip {
  final String id;
  final String Function() content;
  final int cooldownSessions;
  final bool Function()? isRelevant;

  const Tip({
    required this.id,
    required this.content,
    this.cooldownSessions = 5,
    this.isRelevant,
  });
}

/// History tracking for tip display.
class TipHistory {
  final Map<String, int> _lastShownAt = {};
  int _currentSession = 0;

  /// Set the current session number.
  set currentSession(int session) => _currentSession = session;

  /// Record that a tip was shown.
  void recordShown(String tipId) {
    _lastShownAt[tipId] = _currentSession;
  }

  /// Sessions since tip was last shown. Returns a large number if never shown.
  int sessionsSinceShown(String tipId) {
    final lastShown = _lastShownAt[tipId];
    if (lastShown == null) return 999;
    return _currentSession - lastShown;
  }

  /// Load history from stored data.
  void loadFrom(Map<String, int> data) {
    _lastShownAt.addAll(data);
  }

  /// Export history for storage.
  Map<String, int> export() => Map.from(_lastShownAt);
}

/// Tips service — manages tip selection and display.
class TipsService {
  final TipHistory history;
  final List<Tip> _tips;
  bool enabled;

  TipsService({
    required this.history,
    List<Tip>? tips,
    this.enabled = true,
  }) : _tips = tips ?? defaultTips;

  /// Get a tip to show on spinner, or null if none applicable.
  Tip? getTipForSpinner() {
    if (!enabled) return null;

    final eligible = _tips.where((tip) {
      // Check cooldown
      if (history.sessionsSinceShown(tip.id) < tip.cooldownSessions) {
        return false;
      }
      // Check relevance
      if (tip.isRelevant != null && !tip.isRelevant!()) {
        return false;
      }
      return true;
    }).toList();

    if (eligible.isEmpty) return null;

    // Pick the tip with the longest time since last shown
    eligible.sort((a, b) {
      final aSince = history.sessionsSinceShown(a.id);
      final bSince = history.sessionsSinceShown(b.id);
      return bSince.compareTo(aSince);
    });

    final tip = eligible.first;
    history.recordShown(tip.id);
    return tip;
  }

  /// Register a custom tip.
  void addTip(Tip tip) => _tips.add(tip);
}

/// Default built-in tips.
final List<Tip> defaultTips = [
  Tip(
    id: 'plan_mode',
    content: () => 'Tip: Use /plan to toggle plan mode — think before acting.',
    cooldownSessions: 10,
  ),
  Tip(
    id: 'memory',
    content: () => 'Tip: Use /memory to manage persistent memory across sessions.',
    cooldownSessions: 10,
  ),
  Tip(
    id: 'compact',
    content: () => 'Tip: Use /compact to free up context space while keeping a summary.',
    cooldownSessions: 8,
  ),
  Tip(
    id: 'context',
    content: () => 'Tip: Use /context to check how much of the context window you\'re using.',
    cooldownSessions: 8,
  ),
  Tip(
    id: 'model_switch',
    content: () => 'Tip: Use /model to switch between different models on the fly.',
    cooldownSessions: 10,
  ),
  Tip(
    id: 'keyboard_shortcuts',
    content: () => 'Tip: Press Escape to interrupt the current operation.',
    cooldownSessions: 15,
  ),
  Tip(
    id: 'cost',
    content: () => 'Tip: Use /cost to see your session\'s token usage.',
    cooldownSessions: 12,
  ),
  Tip(
    id: 'commit',
    content: () => 'Tip: Use /commit to create a git commit with an AI-generated message.',
    cooldownSessions: 8,
  ),
  Tip(
    id: 'review',
    content: () => 'Tip: Use /review to get a code review of your changes or a PR.',
    cooldownSessions: 10,
  ),
  Tip(
    id: 'help',
    content: () => 'Tip: Use /help to see all available commands.',
    cooldownSessions: 20,
  ),
];
