import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/dashboard_provider.dart';
import '../../../services/api_service.dart';
import '../../notifications/providers/notifications_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/premium_glass_app_bar.dart';

class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncStats = ref.watch(dashboardStatsProvider);
    final user = ref.watch(apiServiceProvider).user;
    final userName = user?['name'] ?? 'Admin';
    final userRole = user?['role'] ?? '';

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PremiumGlassAppBar(showBranding: true),
      backgroundColor: AppTheme.surface,
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(dashboardStatsProvider),
        color: AppTheme.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 32),

                    // \u2500\u2500\u2500 Welcome Section \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userRole == 'admin' ? 'MANAGEMENT PORTAL' : 'WELCOME BACK',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2.0,
                                  color: AppTheme.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Society Overview',
                                style: GoogleFonts.manrope(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.onSurface,
                                  letterSpacing: -1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (userRole == 'admin') ...[
                          const SizedBox(width: 12),
                          _PillButton(
                            label: 'Broadcast',
                            icon: Icons.campaign_outlined,
                            onTap: () => context.push('/community'),
                            isPrimary: false,
                          ),
                          const SizedBox(width: 8),
                          _PillButton(
                            label: 'Add Notice',
                            icon: Icons.add,
                            onTap: () => context.push('/community'),
                            isPrimary: true,
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 32),

                    // \u2500\u2500\u2500 Stats Bento Grid \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
                    asyncStats.when(
                      data: (stats) => _buildStatsBentoGrid(context, stats),
                      loading: () => _buildStatsLoadingSkeleton(),
                      error: (_, __) => _buildStatsBentoGrid(context, {
                        'openComplaints': 0,
                        'visitorsToday': 0,
                        'pendingInvoices': 0,
                        'collectionPct': 0,
                        'totalCollection': '0',
                        'expected': '0',
                        'criticalComplaints': 0,
                        'pendingComplaints': 0,
                      }),
                    ),

                    const SizedBox(height: 40),

                    // \u2500\u2500\u2500 Main 2-column grid \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
                    asyncStats.when(
                      data: (stats) => _buildMainGrid(context, stats, user),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),

                    const SizedBox(height: 40),

                    // \u2500\u2500\u2500 Administrative Controls \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
                    _buildAdminControls(context, userRole),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // \u2500\u2500\u2500 Stats Bento Grid \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
  Widget _buildStatsBentoGrid(BuildContext context, Map<String, dynamic> stats) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _StatCard(
              label: 'Collection Status',
              value: '${stats['collectionPct'] ?? 85}%',
              badge: '+2.4%',
              badgeColor: AppTheme.secondary,
              badgeBg: const Color(0xFFD4F5DF),
              badgeIcon: Icons.trending_up,
              footer: 'Collected: \u20B9${stats['totalCollection'] ?? '4.2L'} / \u20B9${stats['expected'] ?? '5L'} Expected',
              progressValue: (stats['collectionPct'] ?? 85) / 100.0,
            )),
            const SizedBox(width: 16),
            Expanded(child: _StatCard(
              label: 'Open Complaints',
              value: '${stats['openComplaints'] ?? 0}',
              valueColor: AppTheme.error,
              chips: [
                _Chip(label: '${stats['criticalComplaints'] ?? 0} Critical', isError: true),
                _Chip(label: '${stats['pendingComplaints'] ?? 0} Pending', isError: false),
              ],
            )),
          ],
        ),
        const SizedBox(height: 16),
        _StatCard(
          label: 'Visitors Today',
          value: '${stats['visitorsToday'] ?? 0}',
          actionLabel: 'Review',
          onActionTap: () {},
          isWide: true,
        ),
      ],
    );
  }

  Widget _buildStatsLoadingSkeleton() {
    return Column(
      children: [
        Row(children: [
          Expanded(child: _SkeletonBox(height: 160, radius: 16)),
          const SizedBox(width: 16),
          Expanded(child: _SkeletonBox(height: 160, radius: 16)),
        ]),
        const SizedBox(height: 16),
        _SkeletonBox(height: 100, radius: 16),
      ],
    );
  }

  Widget _buildStatsError() {
    return Center(
      child: Text('Failed to load stats',
        style: GoogleFonts.inter(color: AppTheme.error)),
    );
  }

  // \u2500\u2500\u2500 Main Grid \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
  Widget _buildMainGrid(BuildContext context, Map<String, dynamic> stats, Map? user) {
    return Column(
      children: [
        // Complaints row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Recent Complaints
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Recent Complaints', style: GoogleFonts.manrope(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.onSurface,
                          letterSpacing: -0.5,
                        )),
                      ),
                      _TextButton(label: 'View All', onTap: () => context.go('/complaints')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        _ComplaintRow(
                          icon: Icons.water_drop_outlined,
                          iconBg: AppTheme.primaryFixed,
                          iconColor: AppTheme.primary,
                          title: 'Water Leakage',
                          sub: 'Rahul Sharma \u2022 B-402',
                          badge: 'Critical',
                          badgeIsError: true,
                        ),
                        const SizedBox(height: 8),
                        _ComplaintRow(
                          icon: Icons.electrical_services_outlined,
                          iconBg: AppTheme.surfaceContainerHighest,
                          iconColor: AppTheme.onSurfaceVariant,
                          title: 'Lift Not Working',
                          sub: 'Anita Desai \u2022 Wing C',
                          badge: 'Investigating',
                          badgeIsError: false,
                        ),
                        const SizedBox(height: 8),
                        _ComplaintRow(
                          icon: Icons.park_outlined,
                          iconBg: AppTheme.surfaceContainerHighest,
                          iconColor: AppTheme.onSurfaceVariant,
                          title: 'Garden Maintenance',
                          sub: 'Vikram Goel \u2022 A-105',
                          badge: 'Scheduled',
                          badgeIsGreen: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 32),

        // Society Notices
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('Society Notices', style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTheme.onSurface,
                letterSpacing: -0.5,
              ))),
              _TextButton(label: 'Manage', onTap: () => context.push('/community')),
            ]),
            const SizedBox(height: 16),
            _NoticeCard(
              title: 'Annual General Meeting 2024',
              time: '2 hours ago',
              body: 'Mandatory attendance for all flat owners. Discussing upcoming parking renovations and maintenance fee revision.',
              meta: 'Oct 24, 2023 \u2022 10:30 AM',
              accentColor: AppTheme.primary,
            ),
            const SizedBox(height: 12),
            _NoticeCard(
              title: 'Society Cultural Festival',
              time: '1 day ago',
              body: 'Join us for the Diwali celebration. Performance slots are open for children. Contact the office to register.',
              meta: 'Nov 12, 2023',
              accentColor: AppTheme.secondary,
            ),
          ],
        ),
      ],
    );
  }

  // \u2500\u2500\u2500 Admin Controls \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
  Widget _buildAdminControls(BuildContext context, String userRole) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Text(
            'ADMINISTRATIVE CONTROLS',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.0,
              color: AppTheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: [
              _ControlButton(icon: Icons.verified_user_outlined, label: 'Visitors', onTap: () => context.push('/visitors')),
              _ControlButton(icon: Icons.account_balance_wallet_outlined, label: 'Finance', onTap: () => context.go('/payments')),
              _ControlButton(icon: Icons.storefront_outlined, label: 'Market', onTap: () => context.push('/marketplace')),
              _ControlButton(icon: Icons.local_parking_rounded, label: 'Parking', onTap: () => context.push('/parking')),
              _ControlButton(icon: Icons.cleaning_services_outlined, label: 'Daily Help', onTap: () => context.push('/daily-help')),
              _ControlButton(icon: Icons.pool_outlined, label: 'Amenities', onTap: () => context.push('/amenities')),
              if (userRole == 'admin') ...[
                _ControlButton(icon: Icons.request_quote_outlined, label: 'Gen Bills', onTap: () => context.push('/admin/billing')),
                _ControlButton(icon: Icons.bar_chart_rounded, label: 'Reports', onTap: () => context.push('/reports')),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// \u2500\u2500\u2500 Helper Widgets \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

class _PillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;

  const _PillButton({required this.label, required this.icon, required this.onTap, required this.isPrimary});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: isPrimary
              ? const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.primaryContainer],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isPrimary ? null : AppTheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(50),
          boxShadow: isPrimary
              ? [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isPrimary ? Colors.white : AppTheme.onSurface),
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: isPrimary ? Colors.white : AppTheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final String? badge;
  final Color? badgeColor;
  final Color? badgeBg;
  final IconData? badgeIcon;
  final String? footer;
  final double? progressValue;
  final List<_Chip>? chips;
  final String? actionLabel;
  final VoidCallback? onActionTap;
  final bool isWide;

  const _StatCard({
    required this.label,
    required this.value,
    this.valueColor,
    this.badge,
    this.badgeColor,
    this.badgeBg,
    this.badgeIcon,
    this.footer,
    this.progressValue,
    this.chips,
    this.actionLabel,
    this.onActionTap,
    this.isWide = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: AppTheme.outlineVariant.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.onSurfaceVariant,
          )),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(value, style: GoogleFonts.manrope(
                fontSize: isWide ? 44 : 40,
                fontWeight: FontWeight.w800,
                color: valueColor ?? AppTheme.onSurface,
                letterSpacing: -2.0,
              )),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeBg ?? AppTheme.primaryFixed,
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (badgeIcon != null) Icon(badgeIcon, size: 12, color: badgeColor ?? AppTheme.primary),
                      if (badgeIcon != null) const SizedBox(width: 2),
                      Text(badge!, style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: badgeColor ?? AppTheme.primary,
                      )),
                    ],
                  ),
                ),
              ],
              if (actionLabel != null) ...[
                const SizedBox(width: 12),
                Container(width: 1, height: 32, color: AppTheme.outlineVariant.withValues(alpha: 0.3)),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: onActionTap,
                  child: Row(
                    children: [
                      Text(actionLabel!, style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                        letterSpacing: 1.2,
                      )),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward, size: 14, color: AppTheme.primary),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (progressValue != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(50),
              child: LinearProgressIndicator(
                value: progressValue,
                backgroundColor: AppTheme.surfaceContainerLow,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                minHeight: 6,
              ),
            ),
          ],
          if (footer != null) ...[
            const SizedBox(height: 8),
            Text(footer!, style: GoogleFonts.inter(
              fontSize: 11,
              color: AppTheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            )),
          ],
          if (chips != null) ...[
            const SizedBox(height: 12),
            Row(
              children: chips!.map((c) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.isError ? AppTheme.errorContainer : AppTheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Text(c.label, style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: c.isError ? const Color(0xFF93000A) : AppTheme.onSurfaceVariant,
                  )),
                ),
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip {
  final String label;
  final bool isError;
  const _Chip({required this.label, required this.isError});
}

class _ComplaintRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String sub;
  final String badge;
  final bool badgeIsError;
  final bool badgeIsGreen;

  const _ComplaintRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.sub,
    required this.badge,
    this.badgeIsError = false,
    this.badgeIsGreen = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.onSurface,
                )),
                const SizedBox(height: 2),
                Text(sub, style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppTheme.onSurfaceVariant,
                )),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badgeIsError
                  ? AppTheme.errorContainer
                  : badgeIsGreen
                      ? const Color(0xFFD4F5DF)
                      : AppTheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(50),
            ),
            child: Text(
              badge.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: badgeIsError
                    ? const Color(0xFF93000A)
                    : badgeIsGreen
                        ? AppTheme.secondary
                        : AppTheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final String title;
  final String time;
  final String body;
  final String meta;
  final Color accentColor;

  const _NoticeCard({
    required this.title,
    required this.time,
    required this.body,
    required this.meta,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLowest,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(12),
          bottomRight: Radius.circular(12),
          topLeft: Radius.circular(4),
          bottomLeft: Radius.circular(4),
        ),
        border: Border(left: BorderSide(color: accentColor, width: 4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(title, style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.onSurface,
                )),
              ),
              const SizedBox(width: 8),
              Text(time, style: GoogleFonts.inter(
                fontSize: 10,
                color: AppTheme.onSurfaceVariant,
              )),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: GoogleFonts.inter(
            fontSize: 12,
            color: AppTheme.onSurfaceVariant,
            height: 1.5,
          )),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.event_outlined, size: 14, color: accentColor),
              const SizedBox(width: 4),
              Text(meta, style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: accentColor,
              )),
            ],
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ControlButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppTheme.primary, size: 28),
            const SizedBox(height: 8),
            Text(
              label.toUpperCase(),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppTheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _TextButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.primaryFixed,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: AppTheme.primary,
          ),
        ),
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double height;
  final double radius;
  const _SkeletonBox({required this.height, required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _NotificationBell extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncCount = ref.watch(unreadCountProvider);
    final count = asyncCount.valueOrNull ?? 0;

    return Stack(
      alignment: Alignment.center,
      children: [
        GestureDetector(
          onTap: () {
            context.push('/notifications');
            ref.invalidate(unreadCountProvider);
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(50),
            ),
            child: Icon(Icons.notifications_outlined, color: const Color(0xFF64748B), size: 24),
          ),
        ),
        if (count > 0)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppTheme.error,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}
