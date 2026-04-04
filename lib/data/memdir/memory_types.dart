// Memory type system — port of neom_claw/src/memdir/memoryTypes.ts.
// Closed 4-type taxonomy for persistent memory.

/// The four types of persistent memory.
enum MemoryType {
  /// Information about the user's role, goals, preferences.
  user,

  /// Guidance from the user about approach — corrections and confirmations.
  feedback,

  /// Information about ongoing work, goals, initiatives within the project.
  project,

  /// Pointers to external systems and resources.
  reference;

  static MemoryType? tryParse(String raw) => switch (raw.toLowerCase().trim()) {
        'user' => MemoryType.user,
        'feedback' => MemoryType.feedback,
        'project' => MemoryType.project,
        'reference' => MemoryType.reference,
        _ => null,
      };
}

/// Parsed frontmatter from a memory file.
class MemoryFrontmatter {
  final String name;
  final String description;
  final MemoryType? type;

  const MemoryFrontmatter({
    required this.name,
    required this.description,
    this.type,
  });
}

/// Parse YAML-like frontmatter from memory file content.
/// Expects format:
/// ```
/// ---
/// name: ...
/// description: ...
/// type: user|feedback|project|reference
/// ---
/// ```
MemoryFrontmatter? parseFrontmatter(String content) {
  if (!content.startsWith('---')) return null;

  final endIndex = content.indexOf('---', 3);
  if (endIndex == -1) return null;

  final frontmatter = content.substring(3, endIndex).trim();
  String? name;
  String? description;
  MemoryType? type;

  for (final line in frontmatter.split('\n')) {
    final colonIndex = line.indexOf(':');
    if (colonIndex == -1) continue;

    final key = line.substring(0, colonIndex).trim();
    final value = line.substring(colonIndex + 1).trim();

    switch (key) {
      case 'name':
        name = value;
      case 'description':
        description = value;
      case 'type':
        type = MemoryType.tryParse(value);
    }
  }

  if (name == null || description == null) return null;

  return MemoryFrontmatter(
    name: name,
    description: description,
    type: type,
  );
}
