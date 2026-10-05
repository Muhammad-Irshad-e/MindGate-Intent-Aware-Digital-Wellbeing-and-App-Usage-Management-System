import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class SettingsScreen extends StatelessWidget {
  final VoidCallback? onNavigateToLimits;
  final VoidCallback? onNavigateToCategories;
  final VoidCallback? onNavigateToPermissions;
  final VoidCallback? onBackToHome;

  const SettingsScreen({
    super.key,
    this.onNavigateToLimits,
    this.onNavigateToCategories,
    this.onNavigateToPermissions,
    this.onBackToHome,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else if (onBackToHome != null) {
              onBackToHome!();
            }
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            // 1. Notifications
            _buildSettingCard(
              title: 'Notifications',
              subtitle: 'Manage reminders and alerts',
              icon: Icons.notifications_none_rounded,
              iconBgColor: const Color(0xFF3B82F6),
              onTap: onNavigateToPermissions,
            ),
            const SizedBox(height: 10),

            // 2. Appearance
            _buildSettingCard(
              title: 'Appearance',
              subtitle: 'Theme and display preferences',
              icon: Icons.palette_outlined,
              iconBgColor: const Color(0xFFEC4899),
              onTap: () {},
            ),
            const SizedBox(height: 10),

            // 3. Data & Privacy
            _buildSettingCard(
              title: 'Data & Privacy',
              subtitle: 'Your data stays on your device',
              icon: Icons.shield_outlined,
              iconBgColor: const Color(0xFF0EA5E9),
              onTap: () {},
            ),
            const SizedBox(height: 10),

            // 4. About
            _buildSettingCard(
              title: 'About',
              subtitle: 'App version and Information',
              icon: Icons.info_outline_rounded,
              iconBgColor: const Color(0xFF64748B),
              onTap: () {},
            ),

            const SizedBox(height: 24),

            // Bottom MindGate Branding Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.productiveLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFDCFCE7)),
              ),
              child: const Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.eco_rounded,
                        color: AppColors.primaryGreen,
                        size: 20,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Use Smarter. Live Better.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryGreenDark,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    'MindGate v1.0',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.productiveText,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconBgColor,
    VoidCallback? onTap,
  }) {
    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: iconBgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.textMuted,
          size: 20,
        ),
      ),
    );
  }
}
