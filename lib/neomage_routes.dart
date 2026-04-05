import 'package:flutter/material.dart';
import 'package:sint/sint.dart';

import 'ui/screens/chat_screen.dart';
import 'ui/screens/doctor_screen.dart';
import 'ui/screens/mcp_panel_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/session_browser_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/choose_agent_screen.dart';
import 'ui/screens/splash_screen.dart';

// ---------------------------------------------------------------------------
// Route constants — single source of truth for navigation paths.
// ---------------------------------------------------------------------------

class NeomageRouteConstants {
  NeomageRouteConstants._();

  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String chat = '/chat';
  static const String settings = '/settings';
  static const String sessionBrowser = '/sessions';
  static const String mcpPanel = '/mcp';
  static const String doctor = '/doctor';
  static const String permissions = '/permissions';
  static const String logs = '/logs';
  static const String agents = '/agents';
  static const String tasks = '/tasks';
  static const String about = '/about';
  static const String chooseAgent = '/choose-agent';

  // Keep the old `root` alias for back-compat with main.dart.
  static const String root = splash;
}

// ---------------------------------------------------------------------------
// App routes — aggregated from all modules.
// ---------------------------------------------------------------------------

class NeomageRoutes {
  static List<SintPage> getAppRoutes() => [
    // -- Main screens (fade transition) --------------------------------
    SintPage(
      name: NeomageRouteConstants.splash,
      page: () => const SplashScreen(),
      transition: Transition.fadeIn,
    ),
    SintPage(
      name: NeomageRouteConstants.onboarding,
      page: () => const OnboardingScreen(),
      transition: Transition.fadeIn,
    ),
    SintPage(
      name: NeomageRouteConstants.chat,
      page: () => const ChatScreen(),
      transition: Transition.fadeIn,
    ),

    // -- Secondary screens (slide transition) --------------------------
    SintPage(
      name: NeomageRouteConstants.settings,
      page: () => const SettingsScreen(),
      transition: Transition.rightToLeft,
    ),
    SintPage(
      name: NeomageRouteConstants.sessionBrowser,
      page: () => const SessionBrowserScreen(),
      transition: Transition.rightToLeft,
    ),
    SintPage(
      name: NeomageRouteConstants.mcpPanel,
      page: () => const McpPanelScreen(),
      transition: Transition.rightToLeft,
    ),
    SintPage(
      name: NeomageRouteConstants.doctor,
      page: () => const DoctorScreen(),
      transition: Transition.rightToLeft,
    ),
    SintPage(
      name: NeomageRouteConstants.chooseAgent,
      page: () => const ChooseAgentPage(),
      transition: Transition.rightToLeft,
    ),
    SintPage(
      name: NeomageRouteConstants.permissions,
      page: () => const _PlaceholderScreen(title: 'Permissions'),
      transition: Transition.rightToLeft,
    ),
    SintPage(
      name: NeomageRouteConstants.logs,
      page: () => const _PlaceholderScreen(title: 'Logs'),
      transition: Transition.rightToLeft,
    ),
    SintPage(
      name: NeomageRouteConstants.agents,
      page: () => const _PlaceholderScreen(title: 'Agents'),
      transition: Transition.rightToLeft,
    ),
    SintPage(
      name: NeomageRouteConstants.tasks,
      page: () => const _PlaceholderScreen(title: 'Tasks'),
      transition: Transition.rightToLeft,
    ),
    SintPage(
      name: NeomageRouteConstants.about,
      page: () => const _PlaceholderScreen(title: 'About'),
      transition: Transition.rightToLeft,
    ),
  ];

  /// Unknown-route handler — returns a simple 404 page.
  static SintPage get unknownRoute => SintPage(
    name: '/not-found',
    page: () => const _NotFoundScreen(),
    transition: Transition.fadeIn,
  );
}

// ---------------------------------------------------------------------------
// Route guards
// ---------------------------------------------------------------------------

/// Middleware that redirects to onboarding when the user has not completed it.
class OnboardingGuard extends SintMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    // TODO: check persistent flag via ConfigService
    // final completed = Sint.find<ConfigService>().onboardingCompleted;
    // if (!completed) return const RouteSettings(name: NeomageRouteConstants.onboarding);
    return null;
  }
}

/// Middleware that redirects to onboarding/login when no API key is present.
class AuthGuard extends SintMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    // TODO: check API key presence via ConfigService
    // final hasKey = Sint.find<ConfigService>().hasApiKey;
    // if (!hasKey) return const RouteSettings(name: NeomageRouteConstants.onboarding);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Placeholder screens for routes that have not been fully implemented yet.
// ---------------------------------------------------------------------------

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          '$title — coming soon',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    );
  }
}

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not Found')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('404', style: Theme.of(context).textTheme.displayLarge),
            const SizedBox(height: 16),
            Text(
              'The page you are looking for does not exist.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Sint.offAllNamed(NeomageRouteConstants.chat),
              child: const Text('Go to Chat'),
            ),
          ],
        ),
      ),
    );
  }
}
