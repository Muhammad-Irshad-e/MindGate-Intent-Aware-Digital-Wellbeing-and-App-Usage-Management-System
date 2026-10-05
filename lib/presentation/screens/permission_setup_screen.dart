import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../services/permission_service.dart';

class PermissionSetupScreen extends StatefulWidget {
  const PermissionSetupScreen({super.key});

  @override
  State<PermissionSetupScreen> createState() => _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends State<PermissionSetupScreen> with WidgetsBindingObserver {
  final PermissionService _permissionService = PermissionService();

  bool _usageAccessGranted = false;
  bool _accessibilityGranted = false;
  bool _notificationsGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAllPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAllPermissions();
    }
  }

  Future<void> _checkAllPermissions() async {
    final bool usage = await _permissionService.checkUsageAccess();
    final bool accessibility = await _permissionService.checkAccessibilityService();
    final bool notifications = await _permissionService.checkNotificationPermission();

    if (mounted) {
      setState(() {
        _usageAccessGranted = usage;
        _accessibilityGranted = accessibility;
        _notificationsGranted = notifications;
      });
    }
  }

  Future<void> _grantUsageAccess() async {
    await _permissionService.openUsageAccessSettings();
  }

  Future<void> _grantAccessibility() async {
    await _permissionService.openAccessibilitySettings();
  }

  Future<void> _grantNotifications() async {
    await _permissionService.requestNotificationPermission();
    // Re-check after prompt
    await _checkAllPermissions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Permissions'),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Permission 1: Usage Access
            _buildPermissionCard(
              title: 'Usage Access',
              subtitle: 'Required to track app usage',
              icon: Icons.bar_chart_rounded,
              isGranted: _usageAccessGranted,
              onGrant: _grantUsageAccess,
            ),

            const SizedBox(height: 12),

            // Permission 2: Accessibility Service
            _buildPermissionCard(
              title: 'Accessibility Service',
              subtitle: 'Required to detect active app',
              icon: Icons.accessibility_new_rounded,
              isGranted: _accessibilityGranted,
              onGrant: _grantAccessibility,
            ),

            const SizedBox(height: 12),

            // Permission 3: Notifications
            _buildPermissionCard(
              title: 'Notifications',
              subtitle: 'Required to send reminders and alerts',
              icon: Icons.notifications_none_rounded,
              isGranted: _notificationsGranted,
              onGrant: _grantNotifications,
            ),

            const Spacer(),

            // Privacy & Functionality Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.productiveLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFC6F6D5)),
              ),
              child: const Text(
                'These permissions are required for MindGate to function properly. Your data stays on your device.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.productiveText,
                  height: 1.4,
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isGranted,
    required VoidCallback onGrant,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.productiveLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: AppColors.productive,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 36,
              child: ElevatedButton(
                onPressed: isGranted ? null : onGrant,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isGranted ? Colors.grey.shade300 : AppColors.grantButton,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Text(
                  isGranted ? 'Granted' : 'Grant',
                  style: TextStyle(
                    color: isGranted ? Colors.grey.shade600 : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
