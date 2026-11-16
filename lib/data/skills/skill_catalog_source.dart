import 'dart:async';

import 'package:flutter/services.dart' show AssetBundle, AssetManifest, rootBundle;

/// Entry returned by a [SkillCatalogSource] for progressive skill discovery.
///
/// Supports both asset-bundled markdown files ([assetPath]) and dynamically
/// resolved skills ([contentLoader], e.g. remote registries, MCP catalogs, or
/// encrypted/host-injected skill bundles).
class CatalogSkillEntry {
  /// Canonical skill identifier (e.g. `chain_of_thought`).
  final String id;

  /// Logical category folder/group (e.g. `architecture`, `testing`).
  final String category;

  /// Language code (e.g. `en`, `es`).
  final String language;

  /// Optional Flutter asset path when backed by an asset bundle.
  final String? assetPath;

  /// Optional human-readable display title override.
  final String? displayNameOverride;

  /// Short description or activation hint.
  final String description;

  /// Optional custom async loader for non-asset or pre-decoded skills.
  final Future<String> Function()? contentLoader;

  const CatalogSkillEntry({
    required this.id,
    required this.category,
    this.language = 'en',
    this.assetPath,
    this.displayNameOverride,
    this.description = '',
    this.contentLoader,
  });

  /// Human-readable name derived from [displayNameOverride] or [id].
  String get displayName =>
      (displayNameOverride != null && displayNameOverride!.trim().isNotEmpty)
          ? displayNameOverride!.trim()
          : _humanizeSkillId(id);

  /// Loads the markdown content of this skill on demand.
  Future<String> loadContent({AssetBundle? bundle}) async {
    if (contentLoader != null) {
      return await contentLoader!();
    }
    final path = assetPath;
    if (path != null && path.isNotEmpty) {
      return await (bundle ?? rootBundle).loadString(path);
    }
    throw StateError('Skill "$id" has neither contentLoader nor assetPath.');
  }
}

/// Pluggable contract for providing categorized skill catalogs to Neomage.
///
/// Host applications can implement or adapt external skill packages and
/// register them via `SkillRegistry.registerCatalogSource(...)` without
/// coupling `neomage` to private packages.
abstract interface class SkillCatalogSource {
  /// Returns available skills grouped by category.
  Future<Map<String, List<CatalogSkillEntry>>> loadByCategory({
    String preferLanguage = 'es',
  });
}

/// Function-backed [SkillCatalogSource] adapter for concise host registration.
class CallbackSkillCatalogSource implements SkillCatalogSource {
  final Future<Map<String, List<CatalogSkillEntry>>> Function(
    String preferLanguage,
  ) _loader;

  const CallbackSkillCatalogSource(this._loader);

  @override
  Future<Map<String, List<CatalogSkillEntry>>> loadByCategory({
    String preferLanguage = 'es',
  }) =>
      _loader(preferLanguage);
}

/// Default open-source [SkillCatalogSource] that discovers markdown skills
/// bundled under Flutter asset prefixes (such as `assets/skills/`).
class AssetManifestSkillCatalogSource implements SkillCatalogSource {
  /// Asset path prefixes scanned for `<category>/<skill>.md` entries.
  final List<String> assetPrefixes;

  /// Optional [AssetBundle] override for testing.
  final AssetBundle? bundle;

  const AssetManifestSkillCatalogSource({
    this.assetPrefixes = const <String>[
      'assets/skills/',
      'packages/neomage/assets/skills/',
    ],
    this.bundle,
  });

  static final RegExp _skillAssetPattern = RegExp(
    r'(?:^|/)(?:skills/)(?:(en|es)/)?(?:([^/]+)/)?([^/]+)\.md$',
  );

  @override
  Future<Map<String, List<CatalogSkillEntry>>> loadByCategory({
    String preferLanguage = 'es',
  }) async {
    final effectiveBundle = bundle ?? rootBundle;
    final manifest = await AssetManifest.loadFromAssetBundle(effectiveBundle);
    final assets = manifest.listAssets();
    final discovered = <CatalogSkillEntry>[];

    for (final path in assets) {
      if (!assetPrefixes.any(path.startsWith)) continue;
      final match = _skillAssetPattern.firstMatch(path);
      if (match == null) continue;

      final id = match.group(3)!;
      if (id.toLowerCase() == 'readme') continue;

      final lang = match.group(1) ?? 'en';
      final category = match.group(2) ?? 'general';

      discovered.add(
        CatalogSkillEntry(
          id: id,
          category: category,
          language: lang,
          assetPath: path,
          contentLoader: () => effectiveBundle.loadString(path),
        ),
      );
    }

    final preferredKeys = <String>{
      for (final entry in discovered)
        if (entry.language == preferLanguage) '${entry.category}/${entry.id}',
    };

    final grouped = <String, List<CatalogSkillEntry>>{};
    for (final entry in discovered) {
      final key = '${entry.category}/${entry.id}';
      if (entry.language != preferLanguage && preferredKeys.contains(key)) {
        continue;
      }
      grouped.putIfAbsent(entry.category, () => <CatalogSkillEntry>[]).add(entry);
    }

    for (final list in grouped.values) {
      list.sort((a, b) => a.id.compareTo(b.id));
    }
    return grouped;
  }
}

String _humanizeSkillId(String id) {
  return id
      .split(RegExp(r'[_\-]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
