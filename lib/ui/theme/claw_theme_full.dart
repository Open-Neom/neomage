/// Complete theming system for Flutter Claw, ported from OpenClaude (Claude Code).
///
/// Provides a rich color scheme, text theme, component theme, predefined themes
/// (dark and light variants), syntax highlighting colors, and a [ThemeManager]
/// for runtime theme switching and persistence.
library;

import 'dart:async';

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Color Scheme
// ---------------------------------------------------------------------------

/// Extended color palette used throughout the Claw UI.
///
/// Mirrors the semantic tokens found in OpenClaude's terminal theme, adapted
/// for Flutter's widget-based rendering.
class ClawColorScheme {
  const ClawColorScheme({
    required this.primary,
    required this.primaryVariant,
    required this.secondary,
    required this.secondaryVariant,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.error,
    required this.onPrimary,
    required this.onSecondary,
    required this.onBackground,
    required this.onSurface,
    required this.onError,
    required this.border,
    required this.borderVariant,
    required this.muted,
    required this.mutedForeground,
    required this.accent,
    required this.accentForeground,
    required this.destructive,
    required this.destructiveForeground,
    required this.success,
    required this.warning,
    required this.info,
  });

  /// The dominant brand color (buttons, links, active elements).
  final Color primary;

  /// A darker / lighter variant of [primary] for hover or pressed states.
  final Color primaryVariant;

  /// Secondary accent used for less prominent interactive elements.
  final Color secondary;

  /// Variant of [secondary].
  final Color secondaryVariant;

  /// The main background color of the application.
  final Color background;

  /// Surface color for cards, sheets, and elevated containers.
  final Color surface;

  /// Alternative surface for distinguishing nested containers.
  final Color surfaceVariant;

  /// Color used to indicate errors and destructive states.
  final Color error;

  /// Foreground color rendered on top of [primary].
  final Color onPrimary;

  /// Foreground color rendered on top of [secondary].
  final Color onSecondary;

  /// Foreground color rendered on top of [background].
  final Color onBackground;

  /// Foreground color rendered on top of [surface].
  final Color onSurface;

  /// Foreground color rendered on top of [error].
  final Color onError;

  /// Default border color for containers and dividers.
  final Color border;

  /// Lighter / subtler border variant.
  final Color borderVariant;

  /// Muted background used for disabled or inactive areas.
  final Color muted;

  /// Foreground color for content placed on [muted] backgrounds.
  final Color mutedForeground;

  /// Accent highlight color (badges, indicators).
  final Color accent;

  /// Foreground on [accent] backgrounds.
  final Color accentForeground;

  /// Color for destructive actions (delete, remove).
  final Color destructive;

  /// Foreground on [destructive] backgrounds.
  final Color destructiveForeground;

  /// Positive / success indication.
  final Color success;

  /// Warning indication.
  final Color warning;

  /// Informational indication.
  final Color info;

  /// Returns a copy with the given fields replaced.
  ClawColorScheme copyWith({
    Color? primary,
    Color? primaryVariant,
    Color? secondary,
    Color? secondaryVariant,
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? error,
    Color? onPrimary,
    Color? onSecondary,
    Color? onBackground,
    Color? onSurface,
    Color? onError,
    Color? border,
    Color? borderVariant,
    Color? muted,
    Color? mutedForeground,
    Color? accent,
    Color? accentForeground,
    Color? destructive,
    Color? destructiveForeground,
    Color? success,
    Color? warning,
    Color? info,
  }) {
    return ClawColorScheme(
      primary: primary ?? this.primary,
      primaryVariant: primaryVariant ?? this.primaryVariant,
      secondary: secondary ?? this.secondary,
      secondaryVariant: secondaryVariant ?? this.secondaryVariant,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      error: error ?? this.error,
      onPrimary: onPrimary ?? this.onPrimary,
      onSecondary: onSecondary ?? this.onSecondary,
      onBackground: onBackground ?? this.onBackground,
      onSurface: onSurface ?? this.onSurface,
      onError: onError ?? this.onError,
      border: border ?? this.border,
      borderVariant: borderVariant ?? this.borderVariant,
      muted: muted ?? this.muted,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      accent: accent ?? this.accent,
      accentForeground: accentForeground ?? this.accentForeground,
      destructive: destructive ?? this.destructive,
      destructiveForeground: destructiveForeground ?? this.destructiveForeground,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
    );
  }

  /// Serialise the scheme to a plain map for persistence / export.
  Map<String, int> toMap() {
    return {
      'primary': primary.value,
      'primaryVariant': primaryVariant.value,
      'secondary': secondary.value,
      'secondaryVariant': secondaryVariant.value,
      'background': background.value,
      'surface': surface.value,
      'surfaceVariant': surfaceVariant.value,
      'error': error.value,
      'onPrimary': onPrimary.value,
      'onSecondary': onSecondary.value,
      'onBackground': onBackground.value,
      'onSurface': onSurface.value,
      'onError': onError.value,
      'border': border.value,
      'borderVariant': borderVariant.value,
      'muted': muted.value,
      'mutedForeground': mutedForeground.value,
      'accent': accent.value,
      'accentForeground': accentForeground.value,
      'destructive': destructive.value,
      'destructiveForeground': destructiveForeground.value,
      'success': success.value,
      'warning': warning.value,
      'info': info.value,
    };
  }

  /// Deserialise from a map produced by [toMap].
  factory ClawColorScheme.fromMap(Map<String, dynamic> map) {
    Color c(String key) => Color(map[key] as int);
    return ClawColorScheme(
      primary: c('primary'),
      primaryVariant: c('primaryVariant'),
      secondary: c('secondary'),
      secondaryVariant: c('secondaryVariant'),
      background: c('background'),
      surface: c('surface'),
      surfaceVariant: c('surfaceVariant'),
      error: c('error'),
      onPrimary: c('onPrimary'),
      onSecondary: c('onSecondary'),
      onBackground: c('onBackground'),
      onSurface: c('onSurface'),
      onError: c('onError'),
      border: c('border'),
      borderVariant: c('borderVariant'),
      muted: c('muted'),
      mutedForeground: c('mutedForeground'),
      accent: c('accent'),
      accentForeground: c('accentForeground'),
      destructive: c('destructive'),
      destructiveForeground: c('destructiveForeground'),
      success: c('success'),
      warning: c('warning'),
      info: c('info'),
    );
  }
}

// ---------------------------------------------------------------------------
// Text Theme
// ---------------------------------------------------------------------------

/// Typography definitions for Claw, including monospaced variants for code
/// and terminal output.
class ClawTextTheme {
  const ClawTextTheme({
    required this.displayLarge,
    required this.displayMedium,
    required this.headlineLarge,
    required this.headlineMedium,
    required this.titleLarge,
    required this.titleMedium,
    required this.bodyLarge,
    required this.bodyMedium,
    required this.bodySmall,
    required this.labelLarge,
    required this.labelMedium,
    required this.labelSmall,
    required this.code,
    required this.codeSmall,
    required this.terminal,
  });

  final TextStyle displayLarge;
  final TextStyle displayMedium;
  final TextStyle headlineLarge;
  final TextStyle headlineMedium;
  final TextStyle titleLarge;
  final TextStyle titleMedium;
  final TextStyle bodyLarge;
  final TextStyle bodyMedium;
  final TextStyle bodySmall;
  final TextStyle labelLarge;
  final TextStyle labelMedium;
  final TextStyle labelSmall;

  /// Monospaced style for inline code blocks.
  final TextStyle code;

  /// Smaller monospaced style for annotations inside code.
  final TextStyle codeSmall;

  /// Monospaced style for terminal / REPL output.
  final TextStyle terminal;

  /// Default text theme using Inter for proportional text and JetBrains Mono
  /// for code / terminal styles.
  factory ClawTextTheme.defaults({Color color = Colors.white}) {
    const String sans = 'Inter';
    const String mono = 'JetBrains Mono';
    return ClawTextTheme(
      displayLarge: TextStyle(fontFamily: sans, fontSize: 32, fontWeight: FontWeight.w700, color: color, height: 1.2),
      displayMedium: TextStyle(fontFamily: sans, fontSize: 28, fontWeight: FontWeight.w600, color: color, height: 1.25),
      headlineLarge: TextStyle(fontFamily: sans, fontSize: 24, fontWeight: FontWeight.w600, color: color, height: 1.3),
      headlineMedium: TextStyle(fontFamily: sans, fontSize: 20, fontWeight: FontWeight.w600, color: color, height: 1.35),
      titleLarge: TextStyle(fontFamily: sans, fontSize: 18, fontWeight: FontWeight.w600, color: color, height: 1.4),
      titleMedium: TextStyle(fontFamily: sans, fontSize: 16, fontWeight: FontWeight.w500, color: color, height: 1.4),
      bodyLarge: TextStyle(fontFamily: sans, fontSize: 16, fontWeight: FontWeight.w400, color: color, height: 1.5),
      bodyMedium: TextStyle(fontFamily: sans, fontSize: 14, fontWeight: FontWeight.w400, color: color, height: 1.5),
      bodySmall: TextStyle(fontFamily: sans, fontSize: 12, fontWeight: FontWeight.w400, color: color, height: 1.5),
      labelLarge: TextStyle(fontFamily: sans, fontSize: 14, fontWeight: FontWeight.w500, color: color, letterSpacing: 0.5),
      labelMedium: TextStyle(fontFamily: sans, fontSize: 12, fontWeight: FontWeight.w500, color: color, letterSpacing: 0.5),
      labelSmall: TextStyle(fontFamily: sans, fontSize: 11, fontWeight: FontWeight.w500, color: color, letterSpacing: 0.5),
      code: TextStyle(fontFamily: mono, fontSize: 14, fontWeight: FontWeight.w400, color: color, height: 1.6),
      codeSmall: TextStyle(fontFamily: mono, fontSize: 12, fontWeight: FontWeight.w400, color: color, height: 1.6),
      terminal: TextStyle(fontFamily: mono, fontSize: 13, fontWeight: FontWeight.w400, color: color, height: 1.5),
    );
  }

  /// Returns a copy of this theme with all styles applied the given [color].
  ClawTextTheme apply({required Color color}) {
    return ClawTextTheme(
      displayLarge: displayLarge.copyWith(color: color),
      displayMedium: displayMedium.copyWith(color: color),
      headlineLarge: headlineLarge.copyWith(color: color),
      headlineMedium: headlineMedium.copyWith(color: color),
      titleLarge: titleLarge.copyWith(color: color),
      titleMedium: titleMedium.copyWith(color: color),
      bodyLarge: bodyLarge.copyWith(color: color),
      bodyMedium: bodyMedium.copyWith(color: color),
      bodySmall: bodySmall.copyWith(color: color),
      labelLarge: labelLarge.copyWith(color: color),
      labelMedium: labelMedium.copyWith(color: color),
      labelSmall: labelSmall.copyWith(color: color),
      code: code.copyWith(color: color),
      codeSmall: codeSmall.copyWith(color: color),
      terminal: terminal.copyWith(color: color),
    );
  }

  /// Serialise to a plain map.
  Map<String, dynamic> toMap() {
    return {
      'displayLarge': _styleToMap(displayLarge),
      'displayMedium': _styleToMap(displayMedium),
      'headlineLarge': _styleToMap(headlineLarge),
      'headlineMedium': _styleToMap(headlineMedium),
      'titleLarge': _styleToMap(titleLarge),
      'titleMedium': _styleToMap(titleMedium),
      'bodyLarge': _styleToMap(bodyLarge),
      'bodyMedium': _styleToMap(bodyMedium),
      'bodySmall': _styleToMap(bodySmall),
      'labelLarge': _styleToMap(labelLarge),
      'labelMedium': _styleToMap(labelMedium),
      'labelSmall': _styleToMap(labelSmall),
      'code': _styleToMap(code),
      'codeSmall': _styleToMap(codeSmall),
      'terminal': _styleToMap(terminal),
    };
  }

  static Map<String, dynamic> _styleToMap(TextStyle s) => {
        'fontFamily': s.fontFamily,
        'fontSize': s.fontSize,
        'fontWeight': s.fontWeight?.index,
        'color': s.color?.value,
      };
}

// ---------------------------------------------------------------------------
// Component Theme
// ---------------------------------------------------------------------------

/// Dimensional constants for common UI components.
class ClawComponentTheme {
  const ClawComponentTheme({
    this.buttonHeight = 40.0,
    this.buttonRadius = 8.0,
    this.cardRadius = 12.0,
    this.cardElevation = 1.0,
    this.inputHeight = 40.0,
    this.inputRadius = 8.0,
    this.chipHeight = 32.0,
    this.badgeSize = 20.0,
    this.tooltipRadius = 6.0,
    this.dialogRadius = 16.0,
    this.statusBarHeight = 28.0,
    this.sidebarWidth = 260.0,
    this.panelMinWidth = 200.0,
  });

  final double buttonHeight;
  final double buttonRadius;
  final double cardRadius;
  final double cardElevation;
  final double inputHeight;
  final double inputRadius;
  final double chipHeight;
  final double badgeSize;
  final double tooltipRadius;
  final double dialogRadius;
  final double statusBarHeight;
  final double sidebarWidth;
  final double panelMinWidth;

  ClawComponentTheme copyWith({
    double? buttonHeight,
    double? buttonRadius,
    double? cardRadius,
    double? cardElevation,
    double? inputHeight,
    double? inputRadius,
    double? chipHeight,
    double? badgeSize,
    double? tooltipRadius,
    double? dialogRadius,
    double? statusBarHeight,
    double? sidebarWidth,
    double? panelMinWidth,
  }) {
    return ClawComponentTheme(
      buttonHeight: buttonHeight ?? this.buttonHeight,
      buttonRadius: buttonRadius ?? this.buttonRadius,
      cardRadius: cardRadius ?? this.cardRadius,
      cardElevation: cardElevation ?? this.cardElevation,
      inputHeight: inputHeight ?? this.inputHeight,
      inputRadius: inputRadius ?? this.inputRadius,
      chipHeight: chipHeight ?? this.chipHeight,
      badgeSize: badgeSize ?? this.badgeSize,
      tooltipRadius: tooltipRadius ?? this.tooltipRadius,
      dialogRadius: dialogRadius ?? this.dialogRadius,
      statusBarHeight: statusBarHeight ?? this.statusBarHeight,
      sidebarWidth: sidebarWidth ?? this.sidebarWidth,
      panelMinWidth: panelMinWidth ?? this.panelMinWidth,
    );
  }

  Map<String, double> toMap() => {
        'buttonHeight': buttonHeight,
        'buttonRadius': buttonRadius,
        'cardRadius': cardRadius,
        'cardElevation': cardElevation,
        'inputHeight': inputHeight,
        'inputRadius': inputRadius,
        'chipHeight': chipHeight,
        'badgeSize': badgeSize,
        'tooltipRadius': tooltipRadius,
        'dialogRadius': dialogRadius,
        'statusBarHeight': statusBarHeight,
        'sidebarWidth': sidebarWidth,
        'panelMinWidth': panelMinWidth,
      };
}

// ---------------------------------------------------------------------------
// Syntax Theme
// ---------------------------------------------------------------------------

/// Colors used by the code syntax highlighter, customised per theme.
class SyntaxTheme {
  const SyntaxTheme({
    required this.keyword,
    required this.string,
    required this.comment,
    required this.number,
    required this.type,
    required this.function_,
    required this.variable,
    required this.operator_,
    required this.punctuation,
  });

  final Color keyword;
  final Color string;
  final Color comment;
  final Color number;
  final Color type;
  final Color function_;
  final Color variable;
  final Color operator_;
  final Color punctuation;

  Map<String, int> toMap() => {
        'keyword': keyword.value,
        'string': string.value,
        'comment': comment.value,
        'number': number.value,
        'type': type.value,
        'function': function_.value,
        'variable': variable.value,
        'operator': operator_.value,
        'punctuation': punctuation.value,
      };

  factory SyntaxTheme.fromMap(Map<String, dynamic> m) {
    Color c(String k) => Color(m[k] as int);
    return SyntaxTheme(
      keyword: c('keyword'),
      string: c('string'),
      comment: c('comment'),
      number: c('number'),
      type: c('type'),
      function_: c('function'),
      variable: c('variable'),
      operator_: c('operator'),
      punctuation: c('punctuation'),
    );
  }
}

// ---------------------------------------------------------------------------
// Theme Info & Full Theme
// ---------------------------------------------------------------------------

/// Metadata for a registered theme.
class ThemeInfo {
  const ThemeInfo({
    required this.name,
    required this.displayName,
    required this.isDark,
    this.description = '',
  });

  final String name;
  final String displayName;
  final bool isDark;
  final String description;
}

/// A complete Claw theme containing colours, typography, component sizes, and
/// syntax highlighting colours.
class ClawTheme {
  const ClawTheme({
    required this.info,
    required this.colors,
    required this.textTheme,
    required this.componentTheme,
    required this.syntaxTheme,
  });

  final ThemeInfo info;
  final ClawColorScheme colors;
  final ClawTextTheme textTheme;
  final ClawComponentTheme componentTheme;
  final SyntaxTheme syntaxTheme;

  /// Serialise the entire theme to a map for export / persistence.
  Map<String, dynamic> toMap() => {
        'name': info.name,
        'displayName': info.displayName,
        'isDark': info.isDark,
        'description': info.description,
        'colors': colors.toMap(),
        'textTheme': textTheme.toMap(),
        'componentTheme': componentTheme.toMap(),
        'syntaxTheme': syntaxTheme.toMap(),
      };

  /// Reconstruct a [ClawTheme] from a map produced by [toMap].
  factory ClawTheme.fromMap(Map<String, dynamic> m) {
    return ClawTheme(
      info: ThemeInfo(
        name: m['name'] as String,
        displayName: m['displayName'] as String,
        isDark: m['isDark'] as bool,
        description: (m['description'] as String?) ?? '',
      ),
      colors: ClawColorScheme.fromMap(m['colors'] as Map<String, dynamic>),
      textTheme: ClawTextTheme.defaults(), // text is regenerated from defaults
      componentTheme: const ClawComponentTheme(),
      syntaxTheme: SyntaxTheme.fromMap(m['syntaxTheme'] as Map<String, dynamic>),
    );
  }
}

// ---------------------------------------------------------------------------
// Predefined Themes
// ---------------------------------------------------------------------------

/// Collection of all built-in Claw themes.
class ClawThemes {
  ClawThemes._();

  // -- Dark themes ----------------------------------------------------------

  /// Deep navy / purple — the default Claw dark theme.
  static final ClawTheme darkDefault = ClawTheme(
    info: const ThemeInfo(name: 'dark-default', displayName: 'Dark Default', isDark: true, description: 'Deep navy/purple dark theme'),
    colors: const ClawColorScheme(
      primary: Color(0xFF7C6FE4),
      primaryVariant: Color(0xFF5B4FC7),
      secondary: Color(0xFF4EC9B0),
      secondaryVariant: Color(0xFF37A08B),
      background: Color(0xFF0D1117),
      surface: Color(0xFF161B22),
      surfaceVariant: Color(0xFF1C2333),
      error: Color(0xFFF85149),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFF0D1117),
      onBackground: Color(0xFFE6EDF3),
      onSurface: Color(0xFFE6EDF3),
      onError: Color(0xFFFFFFFF),
      border: Color(0xFF30363D),
      borderVariant: Color(0xFF21262D),
      muted: Color(0xFF21262D),
      mutedForeground: Color(0xFF8B949E),
      accent: Color(0xFF7C6FE4),
      accentForeground: Color(0xFFFFFFFF),
      destructive: Color(0xFFF85149),
      destructiveForeground: Color(0xFFFFFFFF),
      success: Color(0xFF3FB950),
      warning: Color(0xFFD29922),
      info: Color(0xFF58A6FF),
    ),
    textTheme: ClawTextTheme.defaults(color: const Color(0xFFE6EDF3)),
    componentTheme: const ClawComponentTheme(),
    syntaxTheme: const SyntaxTheme(
      keyword: Color(0xFFFF7B72),
      string: Color(0xFFA5D6FF),
      comment: Color(0xFF8B949E),
      number: Color(0xFF79C0FF),
      type: Color(0xFFFFA657),
      function_: Color(0xFFD2A8FF),
      variable: Color(0xFFFFA657),
      operator_: Color(0xFFFF7B72),
      punctuation: Color(0xFFC9D1D9),
    ),
  );

  /// Monokai-inspired dark theme.
  static final ClawTheme darkMonokai = ClawTheme(
    info: const ThemeInfo(name: 'dark-monokai', displayName: 'Monokai', isDark: true, description: 'Monokai-inspired dark theme'),
    colors: const ClawColorScheme(
      primary: Color(0xFFA6E22E),
      primaryVariant: Color(0xFF86B21E),
      secondary: Color(0xFF66D9EF),
      secondaryVariant: Color(0xFF4FB8CC),
      background: Color(0xFF272822),
      surface: Color(0xFF2D2E27),
      surfaceVariant: Color(0xFF3E3D32),
      error: Color(0xFFF92672),
      onPrimary: Color(0xFF272822),
      onSecondary: Color(0xFF272822),
      onBackground: Color(0xFFF8F8F2),
      onSurface: Color(0xFFF8F8F2),
      onError: Color(0xFFFFFFFF),
      border: Color(0xFF49483E),
      borderVariant: Color(0xFF3E3D32),
      muted: Color(0xFF3E3D32),
      mutedForeground: Color(0xFF75715E),
      accent: Color(0xFFAE81FF),
      accentForeground: Color(0xFFFFFFFF),
      destructive: Color(0xFFF92672),
      destructiveForeground: Color(0xFFFFFFFF),
      success: Color(0xFFA6E22E),
      warning: Color(0xFFE6DB74),
      info: Color(0xFF66D9EF),
    ),
    textTheme: ClawTextTheme.defaults(color: const Color(0xFFF8F8F2)),
    componentTheme: const ClawComponentTheme(),
    syntaxTheme: const SyntaxTheme(
      keyword: Color(0xFFF92672),
      string: Color(0xFFE6DB74),
      comment: Color(0xFF75715E),
      number: Color(0xFFAE81FF),
      type: Color(0xFF66D9EF),
      function_: Color(0xFFA6E22E),
      variable: Color(0xFFF8F8F2),
      operator_: Color(0xFFF92672),
      punctuation: Color(0xFFF8F8F2),
    ),
  );

  /// Solarized dark theme.
  static final ClawTheme darkSolarized = ClawTheme(
    info: const ThemeInfo(name: 'dark-solarized', displayName: 'Solarized Dark', isDark: true, description: 'Ethan Schoonover\'s Solarized dark'),
    colors: const ClawColorScheme(
      primary: Color(0xFF268BD2),
      primaryVariant: Color(0xFF1A6DA8),
      secondary: Color(0xFF2AA198),
      secondaryVariant: Color(0xFF1E8078),
      background: Color(0xFF002B36),
      surface: Color(0xFF073642),
      surfaceVariant: Color(0xFF0A4050),
      error: Color(0xFFDC322F),
      onPrimary: Color(0xFFFDF6E3),
      onSecondary: Color(0xFFFDF6E3),
      onBackground: Color(0xFF839496),
      onSurface: Color(0xFF93A1A1),
      onError: Color(0xFFFDF6E3),
      border: Color(0xFF586E75),
      borderVariant: Color(0xFF073642),
      muted: Color(0xFF073642),
      mutedForeground: Color(0xFF657B83),
      accent: Color(0xFF6C71C4),
      accentForeground: Color(0xFFFDF6E3),
      destructive: Color(0xFFDC322F),
      destructiveForeground: Color(0xFFFDF6E3),
      success: Color(0xFF859900),
      warning: Color(0xFFB58900),
      info: Color(0xFF268BD2),
    ),
    textTheme: ClawTextTheme.defaults(color: const Color(0xFF839496)),
    componentTheme: const ClawComponentTheme(),
    syntaxTheme: const SyntaxTheme(
      keyword: Color(0xFF859900),
      string: Color(0xFF2AA198),
      comment: Color(0xFF586E75),
      number: Color(0xFFD33682),
      type: Color(0xFFB58900),
      function_: Color(0xFF268BD2),
      variable: Color(0xFFCB4B16),
      operator_: Color(0xFF859900),
      punctuation: Color(0xFF839496),
    ),
  );

  /// Gruvbox dark theme.
  static final ClawTheme darkGruvbox = ClawTheme(
    info: const ThemeInfo(name: 'dark-gruvbox', displayName: 'Gruvbox Dark', isDark: true, description: 'Retro groove dark theme'),
    colors: const ClawColorScheme(
      primary: Color(0xFFFE8019),
      primaryVariant: Color(0xFFD65D0E),
      secondary: Color(0xFF8EC07C),
      secondaryVariant: Color(0xFF689D6A),
      background: Color(0xFF282828),
      surface: Color(0xFF3C3836),
      surfaceVariant: Color(0xFF504945),
      error: Color(0xFFCC241D),
      onPrimary: Color(0xFF282828),
      onSecondary: Color(0xFF282828),
      onBackground: Color(0xFFEBDBB2),
      onSurface: Color(0xFFEBDBB2),
      onError: Color(0xFFEBDBB2),
      border: Color(0xFF665C54),
      borderVariant: Color(0xFF504945),
      muted: Color(0xFF504945),
      mutedForeground: Color(0xFFA89984),
      accent: Color(0xFFD3869B),
      accentForeground: Color(0xFF282828),
      destructive: Color(0xFFFB4934),
      destructiveForeground: Color(0xFFEBDBB2),
      success: Color(0xFFB8BB26),
      warning: Color(0xFFFABD2F),
      info: Color(0xFF83A598),
    ),
    textTheme: ClawTextTheme.defaults(color: const Color(0xFFEBDBB2)),
    componentTheme: const ClawComponentTheme(),
    syntaxTheme: const SyntaxTheme(
      keyword: Color(0xFFFB4934),
      string: Color(0xFFB8BB26),
      comment: Color(0xFF928374),
      number: Color(0xFFD3869B),
      type: Color(0xFFFABD2F),
      function_: Color(0xFF8EC07C),
      variable: Color(0xFF83A598),
      operator_: Color(0xFFFE8019),
      punctuation: Color(0xFFEBDBB2),
    ),
  );

  /// Dracula dark theme.
  static final ClawTheme darkDracula = ClawTheme(
    info: const ThemeInfo(name: 'dark-dracula', displayName: 'Dracula', isDark: true, description: 'Dracula-inspired dark theme'),
    colors: const ClawColorScheme(
      primary: Color(0xFFBD93F9),
      primaryVariant: Color(0xFF9B6FD7),
      secondary: Color(0xFF50FA7B),
      secondaryVariant: Color(0xFF3BD65E),
      background: Color(0xFF282A36),
      surface: Color(0xFF343746),
      surfaceVariant: Color(0xFF44475A),
      error: Color(0xFFFF5555),
      onPrimary: Color(0xFF282A36),
      onSecondary: Color(0xFF282A36),
      onBackground: Color(0xFFF8F8F2),
      onSurface: Color(0xFFF8F8F2),
      onError: Color(0xFFF8F8F2),
      border: Color(0xFF6272A4),
      borderVariant: Color(0xFF44475A),
      muted: Color(0xFF44475A),
      mutedForeground: Color(0xFF6272A4),
      accent: Color(0xFFFF79C6),
      accentForeground: Color(0xFF282A36),
      destructive: Color(0xFFFF5555),
      destructiveForeground: Color(0xFFF8F8F2),
      success: Color(0xFF50FA7B),
      warning: Color(0xFFF1FA8C),
      info: Color(0xFF8BE9FD),
    ),
    textTheme: ClawTextTheme.defaults(color: const Color(0xFFF8F8F2)),
    componentTheme: const ClawComponentTheme(),
    syntaxTheme: const SyntaxTheme(
      keyword: Color(0xFFFF79C6),
      string: Color(0xFFF1FA8C),
      comment: Color(0xFF6272A4),
      number: Color(0xFFBD93F9),
      type: Color(0xFF8BE9FD),
      function_: Color(0xFF50FA7B),
      variable: Color(0xFFF8F8F2),
      operator_: Color(0xFFFF79C6),
      punctuation: Color(0xFFF8F8F2),
    ),
  );

  // -- Light themes ---------------------------------------------------------

  /// Default light theme.
  static final ClawTheme lightDefault = ClawTheme(
    info: const ThemeInfo(name: 'light-default', displayName: 'Light Default', isDark: false, description: 'Clean light theme'),
    colors: const ClawColorScheme(
      primary: Color(0xFF5B4FC7),
      primaryVariant: Color(0xFF4A3FB0),
      secondary: Color(0xFF0F7B6C),
      secondaryVariant: Color(0xFF0A5F53),
      background: Color(0xFFFAFBFC),
      surface: Color(0xFFFFFFFF),
      surfaceVariant: Color(0xFFF3F4F6),
      error: Color(0xFFCF222E),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFFFFFFFF),
      onBackground: Color(0xFF1F2328),
      onSurface: Color(0xFF1F2328),
      onError: Color(0xFFFFFFFF),
      border: Color(0xFFD0D7DE),
      borderVariant: Color(0xFFE5E8EB),
      muted: Color(0xFFF3F4F6),
      mutedForeground: Color(0xFF656D76),
      accent: Color(0xFF5B4FC7),
      accentForeground: Color(0xFFFFFFFF),
      destructive: Color(0xFFCF222E),
      destructiveForeground: Color(0xFFFFFFFF),
      success: Color(0xFF1A7F37),
      warning: Color(0xFF9A6700),
      info: Color(0xFF0969DA),
    ),
    textTheme: ClawTextTheme.defaults(color: const Color(0xFF1F2328)),
    componentTheme: const ClawComponentTheme(),
    syntaxTheme: const SyntaxTheme(
      keyword: Color(0xFFCF222E),
      string: Color(0xFF0A3069),
      comment: Color(0xFF6E7781),
      number: Color(0xFF0550AE),
      type: Color(0xFF953800),
      function_: Color(0xFF8250DF),
      variable: Color(0xFF953800),
      operator_: Color(0xFFCF222E),
      punctuation: Color(0xFF1F2328),
    ),
  );

  /// Solarized light theme.
  static final ClawTheme lightSolarized = ClawTheme(
    info: const ThemeInfo(name: 'light-solarized', displayName: 'Solarized Light', isDark: false, description: 'Ethan Schoonover\'s Solarized light'),
    colors: const ClawColorScheme(
      primary: Color(0xFF268BD2),
      primaryVariant: Color(0xFF1A6DA8),
      secondary: Color(0xFF2AA198),
      secondaryVariant: Color(0xFF1E8078),
      background: Color(0xFFFDF6E3),
      surface: Color(0xFFEEE8D5),
      surfaceVariant: Color(0xFFE4DEC8),
      error: Color(0xFFDC322F),
      onPrimary: Color(0xFFFDF6E3),
      onSecondary: Color(0xFFFDF6E3),
      onBackground: Color(0xFF657B83),
      onSurface: Color(0xFF586E75),
      onError: Color(0xFFFDF6E3),
      border: Color(0xFF93A1A1),
      borderVariant: Color(0xFFEEE8D5),
      muted: Color(0xFFEEE8D5),
      mutedForeground: Color(0xFF93A1A1),
      accent: Color(0xFF6C71C4),
      accentForeground: Color(0xFFFDF6E3),
      destructive: Color(0xFFDC322F),
      destructiveForeground: Color(0xFFFDF6E3),
      success: Color(0xFF859900),
      warning: Color(0xFFB58900),
      info: Color(0xFF268BD2),
    ),
    textTheme: ClawTextTheme.defaults(color: const Color(0xFF657B83)),
    componentTheme: const ClawComponentTheme(),
    syntaxTheme: const SyntaxTheme(
      keyword: Color(0xFF859900),
      string: Color(0xFF2AA198),
      comment: Color(0xFF93A1A1),
      number: Color(0xFFD33682),
      type: Color(0xFFB58900),
      function_: Color(0xFF268BD2),
      variable: Color(0xFFCB4B16),
      operator_: Color(0xFF859900),
      punctuation: Color(0xFF657B83),
    ),
  );

  /// GitHub-inspired light theme.
  static final ClawTheme lightGithub = ClawTheme(
    info: const ThemeInfo(name: 'light-github', displayName: 'GitHub Light', isDark: false, description: 'GitHub-inspired light theme'),
    colors: const ClawColorScheme(
      primary: Color(0xFF0969DA),
      primaryVariant: Color(0xFF0550AE),
      secondary: Color(0xFF1A7F37),
      secondaryVariant: Color(0xFF116329),
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFF6F8FA),
      surfaceVariant: Color(0xFFEAEEF2),
      error: Color(0xFFCF222E),
      onPrimary: Color(0xFFFFFFFF),
      onSecondary: Color(0xFFFFFFFF),
      onBackground: Color(0xFF1F2328),
      onSurface: Color(0xFF1F2328),
      onError: Color(0xFFFFFFFF),
      border: Color(0xFFD0D7DE),
      borderVariant: Color(0xFFE5E8EB),
      muted: Color(0xFFF6F8FA),
      mutedForeground: Color(0xFF656D76),
      accent: Color(0xFF8250DF),
      accentForeground: Color(0xFFFFFFFF),
      destructive: Color(0xFFCF222E),
      destructiveForeground: Color(0xFFFFFFFF),
      success: Color(0xFF1A7F37),
      warning: Color(0xFF9A6700),
      info: Color(0xFF0969DA),
    ),
    textTheme: ClawTextTheme.defaults(color: const Color(0xFF1F2328)),
    componentTheme: const ClawComponentTheme(),
    syntaxTheme: const SyntaxTheme(
      keyword: Color(0xFFCF222E),
      string: Color(0xFF0A3069),
      comment: Color(0xFF6E7781),
      number: Color(0xFF0550AE),
      type: Color(0xFF953800),
      function_: Color(0xFF8250DF),
      variable: Color(0xFF953800),
      operator_: Color(0xFFCF222E),
      punctuation: Color(0xFF24292F),
    ),
  );

  /// All built-in themes keyed by name.
  static final Map<String, ClawTheme> all = {
    darkDefault.info.name: darkDefault,
    darkMonokai.info.name: darkMonokai,
    darkSolarized.info.name: darkSolarized,
    darkGruvbox.info.name: darkGruvbox,
    darkDracula.info.name: darkDracula,
    lightDefault.info.name: lightDefault,
    lightSolarized.info.name: lightSolarized,
    lightGithub.info.name: lightGithub,
  };
}

// ---------------------------------------------------------------------------
// Theme Manager
// ---------------------------------------------------------------------------

/// Manages the active theme at runtime, supports custom themes, and converts
/// Claw themes to Flutter [ThemeData].
class ThemeManager {
  ThemeManager._({ClawTheme? initial})
      : _currentTheme = initial ?? ClawThemes.darkDefault {
    _controller = StreamController<ClawTheme>.broadcast();
  }

  /// Singleton instance.
  static final ThemeManager instance = ThemeManager._();

  /// Allow construction for testing with a specific initial theme.
  factory ThemeManager.withTheme(ClawTheme theme) => ThemeManager._(initial: theme);

  ClawTheme _currentTheme;
  late final StreamController<ClawTheme> _controller;

  final Map<String, ClawTheme> _customThemes = {};

  /// The currently active theme.
  ClawTheme get currentTheme => _currentTheme;

  /// Stream that emits whenever the theme changes.
  Stream<ClawTheme> get themeStream => _controller.stream;

  /// Switch to a named built-in or custom theme.
  ///
  /// Throws [ArgumentError] if [name] does not match any registered theme.
  void setTheme(String name) {
    final theme = ClawThemes.all[name] ?? _customThemes[name];
    if (theme == null) {
      throw ArgumentError('Unknown theme: $name');
    }
    _currentTheme = theme;
    _controller.add(_currentTheme);
  }

  /// Register and activate a user-defined theme.
  void customTheme({
    required String name,
    required ClawColorScheme colors,
    ClawTextTheme? text,
    ClawComponentTheme? components,
    SyntaxTheme? syntax,
  }) {
    final theme = ClawTheme(
      info: ThemeInfo(name: name, displayName: name, isDark: _looksLikeDark(colors)),
      colors: colors,
      textTheme: text ?? ClawTextTheme.defaults(color: colors.onBackground),
      componentTheme: components ?? const ClawComponentTheme(),
      syntaxTheme: syntax ?? ClawThemes.darkDefault.syntaxTheme,
    );
    _customThemes[name] = theme;
    _currentTheme = theme;
    _controller.add(_currentTheme);
  }

  /// Returns metadata for every available theme (built-in + custom).
  List<ThemeInfo> getAvailableThemes() {
    return [
      ...ClawThemes.all.values.map((t) => t.info),
      ..._customThemes.values.map((t) => t.info),
    ];
  }

  /// Convert a [ClawColorScheme] to a Flutter [ThemeData].
  static ThemeData toMaterialTheme(ClawColorScheme colors) {
    final brightness = _brightnessOf(colors);
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: colors.primary,
      onPrimary: colors.onPrimary,
      secondary: colors.secondary,
      onSecondary: colors.onSecondary,
      error: colors.error,
      onError: colors.onError,
      surface: colors.surface,
      onSurface: colors.onSurface,
    );

    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.background,
      cardColor: colors.surface,
      dividerColor: colors.border,
      hintColor: colors.mutedForeground,
      canvasColor: colors.background,
      dialogBackgroundColor: colors.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceVariant,
        border: OutlineInputBorder(
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceVariant,
        labelStyle: TextStyle(color: colors.onSurface),
        side: BorderSide(color: colors.borderVariant),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.border),
        ),
        textStyle: TextStyle(color: colors.onSurface, fontSize: 12),
      ),
    );
  }

  /// Apply [ClawComponentTheme] overrides to an existing [ThemeData].
  static ThemeData applyComponentOverrides(
    ThemeData base,
    ClawComponentTheme comp,
  ) {
    return base.copyWith(
      cardTheme: base.cardTheme.copyWith(
        elevation: comp.cardElevation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(comp.cardRadius),
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(comp.dialogRadius),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: Size(0, comp.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(comp.buttonRadius),
          ),
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(comp.inputRadius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(comp.inputRadius),
          borderSide: base.inputDecorationTheme.enabledBorder?.borderSide ?? BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(comp.inputRadius),
          borderSide: base.inputDecorationTheme.focusedBorder?.borderSide ?? BorderSide.none,
        ),
        constraints: BoxConstraints(minHeight: comp.inputHeight),
      ),
    );
  }

  /// Serialise the current theme to a map suitable for JSON encoding.
  Map<String, dynamic> exportTheme() => _currentTheme.toMap();

  /// Import a theme from a previously exported map and activate it.
  void importTheme(Map<String, dynamic> map) {
    final theme = ClawTheme.fromMap(map);
    _customThemes[theme.info.name] = theme;
    _currentTheme = theme;
    _controller.add(_currentTheme);
  }

  // -- Helpers --------------------------------------------------------------

  static bool _looksLikeDark(ClawColorScheme colors) {
    final bg = colors.background;
    final luminance = bg.computeLuminance();
    return luminance < 0.5;
  }

  static Brightness _brightnessOf(ClawColorScheme colors) {
    return _looksLikeDark(colors) ? Brightness.dark : Brightness.light;
  }

  /// Release resources. Call when the application shuts down.
  void dispose() {
    _controller.close();
  }
}
