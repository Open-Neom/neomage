// Design system — reusable widgets, tokens, and theme utilities.
// Port of neom_claw/src/components/ design tokens and shared components.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ────────────────────────────────────────────────────────────────────────────
// COLOR PALETTE
// ────────────────────────────────────────────────────────────────────────────

/// Full color palette for the Claw design system (dark and light themes).
class ClawColors {
  ClawColors._();

  // ── Brand ──
  static const amber = Color(0xFFD97706);
  static const amberLight = Color(0xFFFBBF24);
  static const amberDark = Color(0xFFB45309);

  // ── Dark theme surfaces ──
  static const darkBg = Color(0xFF0D1117);
  static const darkSurface = Color(0xFF161B22);
  static const darkCard = Color(0xFF1C2333);
  static const darkElevated = Color(0xFF242D3D);
  static const darkBorder = Color(0xFF30363D);
  static const darkBorderSubtle = Color(0xFF21262D);

  // ── Light theme surfaces ──
  static const lightBg = Color(0xFFF6F8FA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightElevated = Color(0xFFF0F3F6);
  static const lightBorder = Color(0xFFD0D7DE);
  static const lightBorderSubtle = Color(0xFFE1E4E8);

  // ── Text (dark) ──
  static const darkTextPrimary = Color(0xFFE6EDF3);
  static const darkTextSecondary = Color(0xFF8B949E);
  static const darkTextTertiary = Color(0xFF6E7681);
  static const darkTextDisabled = Color(0xFF484F58);

  // ── Text (light) ──
  static const lightTextPrimary = Color(0xFF1F2328);
  static const lightTextSecondary = Color(0xFF656D76);
  static const lightTextTertiary = Color(0xFF8C959F);
  static const lightTextDisabled = Color(0xFFAFB8C1);

  // ── Semantic ──
  static const success = Color(0xFF3FB950);
  static const successBg = Color(0xFF0D2818);
  static const warning = Color(0xFFD29922);
  static const warningBg = Color(0xFF2E1F0A);
  static const error = Color(0xFFF85149);
  static const errorBg = Color(0xFF3D1214);
  static const info = Color(0xFF58A6FF);
  static const infoBg = Color(0xFF0D2240);

  // ── Semantic (light) ──
  static const successLightBg = Color(0xFFDCFCE7);
  static const warningLightBg = Color(0xFFFEF3C7);
  static const errorLightBg = Color(0xFFFEE2E2);
  static const infoLightBg = Color(0xFFDBEAFE);

  // ── Code ──
  static const codeBg = Color(0xFF0D1117);
  static const codeText = Color(0xFFE6EDF3);
  static const codeKeyword = Color(0xFFFF7B72);
  static const codeString = Color(0xFFA5D6FF);
  static const codeComment = Color(0xFF8B949E);
  static const codeFunction = Color(0xFFD2A8FF);
  static const codeGreen = Color(0xFF7EE787);
  static const codeYellow = Color(0xFFD29922);
  static const codeRed = Color(0xFFF85149);

  // ── Agent / model indicators ──
  static const agentNeomClaw = Color(0xFFD97706);
  static const agentSonnet = Color(0xFF58A6FF);
  static const agentHaiku = Color(0xFF7EE787);
  static const agentOpus = Color(0xFFD2A8FF);
}

// ────────────────────────────────────────────────────────────────────────────
// TYPOGRAPHY
// ────────────────────────────────────────────────────────────────────────────

/// Text style definitions.
class ClawTypography {
  ClawTypography._();

  static const _monoFamily = 'JetBrains Mono';
  static const _sansFamily = 'Inter';

  // ── Headings ──
  static const heading1 = TextStyle(
    fontFamily: _sansFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.5,
  );

  static const heading2 = TextStyle(
    fontFamily: _sansFamily,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.3,
  );

  static const heading3 = TextStyle(
    fontFamily: _sansFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const heading4 = TextStyle(
    fontFamily: _sansFamily,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  // ── Body ──
  static const bodyLarge = TextStyle(
    fontFamily: _sansFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const bodyMedium = TextStyle(
    fontFamily: _sansFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const bodySmall = TextStyle(
    fontFamily: _sansFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  // ── Code ──
  static const codeLarge = TextStyle(
    fontFamily: _monoFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.6,
  );

  static const codeMedium = TextStyle(
    fontFamily: _monoFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const codeSmall = TextStyle(
    fontFamily: _monoFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  // ── Labels / Captions ──
  static const label = TextStyle(
    fontFamily: _sansFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: 0.3,
  );

  static const caption = TextStyle(
    fontFamily: _sansFamily,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  static const overline = TextStyle(
    fontFamily: _sansFamily,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: 1.2,
  );
}

// ────────────────────────────────────────────────────────────────────────────
// SPACING
// ────────────────────────────────────────────────────────────────────────────

class ClawSpacing {
  ClawSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Standard horizontal padding for page content.
  static const pagePadding = EdgeInsets.symmetric(horizontal: lg);

  /// Standard card content padding.
  static const cardPadding = EdgeInsets.all(lg);

  /// Compact inner padding for dense UI areas.
  static const compactPadding = EdgeInsets.all(sm);

  /// Vertical gap between sections.
  static const sectionGap = SizedBox(height: xl);

  /// Vertical gap between items in a list.
  static const itemGap = SizedBox(height: sm);
}

// ────────────────────────────────────────────────────────────────────────────
// BORDER RADIUS
// ────────────────────────────────────────────────────────────────────────────

class ClawRadius {
  ClawRadius._();

  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double full = 999;

  static final borderXs = BorderRadius.circular(xs);
  static final borderSm = BorderRadius.circular(sm);
  static final borderMd = BorderRadius.circular(md);
  static final borderLg = BorderRadius.circular(lg);
  static final borderXl = BorderRadius.circular(xl);
  static final borderFull = BorderRadius.circular(full);
}

// ────────────────────────────────────────────────────────────────────────────
// SHADOWS
// ────────────────────────────────────────────────────────────────────────────

class ClawShadows {
  ClawShadows._();

  static const sm = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 3,
      offset: Offset(0, 1),
    ),
  ];

  static const md = [
    BoxShadow(
      color: Color(0x1F000000),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
    BoxShadow(
      color: Color(0x0F000000),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  static const lg = [
    BoxShadow(
      color: Color(0x26000000),
      blurRadius: 15,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color(0x0D000000),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  static const xl = [
    BoxShadow(
      color: Color(0x33000000),
      blurRadius: 25,
      offset: Offset(0, 8),
    ),
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 10,
      offset: Offset(0, 4),
    ),
  ];
}

// ────────────────────────────────────────────────────────────────────────────
// THEME BUILDER
// ────────────────────────────────────────────────────────────────────────────

/// Builds ThemeData for light and dark modes using Claw design tokens.
class ClawTheme {
  ClawTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: ClawColors.amber,
      brightness: Brightness.light,
      surface: ClawColors.lightSurface,
      onSurface: ClawColors.lightTextPrimary,
      error: ClawColors.error,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: ClawColors.lightBg,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: ClawColors.lightSurface,
        foregroundColor: ClawColors.lightTextPrimary,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: ClawColors.lightCard,
        shape: RoundedRectangleBorder(
          borderRadius: ClawRadius.borderLg,
          side: const BorderSide(color: ClawColors.lightBorder, width: 0.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ClawColors.lightElevated,
        border: OutlineInputBorder(borderRadius: ClawRadius.borderMd),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      dividerTheme: const DividerThemeData(
        color: ClawColors.lightBorder,
        thickness: 0.5,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: ClawColors.lightTextPrimary,
          borderRadius: ClawRadius.borderSm,
        ),
        textStyle: ClawTypography.caption.copyWith(color: ClawColors.lightBg),
      ),
    );
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: ClawColors.amber,
      brightness: Brightness.dark,
      surface: ClawColors.darkSurface,
      onSurface: ClawColors.darkTextPrimary,
      error: ClawColors.error,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: ClawColors.darkBg,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: ClawColors.darkSurface,
        foregroundColor: ClawColors.darkTextPrimary,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: ClawColors.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: ClawRadius.borderLg,
          side: const BorderSide(color: ClawColors.darkBorder, width: 0.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ClawColors.darkElevated,
        border: OutlineInputBorder(borderRadius: ClawRadius.borderMd),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      dividerTheme: const DividerThemeData(
        color: ClawColors.darkBorder,
        thickness: 0.5,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: ClawColors.darkTextPrimary,
          borderRadius: ClawRadius.borderSm,
        ),
        textStyle: ClawTypography.caption.copyWith(color: ClawColors.darkBg),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// BUTTON VARIANTS
// ────────────────────────────────────────────────────────────────────────────

enum ClawButtonVariant { primary, secondary, ghost, danger }

/// Styled button with variant support (primary, secondary, ghost, danger).
class ClawButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final ClawButtonVariant variant;
  final IconData? icon;
  final bool isLoading;
  final bool compact;

  const ClawButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = ClawButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final (bgColor, fgColor, borderColor) = switch (variant) {
      ClawButtonVariant.primary => (
          ClawColors.amber,
          Colors.white,
          ClawColors.amber,
        ),
      ClawButtonVariant.secondary => (
          isDark ? ClawColors.darkElevated : ClawColors.lightElevated,
          isDark ? ClawColors.darkTextPrimary : ClawColors.lightTextPrimary,
          isDark ? ClawColors.darkBorder : ClawColors.lightBorder,
        ),
      ClawButtonVariant.ghost => (
          Colors.transparent,
          isDark ? ClawColors.darkTextSecondary : ClawColors.lightTextSecondary,
          Colors.transparent,
        ),
      ClawButtonVariant.danger => (
          ClawColors.error,
          Colors.white,
          ClawColors.error,
        ),
    };

    final style = ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(bgColor),
      foregroundColor: WidgetStatePropertyAll(fgColor),
      side: WidgetStatePropertyAll(
        BorderSide(color: borderColor, width: 0.5),
      ),
      padding: WidgetStatePropertyAll(
        compact
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: ClawRadius.borderMd),
      ),
      textStyle: WidgetStatePropertyAll(
        compact ? ClawTypography.caption : ClawTypography.bodyMedium,
      ),
      elevation: const WidgetStatePropertyAll(0),
    );

    final child = isLoading
        ? SizedBox(
            width: compact ? 14 : 18,
            height: compact ? 14 : 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: fgColor,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: compact ? 14 : 18),
                SizedBox(width: compact ? 4 : 8),
              ],
              Text(label),
            ],
          );

    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: style,
      child: child,
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// ICON BUTTON
// ────────────────────────────────────────────────────────────────────────────

/// Icon button with tooltip and consistent sizing.
class ClawIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;
  final Color? backgroundColor;

  const ClawIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.size = 20,
    this.color,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final defaultColor =
        isDark ? ClawColors.darkTextSecondary : ClawColors.lightTextSecondary;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor ?? Colors.transparent,
        borderRadius: ClawRadius.borderSm,
        child: InkWell(
          onTap: onPressed,
          borderRadius: ClawRadius.borderSm,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              icon,
              size: size,
              color: onPressed != null ? (color ?? defaultColor) : defaultColor.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// CARD
// ────────────────────────────────────────────────────────────────────────────

/// Card with optional header, body, and footer sections.
class ClawCard extends StatelessWidget {
  final Widget? header;
  final Widget child;
  final Widget? footer;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final bool hasBorder;

  const ClawCard({
    super.key,
    this.header,
    required this.child,
    this.footer,
    this.padding,
    this.backgroundColor,
    this.hasBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = backgroundColor ??
        (isDark ? ClawColors.darkCard : ClawColors.lightCard);
    final border =
        isDark ? ClawColors.darkBorder : ClawColors.lightBorder;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: ClawRadius.borderLg,
        border: hasBorder
            ? Border.all(color: border, width: 0.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: ClawSpacing.lg,
                vertical: ClawSpacing.md,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: border, width: 0.5),
                ),
              ),
              child: header!,
            ),
          Padding(
            padding: padding ?? ClawSpacing.cardPadding,
            child: child,
          ),
          if (footer != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: ClawSpacing.lg,
                vertical: ClawSpacing.md,
              ),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: border, width: 0.5),
                ),
              ),
              child: footer!,
            ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// BADGE
// ────────────────────────────────────────────────────────────────────────────

enum ClawBadgeVariant { success, warning, error, info, neutral }

/// Status badge with semantic coloring.
class ClawBadge extends StatelessWidget {
  final String label;
  final ClawBadgeVariant variant;
  final IconData? icon;

  const ClawBadge({
    super.key,
    required this.label,
    this.variant = ClawBadgeVariant.neutral,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final (fg, bg) = switch (variant) {
      ClawBadgeVariant.success => (
          ClawColors.success,
          isDark ? ClawColors.successBg : ClawColors.successLightBg,
        ),
      ClawBadgeVariant.warning => (
          ClawColors.warning,
          isDark ? ClawColors.warningBg : ClawColors.warningLightBg,
        ),
      ClawBadgeVariant.error => (
          ClawColors.error,
          isDark ? ClawColors.errorBg : ClawColors.errorLightBg,
        ),
      ClawBadgeVariant.info => (
          ClawColors.info,
          isDark ? ClawColors.infoBg : ClawColors.infoLightBg,
        ),
      ClawBadgeVariant.neutral => (
          isDark ? ClawColors.darkTextSecondary : ClawColors.lightTextSecondary,
          isDark ? ClawColors.darkElevated : ClawColors.lightElevated,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: ClawRadius.borderFull,
        border: Border.all(color: fg.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: ClawTypography.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// CHIP
// ────────────────────────────────────────────────────────────────────────────

/// Tag / chip widget with optional remove callback.
class ClawChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;
  final Color? color;

  const ClawChip({
    super.key,
    required this.label,
    this.icon,
    this.onRemove,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chipColor = color ??
        (isDark ? ClawColors.darkTextSecondary : ClawColors.lightTextSecondary);
    final bg = isDark ? ClawColors.darkElevated : ClawColors.lightElevated;

    return Material(
      color: bg,
      borderRadius: ClawRadius.borderSm,
      child: InkWell(
        onTap: onTap,
        borderRadius: ClawRadius.borderSm,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: ClawRadius.borderSm,
            border: Border.all(
              color: chipColor.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: chipColor),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: ClawTypography.caption.copyWith(color: chipColor),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onRemove,
                  child: Icon(
                    Icons.close,
                    size: 12,
                    color: chipColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// DIVIDER
// ────────────────────────────────────────────────────────────────────────────

/// Styled divider with optional label.
class ClawDivider extends StatelessWidget {
  final String? label;
  final double height;

  const ClawDivider({super.key, this.label, this.height = 24});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? ClawColors.darkBorder : ClawColors.lightBorder;

    if (label == null) {
      return Divider(height: height, thickness: 0.5, color: color);
    }

    return SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(child: Divider(thickness: 0.5, color: color)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label!,
              style: ClawTypography.overline.copyWith(
                color: isDark
                    ? ClawColors.darkTextTertiary
                    : ClawColors.lightTextTertiary,
              ),
            ),
          ),
          Expanded(child: Divider(thickness: 0.5, color: color)),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// AVATAR
// ────────────────────────────────────────────────────────────────────────────

/// User or model avatar with initials fallback.
class ClawAvatar extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final String? imageUrl;
  final double size;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const ClawAvatar({
    super.key,
    this.label,
    this.icon,
    this.imageUrl,
    this.size = 32,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = backgroundColor ??
        (isDark ? ClawColors.darkElevated : ClawColors.lightElevated);
    final fg = foregroundColor ??
        (isDark ? ClawColors.darkTextPrimary : ClawColors.lightTextPrimary);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(
          color: (isDark ? ClawColors.darkBorder : ClawColors.lightBorder),
          width: 0.5,
        ),
      ),
      child: ClipOval(
        child: imageUrl != null
            ? Image.network(
                imageUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(fg),
              )
            : _fallback(fg),
      ),
    );
  }

  Widget _fallback(Color fg) {
    if (icon != null) {
      return Center(child: Icon(icon, size: size * 0.55, color: fg));
    }
    final initials = (label ?? '?')
        .split(' ')
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.38,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// LOADING INDICATOR
// ────────────────────────────────────────────────────────────────────────────

enum ClawLoadingStyle { spinner, dots, shimmer }

/// Spinner, dots, or shimmer loading indicator.
class ClawLoadingIndicator extends StatefulWidget {
  final ClawLoadingStyle style;
  final double size;
  final Color? color;
  final String? message;

  const ClawLoadingIndicator({
    super.key,
    this.style = ClawLoadingStyle.spinner,
    this.size = 24,
    this.color,
    this.message,
  });

  @override
  State<ClawLoadingIndicator> createState() => _ClawLoadingIndicatorState();
}

class _ClawLoadingIndicatorState extends State<ClawLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        widget.color ?? Theme.of(context).colorScheme.primary;

    final indicator = switch (widget.style) {
      ClawLoadingStyle.spinner => SizedBox(
          width: widget.size,
          height: widget.size,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: effectiveColor,
          ),
        ),
      ClawLoadingStyle.dots => _buildDots(effectiveColor),
      ClawLoadingStyle.shimmer => _buildShimmer(effectiveColor),
    };

    if (widget.message == null) return indicator;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        indicator,
        const SizedBox(height: 8),
        Text(
          widget.message!,
          style: ClawTypography.caption.copyWith(
            color: effectiveColor.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildDots(Color color) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final offset = (i * 0.33);
          final t = ((_controller.value + offset) % 1.0);
          final scale = 0.5 + 0.5 * (t < 0.5 ? t * 2 : (1 - t) * 2);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: widget.size * 0.28,
                height: widget.size * 0.28,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildShimmer(Color color) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Container(
        width: widget.size * 4,
        height: widget.size,
        decoration: BoxDecoration(
          borderRadius: ClawRadius.borderSm,
          gradient: LinearGradient(
            begin: Alignment(-1.0 + _controller.value * 3, 0),
            end: Alignment(_controller.value * 3, 0),
            colors: [
              color.withValues(alpha: 0.06),
              color.withValues(alpha: 0.15),
              color.withValues(alpha: 0.06),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// TOAST
// ────────────────────────────────────────────────────────────────────────────

enum ClawToastVariant { success, warning, error, info }

/// Toast notification widget with auto-dismiss.
class ClawToast extends StatefulWidget {
  final String message;
  final ClawToastVariant variant;
  final Duration duration;
  final VoidCallback? onDismiss;
  final String? action;
  final VoidCallback? onAction;

  const ClawToast({
    super.key,
    required this.message,
    this.variant = ClawToastVariant.info,
    this.duration = const Duration(seconds: 4),
    this.onDismiss,
    this.action,
    this.onAction,
  });

  @override
  State<ClawToast> createState() => _ClawToastState();
}

class _ClawToastState extends State<ClawToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<Offset> _slideAnimation;
  Timer? _autoDismiss;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    _animController.forward();
    _autoDismiss = Timer(widget.duration, _dismiss);
  }

  void _dismiss() {
    _autoDismiss?.cancel();
    _animController.reverse().then((_) => widget.onDismiss?.call());
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (iconData, color) = switch (widget.variant) {
      ClawToastVariant.success => (Icons.check_circle, ClawColors.success),
      ClawToastVariant.warning => (Icons.warning_amber, ClawColors.warning),
      ClawToastVariant.error => (Icons.error_outline, ClawColors.error),
      ClawToastVariant.info => (Icons.info_outline, ClawColors.info),
    };

    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: ClawColors.darkCard,
          borderRadius: ClawRadius.borderMd,
          border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
          boxShadow: ClawShadows.lg,
        ),
        child: Row(
          children: [
            Icon(iconData, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.message,
                style: ClawTypography.bodyMedium.copyWith(
                  color: ClawColors.darkTextPrimary,
                ),
              ),
            ),
            if (widget.action != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  widget.onAction?.call();
                  _dismiss();
                },
                child: Text(
                  widget.action!,
                  style: ClawTypography.label.copyWith(color: color),
                ),
              ),
            ],
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _dismiss,
              child: Icon(
                Icons.close,
                size: 16,
                color: ClawColors.darkTextTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// DIALOG
// ────────────────────────────────────────────────────────────────────────────

/// Base dialog with title, content, and action buttons.
class ClawDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget> actions;
  final IconData? icon;
  final double maxWidth;

  const ClawDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
    this.icon,
    this.maxWidth = 480,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor:
          isDark ? ClawColors.darkCard : ClawColors.lightCard,
      shape: RoundedRectangleBorder(borderRadius: ClawRadius.borderLg),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 22, color: ClawColors.amber),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: ClawTypography.heading4.copyWith(
                        color: isDark
                            ? ClawColors.darkTextPrimary
                            : ClawColors.lightTextPrimary,
                      ),
                    ),
                  ),
                  ClawIconButton(
                    icon: Icons.close,
                    tooltip: 'Close',
                    size: 18,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const ClawDivider(height: 20),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: content,
              ),
            ),
            // Actions
            if (actions.isNotEmpty) ...[
              const ClawDivider(height: 20),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions
                      .expand((w) => [w, const SizedBox(width: 8)])
                      .toList()
                    ..removeLast(),
                ),
              ),
            ] else
              const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// DROPDOWN
// ────────────────────────────────────────────────────────────────────────────

/// Styled dropdown with consistent theming.
class ClawDropdown<T> extends StatelessWidget {
  final T? value;
  final List<ClawDropdownItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? hint;
  final bool dense;

  const ClawDropdown({
    super.key,
    this.value,
    required this.items,
    this.onChanged,
    this.hint,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? ClawColors.darkElevated : ClawColors.lightElevated;
    final border = isDark ? ClawColors.darkBorder : ClawColors.lightBorder;
    final textColor =
        isDark ? ClawColors.darkTextPrimary : ClawColors.lightTextPrimary;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 10,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: ClawRadius.borderMd,
        border: Border.all(color: border, width: 0.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: dense,
          isExpanded: false,
          icon: Icon(Icons.expand_more, size: 18, color: textColor),
          dropdownColor: isDark ? ClawColors.darkCard : ClawColors.lightCard,
          hint: hint != null
              ? Text(
                  hint!,
                  style: ClawTypography.bodyMedium.copyWith(
                    color: isDark
                        ? ClawColors.darkTextTertiary
                        : ClawColors.lightTextTertiary,
                  ),
                )
              : null,
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item.value,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.icon != null) ...[
                          Icon(item.icon, size: 16, color: textColor),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          item.label,
                          style: ClawTypography.bodyMedium
                              .copyWith(color: textColor),
                        ),
                      ],
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class ClawDropdownItem<T> {
  final T value;
  final String label;
  final IconData? icon;

  const ClawDropdownItem({
    required this.value,
    required this.label,
    this.icon,
  });
}

// ────────────────────────────────────────────────────────────────────────────
// TEXT FIELD
// ────────────────────────────────────────────────────────────────────────────

/// Styled text field with label, hint, and error support.
class ClawTextField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? hint;
  final String? errorText;
  final int? maxLines;
  final int? minLines;
  final bool obscureText;
  final bool readOnly;
  final IconData? prefixIcon;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;

  const ClawTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.hint,
    this.errorText,
    this.maxLines = 1,
    this.minLines,
    this.obscureText = false,
    this.readOnly = false,
    this.prefixIcon,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? ClawColors.darkTextPrimary : ClawColors.lightTextPrimary;
    final hintColor =
        isDark ? ClawColors.darkTextTertiary : ClawColors.lightTextTertiary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: ClawTypography.label.copyWith(color: textColor),
          ),
          const SizedBox(height: 6),
        ],
        TextField(
          controller: controller,
          focusNode: focusNode,
          maxLines: maxLines,
          minLines: minLines,
          obscureText: obscureText,
          readOnly: readOnly,
          keyboardType: keyboardType,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: ClawTypography.bodyMedium.copyWith(color: textColor),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: ClawTypography.bodyMedium.copyWith(color: hintColor),
            errorText: errorText,
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, size: 18)
                : null,
            suffix: suffix,
            filled: true,
            fillColor:
                isDark ? ClawColors.darkElevated : ClawColors.lightElevated,
            border: OutlineInputBorder(
              borderRadius: ClawRadius.borderMd,
              borderSide: BorderSide(
                color: isDark ? ClawColors.darkBorder : ClawColors.lightBorder,
                width: 0.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: ClawRadius.borderMd,
              borderSide: BorderSide(
                color: isDark ? ClawColors.darkBorder : ClawColors.lightBorder,
                width: 0.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: ClawRadius.borderMd,
              borderSide: const BorderSide(
                color: ClawColors.amber,
                width: 1,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: ClawRadius.borderMd,
              borderSide: const BorderSide(
                color: ClawColors.error,
                width: 1,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// STATUS INDICATOR
// ────────────────────────────────────────────────────────────────────────────

enum ClawStatus { online, offline, busy, idle, error }

/// Online / offline / busy status dot with optional label.
class ClawStatusIndicator extends StatelessWidget {
  final ClawStatus status;
  final String? label;
  final double dotSize;
  final bool animated;

  const ClawStatusIndicator({
    super.key,
    required this.status,
    this.label,
    this.dotSize = 8,
    this.animated = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ClawStatus.online => ClawColors.success,
      ClawStatus.offline => ClawColors.darkTextDisabled,
      ClawStatus.busy => ClawColors.warning,
      ClawStatus.idle => ClawColors.darkTextTertiary,
      ClawStatus.error => ClawColors.error,
    };

    final dot = Container(
      width: dotSize,
      height: dotSize,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: (status == ClawStatus.online && animated)
            ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4)]
            : null,
      ),
    );

    if (label == null) return dot;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: 6),
        Text(
          label!,
          style: ClawTypography.caption.copyWith(
            color: Theme.of(context).brightness == Brightness.dark
                ? ClawColors.darkTextSecondary
                : ClawColors.lightTextSecondary,
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// TOOLTIP WRAPPER
// ────────────────────────────────────────────────────────────────────────────

/// Tooltip with custom styling matching design system.
class ClawTooltipWrapper extends StatelessWidget {
  final String message;
  final Widget child;
  final bool preferBelow;

  const ClawTooltipWrapper({
    super.key,
    required this.message,
    required this.child,
    this.preferBelow = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Tooltip(
      message: message,
      preferBelow: preferBelow,
      decoration: BoxDecoration(
        color: isDark ? ClawColors.darkTextPrimary : ClawColors.lightTextPrimary,
        borderRadius: ClawRadius.borderSm,
        boxShadow: ClawShadows.md,
      ),
      textStyle: ClawTypography.caption.copyWith(
        color: isDark ? ClawColors.darkBg : ClawColors.lightBg,
      ),
      waitDuration: const Duration(milliseconds: 500),
      child: child,
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// EMPTY STATE
// ────────────────────────────────────────────────────────────────────────────

/// Empty state placeholder with icon, message, and optional action.
class ClawEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const ClawEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor =
        isDark ? ClawColors.darkTextTertiary : ClawColors.lightTextTertiary;
    final textColor =
        isDark ? ClawColors.darkTextSecondary : ClawColors.lightTextSecondary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: mutedColor),
            const SizedBox(height: 16),
            Text(
              title,
              style: ClawTypography.heading4.copyWith(color: textColor),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: ClawTypography.bodyMedium.copyWith(color: mutedColor),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ClawButton(
                label: actionLabel!,
                onPressed: onAction,
                variant: ClawButtonVariant.secondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// CODE BLOCK
// ────────────────────────────────────────────────────────────────────────────

/// Styled code block with copy button and language label.
class ClawCodeBlock extends StatefulWidget {
  final String code;
  final String? language;
  final bool showLineNumbers;
  final int? maxLines;

  const ClawCodeBlock({
    super.key,
    required this.code,
    this.language,
    this.showLineNumbers = true,
    this.maxLines,
  });

  @override
  State<ClawCodeBlock> createState() => _ClawCodeBlockState();
}

class _ClawCodeBlockState extends State<ClawCodeBlock> {
  bool _copied = false;

  void _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.code.split('\n');
    final displayLines = widget.maxLines != null
        ? lines.take(widget.maxLines!).toList()
        : lines;
    final truncated =
        widget.maxLines != null && lines.length > widget.maxLines!;

    return Container(
      decoration: BoxDecoration(
        color: ClawColors.codeBg,
        borderRadius: ClawRadius.borderMd,
        border: Border.all(
          color: ClawColors.darkBorder,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: ClawColors.darkElevated,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(ClawRadius.md),
                topRight: Radius.circular(ClawRadius.md),
              ),
            ),
            child: Row(
              children: [
                if (widget.language != null)
                  Text(
                    widget.language!,
                    style: ClawTypography.caption.copyWith(
                      color: ClawColors.darkTextTertiary,
                    ),
                  ),
                const Spacer(),
                GestureDetector(
                  onTap: _copyToClipboard,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _copied ? Icons.check : Icons.copy,
                        size: 14,
                        color: _copied
                            ? ClawColors.success
                            : ClawColors.darkTextTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _copied ? 'Copied' : 'Copy',
                        style: ClawTypography.caption.copyWith(
                          color: _copied
                              ? ClawColors.success
                              : ClawColors.darkTextTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Code body
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < displayLines.length; i++)
                  Row(
                    children: [
                      if (widget.showLineNumbers)
                        SizedBox(
                          width: 36,
                          child: Text(
                            '${i + 1}',
                            style: ClawTypography.codeSmall.copyWith(
                              color: ClawColors.darkTextDisabled,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      if (widget.showLineNumbers)
                        const SizedBox(width: 12),
                      Text(
                        displayLines[i],
                        style: ClawTypography.codeMedium.copyWith(
                          color: ClawColors.codeText,
                        ),
                      ),
                    ],
                  ),
                if (truncated)
                  Padding(
                    padding: EdgeInsets.only(
                      left: widget.showLineNumbers ? 48 : 0,
                      top: 4,
                    ),
                    child: Text(
                      '... ${lines.length - widget.maxLines!} more lines',
                      style: ClawTypography.caption.copyWith(
                        color: ClawColors.darkTextTertiary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
