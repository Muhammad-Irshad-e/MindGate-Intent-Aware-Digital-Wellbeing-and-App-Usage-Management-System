import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class InterventionScreen extends StatefulWidget {
  final String appName;
  final String? categoryName;
  final int usedMinutes;
  final int remainingSeconds;
  final bool snoozeEnabled;
  final int snoozeDuration;
  final VoidCallback? onTakeBreak;
  final VoidCallback? onSnooze;

  const InterventionScreen({
    super.key,
    this.appName = 'YouTube',
    this.categoryName,
    this.usedMinutes = 30,
    this.remainingSeconds = 299,
    this.snoozeEnabled = true,
    this.snoozeDuration = 5,
    this.onTakeBreak,
    this.onSnooze,
  });

  @override
  State<InterventionScreen> createState() => _InterventionScreenState();
}

class _InterventionScreenState extends State<InterventionScreen> {
  late int _remainingSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.remainingSeconds;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatTimer(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins : $secs';
  }

  @override
  Widget build(BuildContext context) {
    final appCategoryText =
        widget.categoryName != null && widget.categoryName!.isNotEmpty
            ? ' (${widget.categoryName})'
            : '';

    return Scaffold(
      backgroundColor: const Color(0xFFFFF0F0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Warning Icon in Badge
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: AppColors.negative,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Title
              const Text(
                'Usage Limit Reached',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),

              const SizedBox(height: 12),

              // Explanation
              Text(
                "You've used ${widget.appName}$appCategoryText for ${widget.usedMinutes} minutes today.\nTake a break and focus on what matters!",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 36),

              // Countdown / Grace Period Display Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFFCDD2)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(244, 67, 54, 0.04),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      _formatTimer(_remainingSeconds),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '(Grace Period)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Action Buttons
              Row(
                children: [
                  // Take a Break (Solid Red)
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          if (widget.onTakeBreak != null) {
                            widget.onTakeBreak!();
                          } else {
                            Navigator.maybePop(context);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.negative,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Take a Break',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),

                  if (widget.snoozeEnabled) ...[
                    const SizedBox(width: 12),

                    // Snooze Button (Outlined Red)
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () {
                            if (widget.onSnooze != null) {
                              widget.onSnooze!();
                            } else {
                              Navigator.maybePop(context);
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                                color: AppColors.negative, width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            'Snooze (${widget.snoozeDuration} minutes)',
                            style: const TextStyle(
                              color: AppColors.negative,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
