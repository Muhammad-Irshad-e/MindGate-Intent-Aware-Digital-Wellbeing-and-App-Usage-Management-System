import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/user_settings_model.dart';

class UsageLimitsScreen extends StatefulWidget {
  final VoidCallback? onSave;
  final VoidCallback? onBackToHome;
  final DatabaseHelper? databaseHelper;

  const UsageLimitsScreen({
    super.key,
    this.onSave,
    this.onBackToHome,
    this.databaseHelper,
  });

  @override
  State<UsageLimitsScreen> createState() => _UsageLimitsScreenState();
}

class _UsageLimitsScreenState extends State<UsageLimitsScreen> {
  double _negativeLimitMinutes = 30;
  double _neutralLimitMinutes = 120;
  bool _enableLimits = true;
  int _gracePeriodMinutes = 5;
  bool _snoozeEnabled = true;
  int _snoozeDurationMinutes = 5;
  bool _isLoading = true;

  DatabaseHelper get _db => widget.databaseHelper ?? DatabaseHelper();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _db.getUserSettings();
      if (mounted) {
        setState(() {
          _negativeLimitMinutes = settings.negativeAppLimit.toDouble();
          _neutralLimitMinutes = settings.neutralAppLimit.toDouble();
          _enableLimits = settings.usageLimitsEnabled;
          _gracePeriodMinutes = settings.gracePeriod;
          _snoozeEnabled = settings.snoozeEnabled;
          _snoozeDurationMinutes = settings.snoozeDuration;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    final settings = UserSettings(
      settingId: 1,
      negativeAppLimit: _negativeLimitMinutes.round(),
      neutralAppLimit: _neutralLimitMinutes.round(),
      productiveAppLimit: -1,
      gracePeriod: _gracePeriodMinutes,
      snoozeEnabled: _snoozeEnabled,
      snoozeDuration: _snoozeDurationMinutes,
      usageLimitsEnabled: _enableLimits,
    );

    await _db.saveUserSettings(settings);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usage limits saved successfully!'),
          backgroundColor: AppColors.primaryGreen,
        ),
      );
      if (widget.onSave != null) widget.onSave!();
    }
  }

  Future<void> _showGracePeriodDialog() async {
    final options = [1, 2, 3, 5, 10, 15];
    final selected = await showDialog<int>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Grace Period'),
          children: options.map((mins) {
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(context, mins),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '$mins minute${mins == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontWeight: mins == _gracePeriodMinutes ? FontWeight.bold : FontWeight.normal,
                    color: mins == _gracePeriodMinutes ? AppColors.primaryGreen : AppColors.textPrimary,
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
    if (selected != null && mounted) {
      setState(() {
        _gracePeriodMinutes = selected;
      });
    }
  }

  Future<void> _showSnoozeOptionsDialog() async {
    bool tempEnabled = _snoozeEnabled;
    int tempDuration = _snoozeDurationMinutes;
    final options = [1, 2, 3, 5, 10, 15];

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Snooze Settings'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('Enable Snooze'),
                    value: tempEnabled,
                    activeTrackColor: AppColors.primaryGreen,
                    onChanged: (val) {
                      setDialogState(() {
                        tempEnabled = val;
                      });
                    },
                  ),
                  if (tempEnabled) ...[
                    const Divider(),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Snooze Duration',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: options.map((mins) {
                        final isSelected = mins == tempDuration;
                        return ChoiceChip(
                          label: Text('$mins min'),
                          selected: isSelected,
                          selectedColor: AppColors.primaryGreenLight,
                          labelStyle: TextStyle(
                            color: isSelected ? AppColors.primaryGreenDark : AppColors.textPrimary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setDialogState(() {
                                tempDuration = mins;
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _snoozeEnabled = tempEnabled;
                      _snoozeDurationMinutes = tempDuration;
                    });
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                  ),
                  child: const Text('Confirm', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryGreen),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Usage Limits'),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else if (widget.onBackToHome != null) {
              widget.onBackToHome!();
            }
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            // Negative Apps Limit Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.negativeLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.layers_clear_rounded,
                            color: AppColors.negative,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Negative Apps',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                'Daily limit',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${_negativeLimitMinutes.toInt()} min',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.negative,
                        inactiveTrackColor: AppColors.negativeLight,
                        thumbColor: AppColors.negative,
                        trackHeight: 6,
                      ),
                      child: Slider(
                        value: _negativeLimitMinutes,
                        min: 0,
                        max: 240,
                        onChanged: (val) => setState(() => _negativeLimitMinutes = val),
                      ),
                    ),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('0 min', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        Text('4 hours', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Neutral Apps Limit Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.neutralLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.tune_rounded,
                            color: AppColors.neutral,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Neutral Apps',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                'Daily limit',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _formatLimitHours(_neutralLimitMinutes.toInt()),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.neutral,
                        inactiveTrackColor: AppColors.neutralLight,
                        thumbColor: AppColors.neutral,
                        trackHeight: 6,
                      ),
                      child: Slider(
                        value: _neutralLimitMinutes,
                        min: 0,
                        max: 480,
                        onChanged: (val) => setState(() => _neutralLimitMinutes = val),
                      ),
                    ),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('0 min', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        Text('8 hours', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Productive Apps Card (No Limit)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.productiveLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            color: AppColors.productive,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Productive Apps',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const Text(
                          'No limit',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.border,
                        inactiveTrackColor: AppColors.inputBackground,
                        thumbColor: AppColors.border,
                        trackHeight: 6,
                      ),
                      child: const Slider(
                        value: 100,
                        min: 0,
                        max: 100,
                        onChanged: null, // Unrestricted
                      ),
                    ),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Text('Unrestricted', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Enable Usage Limits Card
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.productiveLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        color: AppColors.productive,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Enable Usage Limits',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Monitor and apply limits to app usage',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _enableLimits,
                      activeThumbColor: Colors.white,
                      activeTrackColor: AppColors.primaryGreen,
                      onChanged: (val) => setState(() => _enableLimits = val),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Grace Period Option
            Card(
              child: ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.inputBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.timer_outlined, color: AppColors.textPrimary, size: 20),
                ),
                title: const Text(
                  'Grace Period',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$_gracePeriodMinutes minute${_gracePeriodMinutes == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                  ],
                ),
                onTap: _showGracePeriodDialog,
              ),
            ),

            const SizedBox(height: 8),

            // Snooze Option
            Card(
              child: ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.inputBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bedtime_outlined, color: AppColors.textPrimary, size: 20),
                ),
                title: const Text(
                  'Snooze Option',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _snoozeEnabled
                          ? '$_snoozeDurationMinutes minute${_snoozeDurationMinutes == 1 ? '' : 's'}'
                          : 'Disabled',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                  ],
                ),
                onTap: _showSnoozeOptionsDialog,
              ),
            ),

            const SizedBox(height: 24),

            // Save Changes Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Save Changes',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  String _formatLimitHours(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remainingMins = minutes % 60;
    if (remainingMins == 0) return '$hours hours';
    return '$hours hrs $remainingMins min';
  }
}

