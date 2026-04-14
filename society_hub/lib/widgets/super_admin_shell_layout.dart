import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SuperAdminShellLayout extends StatelessWidget {
  final Widget child;
  const SuperAdminShellLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            )
          ],
        ),
        child: NavigationBar(
          selectedIndex: _calculateSelectedIndex(context),
          onDestinationSelected: (index) => _onItemTapped(index, context),
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 0,
          indicatorColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.2),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded, color: Color(0xFF4F46E5)),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.business_outlined),
              selectedIcon: Icon(Icons.business_rounded, color: Color(0xFF4F46E5)),
              label: 'Societies',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded, color: Color(0xFF4F46E5)),
              label: 'Invoices',
            ),
            NavigationDestination(
              icon: Icon(Icons.analytics_outlined),
              selectedIcon: Icon(Icons.analytics_rounded, color: Color(0xFF4F46E5)),
              label: 'Reports',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded, color: Color(0xFF4F46E5)),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  static int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/super_admin/dashboard')) return 0;
    if (location.startsWith('/super_admin/societies')) return 1;
    if (location.startsWith('/super_admin/invoices')) return 2;
    if (location.startsWith('/super_admin/reports')) return 3;
    if (location.startsWith('/super_admin/settings')) return 4;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/super_admin/dashboard');
        break;
      case 1:
        context.go('/super_admin/societies');
        break;
      case 2:
        context.go('/super_admin/invoices');
        break;
      case 3:
        context.go('/super_admin/reports');
        break;
      case 4:
        context.go('/super_admin/settings');
        break;
    }
  }
}
