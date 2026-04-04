// Buddy system — port of neom_claw/src/buddy/.
// Provides contextual help, tips, and guided assistance via an animated
// avatar with a suggestion popup queue.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Enums ──────────────────────────────────────────────────────────────────

/// Visual & logical state of the buddy avatar.
enum BuddyState {
  /// No suggestion active — avatar is calm.
  idle,

  /// Processing context to generate a suggestion.
  thinking,

  /// A suggestion is being displayed.
  suggesting,

  /// Actively walking the user through something.
  helping,

  /// Celebrating a milestone (first commit, session complete, etc.).
  celebrating,
}

/// Tone / verbosity of buddy suggestions.
enum BuddyPersonality {
  helpful,
  concise,
  detailed,
  playful,
}

/// Semantic category of a suggestion.
enum SuggestionCategory {
  tip,
  shortcut,
  warning,
  encouragement,
}

// ── Data classes ───────────────────────────────────────────────────────────

/// A single suggestion the buddy can show.
class BuddySuggestion {
  final String text;
  final SuggestionCategory category;
  final int priority;
  final bool dismissible;
  final DateTime createdAt;

  BuddySuggestion({
    required this.text,
    required this.category,
    this.priority = 0,
    this.dismissible = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

/// Configuration for the buddy system.
class BuddyConfig {
  final BuddyPersonality personality;
  final bool enabled;
  final bool showTips;
  final bool showShortcuts;
  final int maxSuggestionsPerSession;

  const BuddyConfig({
    this.personality = BuddyPersonality.helpful,
    this.enabled = true,
    this.showTips = true,
    this.showShortcuts = true,
    this.maxSuggestionsPerSession = 20,
  });

  BuddyConfig copyWith({
    BuddyPersonality? personality,
    bool? enabled,
    bool? showTips,
    bool? showShortcuts,
    int? maxSuggestionsPerSession,
  }) {
    return BuddyConfig(
      personality: personality ?? this.personality,
      enabled: enabled ?? this.enabled,
      showTips: showTips ?? this.showTips,
      showShortcuts: showShortcuts ?? this.showShortcuts,
      maxSuggestionsPerSession:
          maxSuggestionsPerSession ?? this.maxSuggestionsPerSession,
    );
  }
}

// ── BuddyService ──────────────────────────────────────────────────────────

/// User action events the buddy tracks to provide relevant tips.
enum UserAction {
  firstMessage,
  sentMessage,
  receivedError,
  usedTool,
  longSession,
  switchedModel,
  usedCommand,
  createdFile,
  ranTests,
  compacted,
}

/// Service that owns tip generation, context tracking, and the built-in tip
/// library.  Stateless with respect to Flutter — can be used outside the
/// widget tree.
class BuddyService {
  final BuddyConfig config;
  final _rng = Random();

  /// Actions seen in the current session.
  final Set<UserAction> _seenActions = {};

  /// How many suggestions have been shown this session.
  int _suggestionsShown = 0;

  BuddyService({this.config = const BuddyConfig()});

  // ── Public API ────────────────────────────────────────────────────────

  /// Record a user action so future suggestions can be context-aware.
  void onUserAction(UserAction action) {
    _seenActions.add(action);
  }

  /// Generate a context-aware suggestion, or `null` if nothing is relevant
  /// or we have exceeded the session cap.
  BuddySuggestion? generateSuggestion(UserAction context) {
    if (!config.enabled) return null;
    if (_suggestionsShown >= config.maxSuggestionsPerSession) return null;

    final tip = getTipForContext(context);
    if (tip == null) return null;

    _suggestionsShown++;
    return BuddySuggestion(
      text: tip,
      category: _categoryForAction(context),
      priority: _priorityForAction(context),
    );
  }

  /// Return a tip string for the given context, or `null`.
  String? getTipForContext(UserAction context) {
    final pool = _tipsForContext(context);
    if (pool.isEmpty) return null;
    return pool[_rng.nextInt(pool.length)];
  }

  /// Return a random encouraging message.
  String getEncouragement() {
    return _encouragements[_rng.nextInt(_encouragements.length)];
  }

  /// The full built-in tips library.
  List<String> get allTips => List.unmodifiable(_allTips);

  // ── Private helpers ───────────────────────────────────────────────────

  SuggestionCategory _categoryForAction(UserAction action) {
    return switch (action) {
      UserAction.receivedError => SuggestionCategory.warning,
      UserAction.longSession => SuggestionCategory.encouragement,
      UserAction.firstMessage => SuggestionCategory.tip,
      _ => SuggestionCategory.tip,
    };
  }

  int _priorityForAction(UserAction action) {
    return switch (action) {
      UserAction.receivedError => 2,
      UserAction.firstMessage => 1,
      _ => 0,
    };
  }

  List<String> _tipsForContext(UserAction context) {
    return switch (context) {
      UserAction.firstMessage => _firstMessageTips,
      UserAction.receivedError => _errorTips,
      UserAction.longSession => _longSessionTips,
      UserAction.sentMessage => _generalTips,
      UserAction.usedTool => _toolTips,
      UserAction.switchedModel => _modelTips,
      UserAction.usedCommand => _commandTips,
      UserAction.createdFile => _fileTips,
      UserAction.ranTests => _testTips,
      UserAction.compacted => _compactTips,
    };
  }

  // ── Tip library (~50+ tips) ───────────────────────────────────────────

  static const _firstMessageTips = [
    'Welcome! You can ask me to edit files, run commands, or explain code.',
    'Tip: Be specific about file paths and what you want changed.',
    'Try asking me to review a PR with /review.',
    'You can reference files by path — I will read them automatically.',
    'Use /help to see all available slash commands.',
  ];

  static const _errorTips = [
    'If a tool failed, try describing the problem differently.',
    'Check the error message carefully — it often contains the fix.',
    'You can paste error output directly and ask me to diagnose it.',
    'Tip: Use /compact if the context is getting large after many retries.',
    'Try breaking the task into smaller steps if errors persist.',
  ];

  static const _longSessionTips = [
    'Long session? Use /compact to summarise and free up context.',
    'Consider saving progress with /commit before continuing.',
    'Tip: /context shows how much of the context window you are using.',
    'You can start a new session if the current one feels stale.',
    'Great persistence! Take a break if you need one.',
  ];

  static const _generalTips = [
    'Tip: Use /plan to think through a problem before acting.',
    'You can ask me to search the codebase with grep patterns.',
    'Tip: Mention specific file paths for more precise edits.',
    'Try /cost to see token usage for this session.',
    'You can interrupt me anytime by pressing Escape.',
    'Tip: Use /memory to store important project context.',
  ];

  static const _toolTips = [
    'I can chain multiple tools together for complex tasks.',
    'Tip: Tools run in a sandbox — your files are safe.',
    'You can ask me to explain what a tool did and why.',
    'Tip: File edits show diffs so you can review changes.',
  ];

  static const _modelTips = [
    'Different models have different strengths — experiment!',
    'Tip: Faster models work well for simple questions.',
    'You can switch back with /model anytime.',
  ];

  static const _commandTips = [
    'Tip: /help lists every available command.',
    'You can create custom commands with skills.',
    'Tip: Commands can be combined with natural language.',
  ];

  static const _fileTips = [
    'Tip: I can create multiple files in one go.',
    'New files are shown as full diffs for review.',
    'You can ask me to scaffold entire project structures.',
  ];

  static const _testTips = [
    'Tip: I can generate tests for existing code.',
    'Ask me to check coverage after running tests.',
    'Tip: Use /review to get feedback on test quality.',
  ];

  static const _compactTips = [
    'Context compacted! The summary preserves key decisions.',
    'Tip: Important memories persist across compactions via /memory.',
    'You can compact again later if context fills up.',
  ];

  static const _encouragements = [
    'You are making great progress!',
    'Nice work — keep going!',
    'That was a clean solution.',
    'Solid approach. What is next?',
    'Well done! Ready for the next task?',
    'Excellent — the codebase is looking better already.',
    'Good call on that change.',
    'You are on a roll!',
    'That fix was spot-on.',
    'Great teamwork!',
  ];

  /// Flat list of every tip for the "show all tips" menu.
  static final _allTips = [
    ..._firstMessageTips,
    ..._errorTips,
    ..._longSessionTips,
    ..._generalTips,
    ..._toolTips,
    ..._modelTips,
    ..._commandTips,
    ..._fileTips,
    ..._testTips,
    ..._compactTips,
  ];
}

// ── BuddyWidget ────────────────────────────────────────────────────────────

/// An animated buddy avatar with tooltip-style popup for contextual
/// suggestions.  Tap to dismiss the current suggestion; long-press for an
/// options menu.
class BuddyWidget extends StatefulWidget {
  /// The service that generates suggestions.
  final BuddyService service;

  /// Duration before a suggestion auto-dismisses.
  final Duration autoDismissDuration;

  /// Called when the user disables the buddy from the long-press menu.
  final VoidCallback? onDisabled;

  /// Called when the user changes personality from the long-press menu.
  final ValueChanged<BuddyPersonality>? onPersonalityChanged;

  const BuddyWidget({
    super.key,
    required this.service,
    this.autoDismissDuration = const Duration(seconds: 8),
    this.onDisabled,
    this.onPersonalityChanged,
  });

  @override
  State<BuddyWidget> createState() => _BuddyWidgetState();
}

class _BuddyWidgetState extends State<BuddyWidget>
    with TickerProviderStateMixin {
  BuddyState _state = BuddyState.idle;
  BuddySuggestion? _currentSuggestion;
  final _queue = <BuddySuggestion>[];
  Timer? _autoDismissTimer;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  late final AnimationController _popupController;
  late final Animation<double> _popupAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _popupController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _popupAnimation = CurvedAnimation(
      parent: _popupController,
      curve: Curves.easeOutBack,
    );
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _pulseController.dispose();
    _popupController.dispose();
    super.dispose();
  }

  // ── Public API for parent widgets ─────────────────────────────────────

  /// Enqueue a suggestion.  If nothing is currently showing, display it
  /// immediately.
  void showSuggestion(BuddySuggestion suggestion) {
    if (!widget.service.config.enabled) return;
    if (_currentSuggestion != null) {
      _queue.add(suggestion);
      return;
    }
    _displaySuggestion(suggestion);
  }

  /// Convenience: generate and show a context-aware suggestion.
  void triggerForContext(UserAction context) {
    final suggestion = widget.service.generateSuggestion(context);
    if (suggestion != null) showSuggestion(suggestion);
  }

  // ── Internal ──────────────────────────────────────────────────────────

  void _displaySuggestion(BuddySuggestion suggestion) {
    setState(() {
      _currentSuggestion = suggestion;
      _state = BuddyState.suggesting;
    });
    _pulseController.repeat(reverse: true);
    _popupController.forward(from: 0);

    _autoDismissTimer?.cancel();
    _autoDismissTimer = Timer(widget.autoDismissDuration, _dismiss);
  }

  void _dismiss() {
    _autoDismissTimer?.cancel();
    _popupController.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        _currentSuggestion = null;
        _state = BuddyState.idle;
      });
      _pulseController.stop();
      _pulseController.reset();

      // Show next in queue.
      if (_queue.isNotEmpty) {
        _displaySuggestion(_queue.removeAt(0));
      }
    });
  }

  void _showAllTips() {
    final tips = widget.service.allTips;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('All Tips'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: tips.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(tips[i], style: const TextStyle(fontSize: 13)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showMenu() {
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy - 120,
        offset.dx + renderBox.size.width,
        offset.dy,
      ),
      items: [
        const PopupMenuItem(value: 'tips', child: Text('Show all tips')),
        const PopupMenuItem(
            value: 'personality', child: Text('Change personality')),
        const PopupMenuItem(value: 'disable', child: Text('Disable buddy')),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'tips':
          _showAllTips();
        case 'personality':
          _showPersonalityPicker();
        case 'disable':
          widget.onDisabled?.call();
      }
    });
  }

  void _showPersonalityPicker() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose Personality'),
        children: BuddyPersonality.values.map((p) {
          return SimpleDialogOption(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onPersonalityChanged?.call(p);
            },
            child: Text(p.name),
          );
        }).toList(),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!widget.service.config.enabled) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Popup
        if (_currentSuggestion != null)
          FadeTransition(
            opacity: _popupAnimation,
            child: ScaleTransition(
              scale: _popupAnimation,
              alignment: Alignment.bottomRight,
              child: _buildPopup(theme),
            ),
          ),
        const SizedBox(height: 4),
        // Avatar
        GestureDetector(
          onTap: _currentSuggestion != null ? _dismiss : null,
          onLongPress: _showMenu,
          child: ScaleTransition(
            scale: _pulseAnimation,
            child: _buildAvatar(theme),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatar(ThemeData theme) {
    final color = switch (_state) {
      BuddyState.idle => theme.colorScheme.surfaceContainerHighest,
      BuddyState.thinking => theme.colorScheme.secondary,
      BuddyState.suggesting => theme.colorScheme.primary,
      BuddyState.helping => theme.colorScheme.tertiary,
      BuddyState.celebrating => Colors.amber,
    };

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: Icon(
        _state == BuddyState.celebrating ? Icons.celebration : Icons.auto_fix_high,
        size: 18,
        color: theme.colorScheme.onPrimary,
      ),
    );
  }

  Widget _buildPopup(ThemeData theme) {
    final suggestion = _currentSuggestion!;
    final iconData = switch (suggestion.category) {
      SuggestionCategory.tip => Icons.lightbulb_outline,
      SuggestionCategory.shortcut => Icons.keyboard,
      SuggestionCategory.warning => Icons.warning_amber,
      SuggestionCategory.encouragement => Icons.thumb_up_alt_outlined,
    };

    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              suggestion.text,
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (suggestion.dismissible) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _dismiss,
              child: Icon(Icons.close, size: 14,
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
