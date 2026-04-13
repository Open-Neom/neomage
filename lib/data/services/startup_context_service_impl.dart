import '../../domain/models/startup_context_config.dart';
import '../../domain/models/startup_context_entry.dart';
import '../../domain/models/startup_context_result.dart';
import '../../domain/services/startup_context_service.dart';

/// Default startup context service implementation.
///
/// Assembles a memory prelude from registered [StartupContextProvider]s,
/// respecting character limits and truncation policies.
class StartupContextServiceImpl extends StartupContextService {
  final List<StartupContextProvider> _providers;

  StartupContextServiceImpl({
    List<StartupContextProvider>? providers,
  }) : _providers = providers ?? [];

  /// Register a context provider (e.g., BioChip, daily memory, mission).
  void registerProvider(StartupContextProvider provider) {
    _providers.add(provider);
  }

  @override
  Future<StartupContextResult?> assemble({
    required String action,
    required StartupContextConfig config,
    String? timezone,
  }) async {
    if (!shouldApply(action, config)) return null;

    final entries = <StartupContextEntry>[];
    int totalChars = 0;
    bool anyTruncated = false;

    for (final provider in _providers) {
      if (totalChars >= config.maxTotalChars) break;

      final rawEntries = await provider.loadEntries(
        config: config,
        timezone: timezone,
      );

      for (final entry in rawEntries) {
        final remaining = config.maxTotalChars - totalChars;
        if (remaining <= 0) break;

        final charLimit = config.maxFileChars.clamp(0, remaining);
        if (entry.content.length <= charLimit) {
          entries.add(entry);
          totalChars += entry.charCount;
        } else {
          final truncated = _truncateToLimit(entry.content, charLimit);
          entries.add(StartupContextEntry(
            source: entry.source,
            content: truncated,
            originalBytes: entry.originalBytes,
            truncated: true,
            sourceTimestamp: entry.sourceTimestamp,
          ));
          totalChars += truncated.length;
          anyTruncated = true;
        }
      }
    }

    if (entries.isEmpty) {
      return StartupContextResult(
        prelude: '',
        entries: const [],
        totalChars: 0,
        anyTruncated: false,
        triggerAction: action,
      );
    }

    final prelude = _assemblePrelude(entries, config);

    return StartupContextResult(
      prelude: prelude,
      entries: entries,
      totalChars: totalChars,
      anyTruncated: anyTruncated,
      triggerAction: action,
    );
  }

  /// Truncate content to fit within character limit, preserving line boundaries.
  String _truncateToLimit(String content, int limit) {
    if (content.length <= limit) return content;

    // Binary search for optimal line-boundary truncation
    final lines = content.split('\n');
    int lo = 0;
    int hi = lines.length;
    int bestEnd = 0;

    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      final candidate = lines.take(mid).join('\n');
      if (candidate.length <= limit) {
        bestEnd = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }

    final truncated = lines.take(bestEnd).join('\n');
    return truncated.isEmpty ? content.substring(0, limit) : truncated;
  }

  /// Assemble the final prelude string from entries.
  String _assemblePrelude(
    List<StartupContextEntry> entries,
    StartupContextConfig config,
  ) {
    final buffer = StringBuffer();

    if (config.markUntrusted) {
      buffer.writeln('<startup-memory status="untrusted">');
    }

    for (final entry in entries) {
      buffer.writeln('<!-- source: ${_escapeXml(entry.source)} -->');
      buffer.writeln(entry.content);
      if (entry.truncated) {
        buffer.writeln('<!-- truncated -->');
      }
      buffer.writeln();
    }

    if (config.markUntrusted) {
      buffer.writeln('</startup-memory>');
    }

    return buffer.toString().trimRight();
  }

  static String _escapeXml(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}

/// Provider interface for startup context sources.
///
/// Implementations supply memory entries from specific sources
/// (BioChip profile, daily memories, active missions, etc.).
abstract class StartupContextProvider {
  /// Provider priority (lower runs first).
  int get priority => 100;

  /// Load memory entries for startup context.
  Future<List<StartupContextEntry>> loadEntries({
    required StartupContextConfig config,
    String? timezone,
  });
}
