import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/pending_peers_provider.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import 'app_drawer.dart';
import '../utils/global_keys.dart';

class ScaffoldWithNav extends StatelessWidget {
  final Widget child;

  const ScaffoldWithNav({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool useRail = width > 600;

    // Build navigation items (always includes loans menu)
    final navItems = _buildNavItems(context);

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      key: GlobalKeys.rootScaffoldKey,
      drawer: useRail ? null : const AppDrawer(),
      body: Semantics(
        explicitChildNodes: true,
        child: Row(
        children: [
          if (useRail)
            Semantics(
              label: TranslationService.translate(context, 'navigation'),
              child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: NavigationRail(
                        minWidth: 88,
                        backgroundColor: isDark
                            ? theme.colorScheme.surface
                            : null,
                        indicatorColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                        selectedIndex: _calculateSelectedIndex(
                          context,
                          navItems,
                        ),
                        onDestinationSelected: (int index) =>
                            _onItemTapped(index, context, navItems),
                        labelType: NavigationRailLabelType.all,
                        selectedLabelTextStyle: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                        unselectedLabelTextStyle: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                        selectedIconTheme: IconThemeData(
                          color: theme.colorScheme.primary,
                        ),
                        unselectedIconTheme: IconThemeData(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        destinations: navItems
                            .map((item) => item.destination)
                            .toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
            ),
          if (useRail) ExcludeSemantics(child: VerticalDivider(
            thickness: 1,
            width: 1,
            color: theme.dividerColor,
          )),
          Expanded(child: child),
        ],
      ),
      ),
    );
  }

  List<_NavItem> _buildNavItems(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return [
      _NavItem(
        route: '/books',
        matchPrefixes: ['/books', '/shelves', '/collections'],
        destination: NavigationRailDestination(
          icon: const Icon(Icons.book),
          label: Text(TranslationService.translate(context, 'library')),
        ),
      ),
      _NavItem(
        route: '/network',
        matchPrefixes: ['/network', '/contacts', '/peers'],
        destination: NavigationRailDestination(
          icon: Consumer<PendingPeersProvider>(
            builder: (context, provider, child) {
              final count = provider.pendingCount;
              return Badge(
                isLabelVisible: count > 0,
                label: Text('$count'),
                child: const Icon(Icons.people),
              );
            },
          ),
          label: Text(TranslationService.translate(context, 'nav_network')),
        ),
      ),
      _NavItem(
        route: '/requests',
        matchPrefixes: ['/requests'],
        destination: NavigationRailDestination(
          icon: const Icon(Icons.swap_horiz),
          label: Text(TranslationService.translate(context, 'nav_loans')),
        ),
      ),
      _NavItem(
        route: '/profile',
        destination: NavigationRailDestination(
          icon: const Icon(Icons.person),
          label: Text(TranslationService.translate(context, 'profile')),
        ),
      ),
      _NavItem(
        route: '/dashboard',
        matchPrefixes: ['/dashboard', '/statistics'],
        destination: NavigationRailDestination(
          icon: const Icon(Icons.dashboard),
          label: Text(TranslationService.translate(context, 'dashboard')),
        ),
      ),
      if (themeProvider.gamesEnabled &&
          (themeProvider.memoryGameEnabled || themeProvider.slidingPuzzleEnabled))
        _NavItem(
          route: '/games',
          matchPrefixes: ['/games', '/memory-game', '/sliding-puzzle'],
          destination: NavigationRailDestination(
            icon: const Icon(Icons.sports_esports),
            label: Text(TranslationService.translate(context, 'games_section')),
          ),
        ),
      _NavItem(
        route: '/settings',
        matchPrefixes: ['/settings', '/operation-log', '/device-pairing', '/sync-review'],
        destination: NavigationRailDestination(
          icon: const Icon(Icons.settings),
          label: Text(TranslationService.translate(context, 'nav_settings')),
        ),
      ),
      _NavItem(
        route: '/help',
        destination: NavigationRailDestination(
          icon: const Icon(Icons.help_outline),
          label: Text(TranslationService.translate(context, 'nav_help')),
        ),
      ),
    ];
  }

  static int _calculateSelectedIndex(
    BuildContext context,
    List<_NavItem> navItems,
  ) {
    final String location = GoRouterState.of(context).uri.path;
    for (int i = 0; i < navItems.length; i++) {
      final item = navItems[i];
      if (item.matchPrefixes != null) {
        for (final prefix in item.matchPrefixes!) {
          if (location.startsWith(prefix)) return i;
        }
      } else if (location.startsWith(item.route)) {
        return i;
      }
    }
    return 0;
  }

  void _onItemTapped(int index, BuildContext context, List<_NavItem> navItems) {
    if (index >= 0 && index < navItems.length) {
      final item = navItems[index];
      if (item.isPush) {
        context.push(item.route);
      } else {
        context.go(item.route);
      }
    }
  }
}

class _NavItem {
  final String route;
  final List<String>? matchPrefixes;
  final NavigationRailDestination destination;
  final bool isPush;

  _NavItem({
    required this.route,
    required this.destination,
    this.matchPrefixes,
    this.isPush = false,
  });
}
