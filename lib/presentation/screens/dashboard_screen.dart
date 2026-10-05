import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../services/analytics_service.dart';
import '../../services/usage_monitoring_service.dart';
import '../widgets/app_icon_widget.dart';
import '../widgets/category_pill.dart';
import 'todays_usage_screen.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onNavigateToSettings;
  final VoidCallback? onNavigateToCategories;

  const DashboardScreen({
    super.key,
    this.onNavigateToSettings,
    this.onNavigateToCategories,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  final UsageAnalyticsService _analyticsService = UsageAnalyticsService();
  DashboardData? _data;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDashboardData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadDashboardData();
    }
  }

  Future<void> _loadDashboardData() async {
    final loaded = await _analyticsService.getDashboardData(
      activePackageName: UsageMonitoringService.currentActivePackageName,
      currentSessionStartTime: UsageMonitoringService.currentActiveSessionStartTime,
    );
    if (mounted) {
      setState(() {
        _data = loaded;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _data == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primaryGreen),
        ),
      );
    }

    final data = _data!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        color: AppColors.primaryGreen,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // Header Section with Forest Dark Green Gradient & CPI Circular Badge
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  // Dark Forest Background Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 50, 20, 70),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.headerGradientStart,
                          AppColors.headerGradientEnd,
                        ],
                      ),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(28),
                        bottomRight: Radius.circular(28),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'MindGate',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                              ),
                            ),
                            IconButton(
                              onPressed: widget.onNavigateToSettings,
                              icon: const Icon(
                                Icons.settings_outlined,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Good morning!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Small steps today, a better you tomorrow.',
                          style: TextStyle(
                            color: Color.fromRGBO(255, 255, 255, 0.75),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),

                  // CPI Badge (Overlapping Bottom of Dark Header)
                  Positioned(
                    bottom: -45,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Color.fromRGBO(0, 0, 0, 0.08),
                            blurRadius: 16,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Circular Ring with Score inside
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 84,
                                height: 84,
                                child: CircularProgressIndicator(
                                  value: data.cpiScore / 100.0,
                                  strokeWidth: 8,
                                  backgroundColor: const Color(0xFFE2E8F0),
                                  valueColor: const AlwaysStoppedAnimation<Color>(
                                    AppColors.productive,
                                  ),
                                  strokeCap: StrokeCap.round,
                                ),
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${data.cpiScore}',
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary,
                                      height: 1.0,
                                    ),
                                  ),
                                  const Text(
                                    'CPI',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Pill badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primaryGreen,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              data.cpiStatus,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 60),

              // Today's App Usage Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Today's App Usage",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Row(
                              children: [
                                Icon(
                                  data.vsYesterdayPercentage >= 0
                                      ? Icons.arrow_upward_rounded
                                      : Icons.arrow_downward_rounded,
                                  size: 14,
                                  color: AppColors.productive,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '${data.vsYesterdayPercentage.abs()}% vs. yesterday',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.productiveText,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          data.formattedTotalTime,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Stacked Horizontal Progress Bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            height: 10,
                            child: Row(
                              children: [
                                Expanded(
                                  flex: data.productivePercentage > 0
                                      ? data.productivePercentage
                                      : (data.cpiResult.totalDurationMs == 0 ? 1 : 0),
                                  child: Container(
                                      color: data.cpiResult.totalDurationMs == 0
                                          ? const Color(0xFFE2E8F0)
                                          : AppColors.productive),
                                ),
                                if (data.cpiResult.totalDurationMs > 0) ...[
                                  const SizedBox(width: 2),
                                  Expanded(
                                    flex: data.neutralPercentage,
                                    child: Container(color: AppColors.neutral),
                                  ),
                                  const SizedBox(width: 2),
                                  Expanded(
                                    flex: data.negativePercentage,
                                    child: Container(color: AppColors.negative),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Breakdown List
                        _buildBreakdownRow(
                          color: AppColors.productive,
                          label: 'Productive',
                          percent: '${data.productivePercentage}%',
                          duration: data.formatDuration(data.productiveMinutes),
                        ),
                        const SizedBox(height: 8),
                        _buildBreakdownRow(
                          color: AppColors.neutral,
                          label: 'Neutral',
                          percent: '${data.neutralPercentage}%',
                          duration: data.formatDuration(data.neutralMinutes),
                        ),
                        const SizedBox(height: 8),
                        _buildBreakdownRow(
                          color: AppColors.negative,
                          label: 'Negative',
                          percent: '${data.negativePercentage}%',
                          duration: data.formatDuration(data.negativeMinutes),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Top Apps Today Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Top Apps Today',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const TodaysUsageScreen()),
                                );
                              },
                              child: const Row(
                                children: [
                                  Text(
                                    'View All',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  SizedBox(width: 2),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 16,
                                    color: AppColors.textSecondary,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (data.topApps.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: Text(
                                'No app activity recorded today',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          )
                        else
                          ...data.topApps.map((app) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  children: [
                                    AppIconWidget(iconKey: app.iconKey, size: 36),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        app.appName,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      app.formattedDuration,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    CategoryPill(category: app.category),
                                  ],
                                ),
                              )),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBreakdownRow({
    required Color color,
    required String label,
    required String percent,
    required String duration,
  }) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        const Spacer(),
        Text(
          percent,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 24),
        SizedBox(
          width: 50,
          child: Text(
            duration,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
