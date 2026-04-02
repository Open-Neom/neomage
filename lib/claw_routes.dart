import 'package:sint/sint.dart';

import 'ui/screens/chat_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/splash_screen.dart';

/// Route constants — single source of truth for navigation paths.
class ClawRouteConstants {
  static const String root = '/';
  static const String onboarding = '/onboarding';
  static const String chat = '/chat';
  static const String settings = '/settings';
}

/// App routes — aggregated from all modules.
class ClawRoutes {
  static List<SintPage> getAppRoutes() => [
        SintPage(
          name: ClawRouteConstants.root,
          page: () => const SplashScreen(),
        ),
        SintPage(
          name: ClawRouteConstants.onboarding,
          page: () => const OnboardingScreen(),
          transition: Transition.fadeIn,
        ),
        SintPage(
          name: ClawRouteConstants.chat,
          page: () => const ChatScreen(),
          transition: Transition.rightToLeft,
        ),
        SintPage(
          name: ClawRouteConstants.settings,
          page: () => const SettingsScreen(),
          transition: Transition.rightToLeft,
        ),
      ];
}
