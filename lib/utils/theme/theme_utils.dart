// Port of openneomclaw theme.ts + systemTheme.ts + logoV2Utils.ts
//
// Theme detection, color palettes, logo layout, and display utilities
// for the neom_claw package.

import 'package:neom_claw/core/platform/claw_io.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Color;

// ---------------------------------------------------------------------------
// theme.ts  --  Theme type and palettes
// ---------------------------------------------------------------------------

/// All color keys used in the theme system.
class ClawTheme {
  const ClawTheme({
    required this.autoAccept,
    required this.bashBorder,
    required this.neomClaw,
    required this.neomClawShimmer,
    required this.neomClawBlueForSystemSpinner,
    required this.neomClawBlueShimmerForSystemSpinner,
    required this.permission,
    required this.permissionShimmer,
    required this.planMode,
    required this.ide,
    required this.promptBorder,
    required this.promptBorderShimmer,
    required this.text,
    required this.inverseText,
    required this.inactive,
    required this.inactiveShimmer,
    required this.subtle,
    required this.suggestion,
    required this.remember,
    required this.background,
    required this.success,
    required this.error,
    required this.warning,
    required this.merged,
    required this.warningShimmer,
    required this.diffAdded,
    required this.diffRemoved,
    required this.diffAddedDimmed,
    required this.diffRemovedDimmed,
    required this.diffAddedWord,
    required this.diffRemovedWord,
    required this.redForSubagents,
    required this.blueForSubagents,
    required this.greenForSubagents,
    required this.yellowForSubagents,
    required this.purpleForSubagents,
    required this.orangeForSubagents,
    required this.pinkForSubagents,
    required this.cyanForSubagents,
    required this.professionalBlue,
    required this.chromeYellow,
    required this.clawdBody,
    required this.clawdBackground,
    required this.userMessageBackground,
    required this.userMessageBackgroundHover,
    required this.messageActionsBackground,
    required this.selectionBg,
    required this.bashMessageBackgroundColor,
    required this.memoryBackgroundColor,
    required this.rateLimitFill,
    required this.rateLimitEmpty,
    required this.fastMode,
    required this.fastModeShimmer,
    required this.briefLabelYou,
    required this.briefLabelNeomClaw,
    required this.rainbowRed,
    required this.rainbowOrange,
    required this.rainbowYellow,
    required this.rainbowGreen,
    required this.rainbowBlue,
    required this.rainbowIndigo,
    required this.rainbowViolet,
    required this.rainbowRedShimmer,
    required this.rainbowOrangeShimmer,
    required this.rainbowYellowShimmer,
    required this.rainbowGreenShimmer,
    required this.rainbowBlueShimmer,
    required this.rainbowIndigoShimmer,
    required this.rainbowVioletShimmer,
  });

  final String autoAccept;
  final String bashBorder;
  final String neomClaw;
  final String neomClawShimmer;
  final String neomClawBlueForSystemSpinner;
  final String neomClawBlueShimmerForSystemSpinner;
  final String permission;
  final String permissionShimmer;
  final String planMode;
  final String ide;
  final String promptBorder;
  final String promptBorderShimmer;
  final String text;
  final String inverseText;
  final String inactive;
  final String inactiveShimmer;
  final String subtle;
  final String suggestion;
  final String remember;
  final String background;
  final String success;
  final String error;
  final String warning;
  final String merged;
  final String warningShimmer;
  final String diffAdded;
  final String diffRemoved;
  final String diffAddedDimmed;
  final String diffRemovedDimmed;
  final String diffAddedWord;
  final String diffRemovedWord;
  final String redForSubagents;
  final String blueForSubagents;
  final String greenForSubagents;
  final String yellowForSubagents;
  final String purpleForSubagents;
  final String orangeForSubagents;
  final String pinkForSubagents;
  final String cyanForSubagents;
  final String professionalBlue;
  final String chromeYellow;
  final String clawdBody;
  final String clawdBackground;
  final String userMessageBackground;
  final String userMessageBackgroundHover;
  final String messageActionsBackground;
  final String selectionBg;
  final String bashMessageBackgroundColor;
  final String memoryBackgroundColor;
  final String rateLimitFill;
  final String rateLimitEmpty;
  final String fastMode;
  final String fastModeShimmer;
  final String briefLabelYou;
  final String briefLabelNeomClaw;
  final String rainbowRed;
  final String rainbowOrange;
  final String rainbowYellow;
  final String rainbowGreen;
  final String rainbowBlue;
  final String rainbowIndigo;
  final String rainbowViolet;
  final String rainbowRedShimmer;
  final String rainbowOrangeShimmer;
  final String rainbowYellowShimmer;
  final String rainbowGreenShimmer;
  final String rainbowBlueShimmer;
  final String rainbowIndigoShimmer;
  final String rainbowVioletShimmer;
}

/// Available theme names.
enum ThemeName {
  dark,
  light,
  lightDaltonized,
  darkDaltonized,
  lightAnsi,
  darkAnsi;

  String get displayName {
    switch (this) {
      case ThemeName.dark:
        return 'dark';
      case ThemeName.light:
        return 'light';
      case ThemeName.lightDaltonized:
        return 'light-daltonized';
      case ThemeName.darkDaltonized:
        return 'dark-daltonized';
      case ThemeName.lightAnsi:
        return 'light-ansi';
      case ThemeName.darkAnsi:
        return 'dark-ansi';
    }
  }

  /// Parse a display name to a ThemeName.
  static ThemeName? fromDisplayName(String name) {
    switch (name) {
      case 'dark':
        return ThemeName.dark;
      case 'light':
        return ThemeName.light;
      case 'light-daltonized':
        return ThemeName.lightDaltonized;
      case 'dark-daltonized':
        return ThemeName.darkDaltonized;
      case 'light-ansi':
        return ThemeName.lightAnsi;
      case 'dark-ansi':
        return ThemeName.darkAnsi;
      default:
        return null;
    }
  }
}

/// Theme setting, including 'auto' which resolves at runtime.
enum ThemeSetting {
  auto,
  dark,
  light,
  lightDaltonized,
  darkDaltonized,
  lightAnsi,
  darkAnsi;

  String get displayName {
    switch (this) {
      case ThemeSetting.auto:
        return 'auto';
      case ThemeSetting.dark:
        return 'dark';
      case ThemeSetting.light:
        return 'light';
      case ThemeSetting.lightDaltonized:
        return 'light-daltonized';
      case ThemeSetting.darkDaltonized:
        return 'dark-daltonized';
      case ThemeSetting.lightAnsi:
        return 'light-ansi';
      case ThemeSetting.darkAnsi:
        return 'dark-ansi';
    }
  }
}

// ---------------------------------------------------------------------------
// Theme palettes
// ---------------------------------------------------------------------------

const _lightTheme = ClawTheme(
  autoAccept: 'rgb(135,0,255)',
  bashBorder: 'rgb(255,0,135)',
  neomClaw: 'rgb(215,119,87)',
  neomClawShimmer: 'rgb(245,149,117)',
  neomClawBlueForSystemSpinner: 'rgb(87,105,247)',
  neomClawBlueShimmerForSystemSpinner: 'rgb(117,135,255)',
  permission: 'rgb(87,105,247)',
  permissionShimmer: 'rgb(137,155,255)',
  planMode: 'rgb(0,102,102)',
  ide: 'rgb(71,130,200)',
  promptBorder: 'rgb(153,153,153)',
  promptBorderShimmer: 'rgb(183,183,183)',
  text: 'rgb(0,0,0)',
  inverseText: 'rgb(255,255,255)',
  inactive: 'rgb(102,102,102)',
  inactiveShimmer: 'rgb(142,142,142)',
  subtle: 'rgb(175,175,175)',
  suggestion: 'rgb(87,105,247)',
  remember: 'rgb(0,0,255)',
  background: 'rgb(0,153,153)',
  success: 'rgb(44,122,57)',
  error: 'rgb(171,43,63)',
  warning: 'rgb(150,108,30)',
  merged: 'rgb(135,0,255)',
  warningShimmer: 'rgb(200,158,80)',
  diffAdded: 'rgb(105,219,124)',
  diffRemoved: 'rgb(255,168,180)',
  diffAddedDimmed: 'rgb(199,225,203)',
  diffRemovedDimmed: 'rgb(253,210,216)',
  diffAddedWord: 'rgb(47,157,68)',
  diffRemovedWord: 'rgb(209,69,75)',
  redForSubagents: 'rgb(220,38,38)',
  blueForSubagents: 'rgb(37,99,235)',
  greenForSubagents: 'rgb(22,163,74)',
  yellowForSubagents: 'rgb(202,138,4)',
  purpleForSubagents: 'rgb(147,51,234)',
  orangeForSubagents: 'rgb(234,88,12)',
  pinkForSubagents: 'rgb(219,39,119)',
  cyanForSubagents: 'rgb(8,145,178)',
  professionalBlue: 'rgb(106,155,204)',
  chromeYellow: 'rgb(251,188,4)',
  clawdBody: 'rgb(215,119,87)',
  clawdBackground: 'rgb(0,0,0)',
  userMessageBackground: 'rgb(240,240,240)',
  userMessageBackgroundHover: 'rgb(252,252,252)',
  messageActionsBackground: 'rgb(232,236,244)',
  selectionBg: 'rgb(180,213,255)',
  bashMessageBackgroundColor: 'rgb(250,245,250)',
  memoryBackgroundColor: 'rgb(230,245,250)',
  rateLimitFill: 'rgb(87,105,247)',
  rateLimitEmpty: 'rgb(39,47,111)',
  fastMode: 'rgb(255,106,0)',
  fastModeShimmer: 'rgb(255,150,50)',
  briefLabelYou: 'rgb(37,99,235)',
  briefLabelNeomClaw: 'rgb(215,119,87)',
  rainbowRed: 'rgb(235,95,87)',
  rainbowOrange: 'rgb(245,139,87)',
  rainbowYellow: 'rgb(250,195,95)',
  rainbowGreen: 'rgb(145,200,130)',
  rainbowBlue: 'rgb(130,170,220)',
  rainbowIndigo: 'rgb(155,130,200)',
  rainbowViolet: 'rgb(200,130,180)',
  rainbowRedShimmer: 'rgb(250,155,147)',
  rainbowOrangeShimmer: 'rgb(255,185,137)',
  rainbowYellowShimmer: 'rgb(255,225,155)',
  rainbowGreenShimmer: 'rgb(185,230,180)',
  rainbowBlueShimmer: 'rgb(180,205,240)',
  rainbowIndigoShimmer: 'rgb(195,180,230)',
  rainbowVioletShimmer: 'rgb(230,180,210)',
);

const _darkTheme = ClawTheme(
  autoAccept: 'rgb(175,135,255)',
  bashBorder: 'rgb(253,93,177)',
  neomClaw: 'rgb(215,119,87)',
  neomClawShimmer: 'rgb(235,159,127)',
  neomClawBlueForSystemSpinner: 'rgb(147,165,255)',
  neomClawBlueShimmerForSystemSpinner: 'rgb(177,195,255)',
  permission: 'rgb(177,185,249)',
  permissionShimmer: 'rgb(207,215,255)',
  planMode: 'rgb(72,150,140)',
  ide: 'rgb(71,130,200)',
  promptBorder: 'rgb(136,136,136)',
  promptBorderShimmer: 'rgb(166,166,166)',
  text: 'rgb(255,255,255)',
  inverseText: 'rgb(0,0,0)',
  inactive: 'rgb(153,153,153)',
  inactiveShimmer: 'rgb(193,193,193)',
  subtle: 'rgb(80,80,80)',
  suggestion: 'rgb(177,185,249)',
  remember: 'rgb(177,185,249)',
  background: 'rgb(0,204,204)',
  success: 'rgb(78,186,101)',
  error: 'rgb(255,107,128)',
  warning: 'rgb(255,193,7)',
  merged: 'rgb(175,135,255)',
  warningShimmer: 'rgb(255,223,57)',
  diffAdded: 'rgb(34,92,43)',
  diffRemoved: 'rgb(122,41,54)',
  diffAddedDimmed: 'rgb(71,88,74)',
  diffRemovedDimmed: 'rgb(105,72,77)',
  diffAddedWord: 'rgb(56,166,96)',
  diffRemovedWord: 'rgb(179,89,107)',
  redForSubagents: 'rgb(220,38,38)',
  blueForSubagents: 'rgb(37,99,235)',
  greenForSubagents: 'rgb(22,163,74)',
  yellowForSubagents: 'rgb(202,138,4)',
  purpleForSubagents: 'rgb(147,51,234)',
  orangeForSubagents: 'rgb(234,88,12)',
  pinkForSubagents: 'rgb(219,39,119)',
  cyanForSubagents: 'rgb(8,145,178)',
  professionalBlue: 'rgb(106,155,204)',
  chromeYellow: 'rgb(251,188,4)',
  clawdBody: 'rgb(215,119,87)',
  clawdBackground: 'rgb(0,0,0)',
  userMessageBackground: 'rgb(55,55,55)',
  userMessageBackgroundHover: 'rgb(70,70,70)',
  messageActionsBackground: 'rgb(44,50,62)',
  selectionBg: 'rgb(38,79,120)',
  bashMessageBackgroundColor: 'rgb(65,60,65)',
  memoryBackgroundColor: 'rgb(55,65,70)',
  rateLimitFill: 'rgb(177,185,249)',
  rateLimitEmpty: 'rgb(80,83,112)',
  fastMode: 'rgb(255,120,20)',
  fastModeShimmer: 'rgb(255,165,70)',
  briefLabelYou: 'rgb(122,180,232)',
  briefLabelNeomClaw: 'rgb(215,119,87)',
  rainbowRed: 'rgb(235,95,87)',
  rainbowOrange: 'rgb(245,139,87)',
  rainbowYellow: 'rgb(250,195,95)',
  rainbowGreen: 'rgb(145,200,130)',
  rainbowBlue: 'rgb(130,170,220)',
  rainbowIndigo: 'rgb(155,130,200)',
  rainbowViolet: 'rgb(200,130,180)',
  rainbowRedShimmer: 'rgb(250,155,147)',
  rainbowOrangeShimmer: 'rgb(255,185,137)',
  rainbowYellowShimmer: 'rgb(255,225,155)',
  rainbowGreenShimmer: 'rgb(185,230,180)',
  rainbowBlueShimmer: 'rgb(180,205,240)',
  rainbowIndigoShimmer: 'rgb(195,180,230)',
  rainbowVioletShimmer: 'rgb(230,180,210)',
);

const _lightDaltonizedTheme = ClawTheme(
  autoAccept: 'rgb(135,0,255)',
  bashBorder: 'rgb(0,102,204)',
  neomClaw: 'rgb(255,153,51)',
  neomClawShimmer: 'rgb(255,183,101)',
  neomClawBlueForSystemSpinner: 'rgb(51,102,255)',
  neomClawBlueShimmerForSystemSpinner: 'rgb(101,152,255)',
  permission: 'rgb(51,102,255)',
  permissionShimmer: 'rgb(101,152,255)',
  planMode: 'rgb(51,102,102)',
  ide: 'rgb(71,130,200)',
  promptBorder: 'rgb(153,153,153)',
  promptBorderShimmer: 'rgb(183,183,183)',
  text: 'rgb(0,0,0)',
  inverseText: 'rgb(255,255,255)',
  inactive: 'rgb(102,102,102)',
  inactiveShimmer: 'rgb(142,142,142)',
  subtle: 'rgb(175,175,175)',
  suggestion: 'rgb(51,102,255)',
  remember: 'rgb(51,102,255)',
  background: 'rgb(0,153,153)',
  success: 'rgb(0,102,153)',
  error: 'rgb(204,0,0)',
  warning: 'rgb(255,153,0)',
  merged: 'rgb(135,0,255)',
  warningShimmer: 'rgb(255,183,50)',
  diffAdded: 'rgb(153,204,255)',
  diffRemoved: 'rgb(255,204,204)',
  diffAddedDimmed: 'rgb(209,231,253)',
  diffRemovedDimmed: 'rgb(255,233,233)',
  diffAddedWord: 'rgb(51,102,204)',
  diffRemovedWord: 'rgb(153,51,51)',
  redForSubagents: 'rgb(204,0,0)',
  blueForSubagents: 'rgb(0,102,204)',
  greenForSubagents: 'rgb(0,204,0)',
  yellowForSubagents: 'rgb(255,204,0)',
  purpleForSubagents: 'rgb(128,0,128)',
  orangeForSubagents: 'rgb(255,128,0)',
  pinkForSubagents: 'rgb(255,102,178)',
  cyanForSubagents: 'rgb(0,178,178)',
  professionalBlue: 'rgb(106,155,204)',
  chromeYellow: 'rgb(251,188,4)',
  clawdBody: 'rgb(215,119,87)',
  clawdBackground: 'rgb(0,0,0)',
  userMessageBackground: 'rgb(220,220,220)',
  userMessageBackgroundHover: 'rgb(232,232,232)',
  messageActionsBackground: 'rgb(210,216,226)',
  selectionBg: 'rgb(180,213,255)',
  bashMessageBackgroundColor: 'rgb(250,245,250)',
  memoryBackgroundColor: 'rgb(230,245,250)',
  rateLimitFill: 'rgb(51,102,255)',
  rateLimitEmpty: 'rgb(23,46,114)',
  fastMode: 'rgb(255,106,0)',
  fastModeShimmer: 'rgb(255,150,50)',
  briefLabelYou: 'rgb(37,99,235)',
  briefLabelNeomClaw: 'rgb(255,153,51)',
  rainbowRed: 'rgb(235,95,87)',
  rainbowOrange: 'rgb(245,139,87)',
  rainbowYellow: 'rgb(250,195,95)',
  rainbowGreen: 'rgb(145,200,130)',
  rainbowBlue: 'rgb(130,170,220)',
  rainbowIndigo: 'rgb(155,130,200)',
  rainbowViolet: 'rgb(200,130,180)',
  rainbowRedShimmer: 'rgb(250,155,147)',
  rainbowOrangeShimmer: 'rgb(255,185,137)',
  rainbowYellowShimmer: 'rgb(255,225,155)',
  rainbowGreenShimmer: 'rgb(185,230,180)',
  rainbowBlueShimmer: 'rgb(180,205,240)',
  rainbowIndigoShimmer: 'rgb(195,180,230)',
  rainbowVioletShimmer: 'rgb(230,180,210)',
);

const _darkDaltonizedTheme = ClawTheme(
  autoAccept: 'rgb(175,135,255)',
  bashBorder: 'rgb(51,153,255)',
  neomClaw: 'rgb(255,153,51)',
  neomClawShimmer: 'rgb(255,183,101)',
  neomClawBlueForSystemSpinner: 'rgb(153,204,255)',
  neomClawBlueShimmerForSystemSpinner: 'rgb(183,224,255)',
  permission: 'rgb(153,204,255)',
  permissionShimmer: 'rgb(183,224,255)',
  planMode: 'rgb(102,153,153)',
  ide: 'rgb(71,130,200)',
  promptBorder: 'rgb(136,136,136)',
  promptBorderShimmer: 'rgb(166,166,166)',
  text: 'rgb(255,255,255)',
  inverseText: 'rgb(0,0,0)',
  inactive: 'rgb(153,153,153)',
  inactiveShimmer: 'rgb(193,193,193)',
  subtle: 'rgb(80,80,80)',
  suggestion: 'rgb(153,204,255)',
  remember: 'rgb(153,204,255)',
  background: 'rgb(0,204,204)',
  success: 'rgb(51,153,255)',
  error: 'rgb(255,102,102)',
  warning: 'rgb(255,204,0)',
  merged: 'rgb(175,135,255)',
  warningShimmer: 'rgb(255,234,50)',
  diffAdded: 'rgb(0,68,102)',
  diffRemoved: 'rgb(102,0,0)',
  diffAddedDimmed: 'rgb(62,81,91)',
  diffRemovedDimmed: 'rgb(62,44,44)',
  diffAddedWord: 'rgb(0,119,179)',
  diffRemovedWord: 'rgb(179,0,0)',
  redForSubagents: 'rgb(255,102,102)',
  blueForSubagents: 'rgb(102,178,255)',
  greenForSubagents: 'rgb(102,255,102)',
  yellowForSubagents: 'rgb(255,255,102)',
  purpleForSubagents: 'rgb(178,102,255)',
  orangeForSubagents: 'rgb(255,178,102)',
  pinkForSubagents: 'rgb(255,153,204)',
  cyanForSubagents: 'rgb(102,204,204)',
  professionalBlue: 'rgb(106,155,204)',
  chromeYellow: 'rgb(251,188,4)',
  clawdBody: 'rgb(215,119,87)',
  clawdBackground: 'rgb(0,0,0)',
  userMessageBackground: 'rgb(55,55,55)',
  userMessageBackgroundHover: 'rgb(70,70,70)',
  messageActionsBackground: 'rgb(44,50,62)',
  selectionBg: 'rgb(38,79,120)',
  bashMessageBackgroundColor: 'rgb(65,60,65)',
  memoryBackgroundColor: 'rgb(55,65,70)',
  rateLimitFill: 'rgb(153,204,255)',
  rateLimitEmpty: 'rgb(69,92,115)',
  fastMode: 'rgb(255,120,20)',
  fastModeShimmer: 'rgb(255,165,70)',
  briefLabelYou: 'rgb(122,180,232)',
  briefLabelNeomClaw: 'rgb(255,153,51)',
  rainbowRed: 'rgb(235,95,87)',
  rainbowOrange: 'rgb(245,139,87)',
  rainbowYellow: 'rgb(250,195,95)',
  rainbowGreen: 'rgb(145,200,130)',
  rainbowBlue: 'rgb(130,170,220)',
  rainbowIndigo: 'rgb(155,130,200)',
  rainbowViolet: 'rgb(200,130,180)',
  rainbowRedShimmer: 'rgb(250,155,147)',
  rainbowOrangeShimmer: 'rgb(255,185,137)',
  rainbowYellowShimmer: 'rgb(255,225,155)',
  rainbowGreenShimmer: 'rgb(185,230,180)',
  rainbowBlueShimmer: 'rgb(180,205,240)',
  rainbowIndigoShimmer: 'rgb(195,180,230)',
  rainbowVioletShimmer: 'rgb(230,180,210)',
);

// ANSI themes use ANSI color names instead of RGB
const _lightAnsiTheme = ClawTheme(
  autoAccept: 'ansi:magenta', bashBorder: 'ansi:magenta',
  neomClaw: 'ansi:redBright', neomClawShimmer: 'ansi:yellowBright',
  neomClawBlueForSystemSpinner: 'ansi:blue',
  neomClawBlueShimmerForSystemSpinner: 'ansi:blueBright',
  permission: 'ansi:blue', permissionShimmer: 'ansi:blueBright',
  planMode: 'ansi:cyan', ide: 'ansi:blueBright',
  promptBorder: 'ansi:white', promptBorderShimmer: 'ansi:whiteBright',
  text: 'ansi:black', inverseText: 'ansi:white',
  inactive: 'ansi:blackBright', inactiveShimmer: 'ansi:white',
  subtle: 'ansi:blackBright', suggestion: 'ansi:blue',
  remember: 'ansi:blue', background: 'ansi:cyan',
  success: 'ansi:green', error: 'ansi:red',
  warning: 'ansi:yellow', merged: 'ansi:magenta',
  warningShimmer: 'ansi:yellowBright',
  diffAdded: 'ansi:green', diffRemoved: 'ansi:red',
  diffAddedDimmed: 'ansi:green', diffRemovedDimmed: 'ansi:red',
  diffAddedWord: 'ansi:greenBright', diffRemovedWord: 'ansi:redBright',
  redForSubagents: 'ansi:red', blueForSubagents: 'ansi:blue',
  greenForSubagents: 'ansi:green', yellowForSubagents: 'ansi:yellow',
  purpleForSubagents: 'ansi:magenta', orangeForSubagents: 'ansi:redBright',
  pinkForSubagents: 'ansi:magentaBright', cyanForSubagents: 'ansi:cyan',
  professionalBlue: 'ansi:blueBright', chromeYellow: 'ansi:yellow',
  clawdBody: 'ansi:redBright', clawdBackground: 'ansi:black',
  userMessageBackground: 'ansi:white',
  userMessageBackgroundHover: 'ansi:whiteBright',
  messageActionsBackground: 'ansi:white',
  selectionBg: 'ansi:cyan',
  bashMessageBackgroundColor: 'ansi:whiteBright',
  memoryBackgroundColor: 'ansi:white',
  rateLimitFill: 'ansi:yellow', rateLimitEmpty: 'ansi:black',
  fastMode: 'ansi:red', fastModeShimmer: 'ansi:redBright',
  briefLabelYou: 'ansi:blue', briefLabelNeomClaw: 'ansi:redBright',
  rainbowRed: 'ansi:red', rainbowOrange: 'ansi:redBright',
  rainbowYellow: 'ansi:yellow', rainbowGreen: 'ansi:green',
  rainbowBlue: 'ansi:cyan', rainbowIndigo: 'ansi:blue',
  rainbowViolet: 'ansi:magenta',
  rainbowRedShimmer: 'ansi:redBright', rainbowOrangeShimmer: 'ansi:yellow',
  rainbowYellowShimmer: 'ansi:yellowBright', rainbowGreenShimmer: 'ansi:greenBright',
  rainbowBlueShimmer: 'ansi:cyanBright', rainbowIndigoShimmer: 'ansi:blueBright',
  rainbowVioletShimmer: 'ansi:magentaBright',
);

const _darkAnsiTheme = ClawTheme(
  autoAccept: 'ansi:magentaBright', bashBorder: 'ansi:magentaBright',
  neomClaw: 'ansi:redBright', neomClawShimmer: 'ansi:yellowBright',
  neomClawBlueForSystemSpinner: 'ansi:blueBright',
  neomClawBlueShimmerForSystemSpinner: 'ansi:blueBright',
  permission: 'ansi:blueBright', permissionShimmer: 'ansi:blueBright',
  planMode: 'ansi:cyanBright', ide: 'ansi:blue',
  promptBorder: 'ansi:white', promptBorderShimmer: 'ansi:whiteBright',
  text: 'ansi:whiteBright', inverseText: 'ansi:black',
  inactive: 'ansi:white', inactiveShimmer: 'ansi:whiteBright',
  subtle: 'ansi:white', suggestion: 'ansi:blueBright',
  remember: 'ansi:blueBright', background: 'ansi:cyanBright',
  success: 'ansi:greenBright', error: 'ansi:redBright',
  warning: 'ansi:yellowBright', merged: 'ansi:magentaBright',
  warningShimmer: 'ansi:yellowBright',
  diffAdded: 'ansi:green', diffRemoved: 'ansi:red',
  diffAddedDimmed: 'ansi:green', diffRemovedDimmed: 'ansi:red',
  diffAddedWord: 'ansi:greenBright', diffRemovedWord: 'ansi:redBright',
  redForSubagents: 'ansi:redBright', blueForSubagents: 'ansi:blueBright',
  greenForSubagents: 'ansi:greenBright', yellowForSubagents: 'ansi:yellowBright',
  purpleForSubagents: 'ansi:magentaBright', orangeForSubagents: 'ansi:redBright',
  pinkForSubagents: 'ansi:magentaBright', cyanForSubagents: 'ansi:cyanBright',
  professionalBlue: 'rgb(106,155,204)', chromeYellow: 'ansi:yellowBright',
  clawdBody: 'ansi:redBright', clawdBackground: 'ansi:black',
  userMessageBackground: 'ansi:blackBright',
  userMessageBackgroundHover: 'ansi:white',
  messageActionsBackground: 'ansi:blackBright',
  selectionBg: 'ansi:blue',
  bashMessageBackgroundColor: 'ansi:black',
  memoryBackgroundColor: 'ansi:blackBright',
  rateLimitFill: 'ansi:yellow', rateLimitEmpty: 'ansi:white',
  fastMode: 'ansi:redBright', fastModeShimmer: 'ansi:redBright',
  briefLabelYou: 'ansi:blueBright', briefLabelNeomClaw: 'ansi:redBright',
  rainbowRed: 'ansi:red', rainbowOrange: 'ansi:redBright',
  rainbowYellow: 'ansi:yellow', rainbowGreen: 'ansi:green',
  rainbowBlue: 'ansi:cyan', rainbowIndigo: 'ansi:blue',
  rainbowViolet: 'ansi:magenta',
  rainbowRedShimmer: 'ansi:redBright', rainbowOrangeShimmer: 'ansi:yellow',
  rainbowYellowShimmer: 'ansi:yellowBright', rainbowGreenShimmer: 'ansi:greenBright',
  rainbowBlueShimmer: 'ansi:cyanBright', rainbowIndigoShimmer: 'ansi:blueBright',
  rainbowVioletShimmer: 'ansi:magentaBright',
);

/// Get a theme palette by name.
ClawTheme getTheme(ThemeName themeName) {
  switch (themeName) {
    case ThemeName.light:
      return _lightTheme;
    case ThemeName.lightAnsi:
      return _lightAnsiTheme;
    case ThemeName.darkAnsi:
      return _darkAnsiTheme;
    case ThemeName.lightDaltonized:
      return _lightDaltonizedTheme;
    case ThemeName.darkDaltonized:
      return _darkDaltonizedTheme;
    case ThemeName.dark:
      return _darkTheme;
  }
}

/// Parse an RGB color string like "rgb(255,0,128)" into a Flutter Color.
Color? parseRgbColor(String themeColor) {
  final match =
      RegExp(r'rgb\(\s?(\d+),\s?(\d+),\s?(\d+)\s?\)').firstMatch(themeColor);
  if (match == null) return null;
  return Color.fromARGB(
    255,
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

// ---------------------------------------------------------------------------
// systemTheme.ts  --  dark/light mode detection
// ---------------------------------------------------------------------------

/// System (terminal) theme.
enum SystemTheme { dark, light }

SystemTheme? _cachedSystemTheme;

/// Get the current terminal theme.
SystemTheme getSystemThemeName() {
  _cachedSystemTheme ??= _detectFromColorFgBg() ?? SystemTheme.dark;
  return _cachedSystemTheme!;
}

/// Update the cached terminal theme (called by watcher on OSC 11 response).
void setCachedSystemTheme(SystemTheme theme) {
  _cachedSystemTheme = theme;
}

/// Resolve a ThemeSetting to a concrete ThemeName.
ThemeName resolveThemeSetting(ThemeSetting setting) {
  if (setting == ThemeSetting.auto) {
    return getSystemThemeName() == SystemTheme.light
        ? ThemeName.light
        : ThemeName.dark;
  }
  // Map ThemeSetting values to ThemeName
  switch (setting) {
    case ThemeSetting.dark:
      return ThemeName.dark;
    case ThemeSetting.light:
      return ThemeName.light;
    case ThemeSetting.lightDaltonized:
      return ThemeName.lightDaltonized;
    case ThemeSetting.darkDaltonized:
      return ThemeName.darkDaltonized;
    case ThemeSetting.lightAnsi:
      return ThemeName.lightAnsi;
    case ThemeSetting.darkAnsi:
      return ThemeName.darkAnsi;
    case ThemeSetting.auto:
      // Already handled above, but required for exhaustive switch
      return ThemeName.dark;
  }
}

/// Parse an OSC color response data string into a theme.
SystemTheme? themeFromOscColor(String data) {
  final rgb = _parseOscRgb(data);
  if (rgb == null) return null;
  // ITU-R BT.709 relative luminance
  final luminance = 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b;
  return luminance > 0.5 ? SystemTheme.light : SystemTheme.dark;
}

class _Rgb {
  const _Rgb(this.r, this.g, this.b);
  final double r;
  final double g;
  final double b;
}

_Rgb? _parseOscRgb(String data) {
  // rgb:RRRR/GGGG/BBBB format
  final rgbMatch =
      RegExp(r'^rgba?:([0-9a-f]{1,4})/([0-9a-f]{1,4})/([0-9a-f]{1,4})', caseSensitive: false)
          .firstMatch(data);
  if (rgbMatch != null) {
    return _Rgb(
      _hexComponent(rgbMatch.group(1)!),
      _hexComponent(rgbMatch.group(2)!),
      _hexComponent(rgbMatch.group(3)!),
    );
  }

  // #RRGGBB or #RRRRGGGGBBBB
  final hashMatch = RegExp(r'^#([0-9a-f]+)$', caseSensitive: false).firstMatch(data);
  if (hashMatch != null && hashMatch.group(1)!.length % 3 == 0) {
    final hex = hashMatch.group(1)!;
    final n = hex.length ~/ 3;
    return _Rgb(
      _hexComponent(hex.substring(0, n)),
      _hexComponent(hex.substring(n, 2 * n)),
      _hexComponent(hex.substring(2 * n)),
    );
  }

  return null;
}

/// Normalize a 1-4 digit hex component to [0, 1].
double _hexComponent(String hex) {
  final maxVal = math.pow(16, hex.length).toInt() - 1;
  return int.parse(hex, radix: 16) / maxVal;
}

/// Detect from $COLORFGBG env var (synchronous initial guess).
SystemTheme? _detectFromColorFgBg() {
  final colorfgbg = Platform.environment['COLORFGBG'];
  if (colorfgbg == null) return null;
  final parts = colorfgbg.split(';');
  final bg = parts.last;
  if (bg.isEmpty) return null;
  final bgNum = int.tryParse(bg);
  if (bgNum == null || bgNum < 0 || bgNum > 15) return null;
  return bgNum <= 6 || bgNum == 8 ? SystemTheme.dark : SystemTheme.light;
}

// ---------------------------------------------------------------------------
// logoV2Utils.ts  --  layout and display helpers
// ---------------------------------------------------------------------------

/// Layout mode for the logo.
enum LayoutMode { horizontal, compact }

/// Layout dimensions for the Logo component.
class LayoutDimensions {
  const LayoutDimensions({
    required this.leftWidth,
    required this.rightWidth,
    required this.totalWidth,
  });

  final int leftWidth;
  final int rightWidth;
  final int totalWidth;
}

// Layout constants
const _maxLeftWidth = 50;
const _maxUsernameLength = 20;
const _borderPadding = 4;
const _dividerWidth = 1;
const _contentPadding = 2;

/// Determine layout mode based on terminal width.
LayoutMode getLayoutMode(int columns) {
  return columns >= 70 ? LayoutMode.horizontal : LayoutMode.compact;
}

/// Calculate layout dimensions for the Logo component.
LayoutDimensions calculateLayoutDimensions({
  required int columns,
  required LayoutMode layoutMode,
  required int optimalLeftWidth,
}) {
  if (layoutMode == LayoutMode.horizontal) {
    final leftWidth = optimalLeftWidth;
    final usedSpace =
        _borderPadding + _contentPadding + _dividerWidth + leftWidth;
    final availableForRight = columns - usedSpace;

    var rightWidth = math.max(30, availableForRight);
    var totalWidth = math.min(
      leftWidth + rightWidth + _dividerWidth + _contentPadding,
      columns - _borderPadding,
    );

    if (totalWidth < leftWidth + rightWidth + _dividerWidth + _contentPadding) {
      rightWidth = totalWidth - leftWidth - _dividerWidth - _contentPadding;
    }

    return LayoutDimensions(
      leftWidth: leftWidth,
      rightWidth: rightWidth,
      totalWidth: totalWidth,
    );
  }

  // Compact mode
  final totalWidth = math.min(columns - _borderPadding, _maxLeftWidth + 20);
  return LayoutDimensions(
    leftWidth: totalWidth,
    rightWidth: totalWidth,
    totalWidth: totalWidth,
  );
}

/// Calculate optimal left panel width based on content.
int calculateOptimalLeftWidth({
  required String welcomeMessage,
  required String truncatedCwd,
  required String modelLine,
}) {
  final contentWidth = [
    welcomeMessage.length,
    truncatedCwd.length,
    modelLine.length,
    20, // Minimum for clawd art
  ].reduce(math.max);
  return math.min(contentWidth + 4, _maxLeftWidth);
}

/// Format a welcome message based on username.
String formatWelcomeMessage(String? username) {
  if (username == null || username.length > _maxUsernameLength) {
    return 'Welcome to Open NeomClaw';
  }
  return 'Welcome back, $username';
}

/// Truncate a path in the middle if too long (width-aware).
String truncatePath(String path, int maxLength) {
  if (path.length <= maxLength) return path;

  const separator = '/';
  const ellipsis = '\u2026';
  const ellipsisWidth = 1;
  const separatorWidth = 1;

  final parts = path.split(separator);
  final first = parts.first;
  final last = parts.last;

  if (parts.length == 1) {
    if (path.length <= maxLength) return path;
    return '${path.substring(0, maxLength - 1)}$ellipsis';
  }

  if (first.isEmpty &&
      ellipsisWidth + separatorWidth + last.length >= maxLength) {
    final truncLen = math.max(1, maxLength - separatorWidth);
    return '$separator${last.length <= truncLen ? last : '${last.substring(0, truncLen - 1)}$ellipsis'}';
  }

  if (first.isNotEmpty &&
      ellipsisWidth * 2 + separatorWidth + last.length >= maxLength) {
    final truncLen = math.max(1, maxLength - ellipsisWidth - separatorWidth);
    return '$ellipsis$separator${last.length <= truncLen ? last : '${last.substring(0, truncLen - 1)}$ellipsis'}';
  }

  if (parts.length == 2) {
    final availableForFirst =
        maxLength - ellipsisWidth - separatorWidth - last.length;
    final truncFirst = availableForFirst > 0 && availableForFirst < first.length
        ? first.substring(0, availableForFirst)
        : first;
    return '$truncFirst$ellipsis$separator$last';
  }

  var available =
      maxLength - first.length - last.length - ellipsisWidth - 2 * separatorWidth;

  if (available <= 0) {
    final availableForFirst = math.max(
      0,
      maxLength - last.length - ellipsisWidth - 2 * separatorWidth,
    );
    final truncFirst =
        availableForFirst < first.length && availableForFirst > 0
            ? first.substring(0, availableForFirst)
            : first;
    return '$truncFirst$separator$ellipsis$separator$last';
  }

  final middleParts = <String>[];
  for (var i = parts.length - 2; i > 0; i--) {
    final part = parts[i];
    if (part.length + separatorWidth <= available) {
      middleParts.insert(0, part);
      available -= part.length + separatorWidth;
    } else {
      break;
    }
  }

  if (middleParts.isEmpty) {
    return '$first$separator$ellipsis$separator$last';
  }

  return '$first$separator$ellipsis$separator${middleParts.join(separator)}$separator$last';
}

/// Determine how to display model and billing info.
({bool shouldSplit, String truncatedModel, String truncatedBilling})
    formatModelAndBilling({
  required String modelName,
  required String billingType,
  required int availableWidth,
}) {
  const separator = ' \u00b7 ';
  final combinedWidth =
      modelName.length + separator.length + billingType.length;
  final shouldSplit = combinedWidth > availableWidth;

  if (shouldSplit) {
    return (
      shouldSplit: true,
      truncatedModel: modelName.length > availableWidth
          ? '${modelName.substring(0, availableWidth - 1)}\u2026'
          : modelName,
      truncatedBilling: billingType.length > availableWidth
          ? '${billingType.substring(0, availableWidth - 1)}\u2026'
          : billingType,
    );
  }

  final maxModelWidth = math.max(
    availableWidth - billingType.length - separator.length,
    10,
  );
  return (
    shouldSplit: false,
    truncatedModel: modelName.length > maxModelWidth
        ? '${modelName.substring(0, maxModelWidth - 1)}\u2026'
        : modelName,
    truncatedBilling: billingType,
  );
}

/// Format a release note for display.
String formatReleaseNoteForDisplay(String note, int maxWidth) {
  if (note.length <= maxWidth) return note;
  return '${note.substring(0, maxWidth - 1)}\u2026';
}
