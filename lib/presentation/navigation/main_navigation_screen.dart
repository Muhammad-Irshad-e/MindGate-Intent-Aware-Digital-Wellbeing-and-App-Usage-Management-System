import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/intervention_state_model.dart';
import '../../services/usage_monitoring_service.dart';
import '../../services/overlay_service.dart';
import '../screens/app_categories_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/permission_setup_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/statistics_screen.dart';
import '../screens/usage_limits_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  final UsageMonitoringService? monitoringService;
  final OverlayService? overlayService;

  const MainNavigationScreen({
    super.key,
    this.monitoringService,
    this.overlayService,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  late final UsageMonitoringService _monitoringService;
  late final OverlayService _overlayService;
  StreamSubscription<InterventionState>? _limitSubscription;
  bool _isInterventionShowing = false;

  @override
  void initState() {
    super.initState();
    _monitoringService = widget.monitoringService ?? UsageMonitoringService();
    _overlayService = widget.overlayService ??
        OverlayService(
          onTakeBreak: () {
            _monitoringService.interventionService.takeABreak();
            _isInterventionShowing = false;
          },
          onSnooze: () async {
            await _monitoringService.interventionService.snooze();
            _isInterventionShowing = false;
          },
        );
    // Initialize & open real-time monitoring session pipeline
    _monitoringService.sessionStream;
    _listenToLimitReachedStream();
  }

  void _listenToLimitReachedStream() {
    _limitSubscription =
        _monitoringService.limitReachedStream.listen((state) async {
      final now = DateTime.now();
      final status = state.getStatusAt(now);

      if (status == InterventionStatus.gracePeriod ||
          status == InterventionStatus.interventionRequired) {
        _isInterventionShowing = true;

        final categoryInfo =
            await _monitoringService.resolveAppCategory(state.packageName);

        final settings = await _monitoringService
            .interventionService.dbHelper
            .getUserSettings();

        final categoryDisplay = categoryInfo.category.name.isNotEmpty
            ? categoryInfo.category.name[0].toUpperCase() +
                categoryInfo.category.name.substring(1)
            : '';

        final remainingSeconds = state.remainingGraceSeconds(now);

        await _overlayService.showOverlay(
          packageName: state.packageName,
          appName: categoryInfo.appName,
          categoryName: categoryDisplay,
          usedMinutes: state.usedMinutes,
          remainingSeconds: remainingSeconds,
          snoozeEnabled: settings.snoozeEnabled,
          snoozeDuration: settings.snoozeDuration,
        );
      } else {
        if (_isInterventionShowing) {
          await _overlayService.hideOverlay();
          _isInterventionShowing = false;
        }
      }
    });
  }

  @override
  void dispose() {
    _limitSubscription?.cancel();
    _limitSubscription = null;
    if (widget.monitoringService == null) {
      _monitoringService.dispose();
    }
    super.dispose();
  }

  void _onTabSelected(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      DashboardScreen(
        onNavigateToSettings: () => _onTabSelected(4),
        onNavigateToCategories: () => _onTabSelected(3),
      ),
      StatisticsScreen(onBackToHome: () => _onTabSelected(0)),
      UsageLimitsScreen(
        onSave: () => _onTabSelected(0),
        onBackToHome: () => _onTabSelected(0),
      ),
      AppCategoriesScreen(onBackToHome: () => _onTabSelected(0)),
      SettingsScreen(
        onNavigateToLimits: () => _onTabSelected(2),
        onNavigateToCategories: () => _onTabSelected(3),
        onNavigateToPermissions: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PermissionSetupScreen()),
          );
        },
        onBackToHome: () => _onTabSelected(0),
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabSelected,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: AppColors.primaryGreen,
          unselectedItemColor: AppColors.textMuted,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_outlined),
              activeIcon: Icon(Icons.bar_chart_rounded),
              label: 'Statistics',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.timer_outlined),
              activeIcon: Icon(Icons.timer_rounded),
              label: 'Limits',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_outlined),
              activeIcon: Icon(Icons.grid_view_rounded),
              label: 'Categories',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
