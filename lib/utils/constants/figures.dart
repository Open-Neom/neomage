import 'dart:io' show Platform;

/// Unicode figure constants — ported from OpenClaude src/constants/figures.ts.

final String blackCircle = Platform.isMacOS ? '\u23fa' : '\u25cf'; // ⏺ or ●
const String bulletOperator = '\u2219'; // ∙
const String teardropAsterisk = '\u273b'; // ✻
const String upArrow = '\u2191'; // ↑
const String downArrow = '\u2193'; // ↓
const String lightningBolt = '\u21af'; // ↯
const String effortLow = '\u25cb'; // ○
const String effortMedium = '\u25d0'; // ◐
const String effortHigh = '\u25cf'; // ●
const String effortMax = '\u25c9'; // ◉

// Media/trigger status
const String playIcon = '\u25b6'; // ▶
const String pauseIcon = '\u23f8'; // ⏸

// MCP subscription indicators
const String refreshArrow = '\u21bb'; // ↻
const String channelArrow = '\u2190'; // ←
const String injectedArrow = '\u2192'; // →
const String forkGlyph = '\u2442'; // ⑂

// Review status (ultrareview diamond states)
const String diamondOpen = '\u25c7'; // ◇
const String diamondFilled = '\u25c6'; // ◆
const String referenceMark = '\u203b'; // ※

// Issue flag
const String flagIcon = '\u2691'; // ⚑

// Blockquote
const String blockquoteBar = '\u258e'; // ▎
const String heavyHorizontal = '\u2501'; // ━

// Bridge status
const List<String> bridgeSpinnerFrames = [
  '\u00b7|\u00b7',
  '\u00b7/\u00b7',
  '\u00b7\u2014\u00b7',
  '\u00b7\\\u00b7',
];
const String bridgeReadyIndicator = '\u00b7\u2714\ufe0e\u00b7';
const String bridgeFailedIndicator = '\u00d7';
