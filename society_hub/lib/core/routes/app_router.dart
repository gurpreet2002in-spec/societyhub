import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/connect_society_screen.dart';
import '../../features/dashboard/presentation/admin_dashboard.dart';
import '../../features/complaints/presentation/complaints_screen.dart';
import '../../features/payments/presentation/payments_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/visitors/presentation/visitor_screen.dart';
import '../../features/visitors/presentation/create_pass_screen.dart';
import '../../features/billing/presentation/admin_billing_screen.dart';
import '../../features/daily_help/presentation/daily_help_screen.dart';
import '../../features/amenities/presentation/amenities_screen.dart';
import '../../features/community/presentation/community_screen.dart';
import '../../features/parking/presentation/parking_screen.dart';
import '../../features/marketplace/presentation/marketplace_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/admin/presentation/admin_users_screen.dart';
import '../../features/admin/presentation/society_settings_screen.dart';
import '../../features/admin/presentation/super_admin_dashboard.dart';
import '../../features/admin/presentation/super_admin_societies_screen.dart';
import '../../features/admin/presentation/super_admin_manage_admins_screen.dart';
import '../../features/admin/presentation/super_admin_settings_screen.dart';
import '../../features/admin/presentation/super_admin_invoices_screen.dart';
import '../../features/admin/presentation/super_admin_reports_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../widgets/shell_layout.dart';
import '../../widgets/super_admin_shell_layout.dart';
import '../providers/auth_provider.dart';
import '../../services/api_service.dart';

// With Supabase, the server is always "configured" — no QR scan needed.
final serverConfiguredProvider = FutureProvider<bool>((ref) async => true);

final appRouterProvider = Provider<GoRouter>((ref) {
  final isAuth = ref.watch(authProvider);

  return GoRouter(
    initialLocation: isAuth
        ? (ref.read(apiServiceProvider).user?['role'] == 'super_admin'
            ? '/super_admin/dashboard'
            : '/dashboard')
        : '/login',
    redirect: (context, state) {
      final location = state.matchedLocation;
      final isLogin = location == '/login';
      final isConnect = location == '/connect';

      // Redirect away from the legacy /connect screen
      if (isConnect) return isAuth ? '/dashboard' : '/login';

      if (!isAuth && !isLogin) return '/login';
      if (isAuth && isLogin) {
        final role = ref.read(apiServiceProvider).user?['role'];
        return role == 'super_admin' ? '/super_admin/dashboard' : '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/connect',           builder: (_, __) => const ConnectSocietyScreen()),
      GoRoute(path: '/login',            builder: (_, __) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => SuperAdminShellLayout(child: child),
        routes: [
          GoRoute(path: '/super_admin/dashboard', builder: (_, __) => const SuperAdminDashboard()),
          GoRoute(path: '/super_admin/societies', builder: (_, __) => const SuperAdminSocietiesScreen()),
          GoRoute(path: '/super_admin/settings',  builder: (_, __) => const SuperAdminSettingsScreen()),
          GoRoute(path: '/super_admin/invoices',  builder: (_, __) => const SuperAdminInvoicesScreen()),
          GoRoute(path: '/super_admin/reports',   builder: (_, __) => const SuperAdminReportsScreen()),
        ],
      ),
      GoRoute(
        path: '/super_admin/societies/:id/admins',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final extras = state.extra as Map<String, dynamic>? ?? {};
          return SuperAdminManageAdminsScreen(societyId: id, societyName: extras['name'] ?? 'Society');
        },
      ),
      ShellRoute(
        builder: (context, state, child) => ShellLayout(child: child),
        routes: [
          GoRoute(path: '/dashboard',  builder: (_, __) => const AdminDashboard()),
          GoRoute(path: '/payments',   builder: (_, __) => const PaymentsScreen()),
          GoRoute(path: '/community',  builder: (_, __) => const CommunityScreen()),
          GoRoute(path: '/complaints', builder: (_, __) => const ComplaintsScreen()),
          GoRoute(path: '/profile',    builder: (_, __) => const ProfileScreen()),
          GoRoute(path: '/profile/edit',     builder: (_, __) => const EditProfileScreen()),
          GoRoute(path: '/notifications',     builder: (_, __) => const NotificationsScreen()),
          GoRoute(path: '/visitors',         builder: (_, __) => const VisitorScreen()),
          GoRoute(path: '/visitors/create',  builder: (_, __) => const CreatePassScreen()),
          GoRoute(path: '/admin/billing',    builder: (_, __) => const AdminBillingScreen()),
          GoRoute(path: '/admin/users',      builder: (_, __) => const AdminUsersScreen()),
          GoRoute(path: '/admin/society',    builder: (_, __) => const SocietySettingsScreen()),
          GoRoute(path: '/daily-help',       builder: (_, __) => const DailyHelpScreen()),
          GoRoute(path: '/amenities',        builder: (_, __) => const AmenitiesScreen()),
          GoRoute(path: '/parking',          builder: (_, __) => const ParkingScreen()),
          GoRoute(path: '/marketplace',      builder: (_, __) => const MarketplaceScreen()),
          GoRoute(path: '/reports',          builder: (_, __) => const ReportsScreen()),
        ],
      ),
    ],
  );
});
