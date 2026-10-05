import 'app_category_model.dart';

/// Represents the status of the intervention state.
enum InterventionStatus {
  none,
  gracePeriod,
  snoozed,
  interventionRequired,
}

/// In-memory model representing the active intervention, grace period, and snooze state
/// for a restricted application category.
class InterventionState {
  final String packageName;
  final AppCategoryType category;
  final DateTime graceStartTime;
  final DateTime graceEndTime;
  final int usedMinutes;
  final bool isSnoozed;
  final DateTime? snoozeStartTime;
  final DateTime? snoozeEndTime;

  const InterventionState({
    required this.packageName,
    required this.category,
    required this.graceStartTime,
    required this.graceEndTime,
    this.usedMinutes = 0,
    this.isSnoozed = false,
    this.snoozeStartTime,
    this.snoozeEndTime,
  });

  /// Evaluates current status at reference time [now].
  InterventionStatus getStatusAt(DateTime now) {
    if (isSnoozed) {
      if (snoozeEndTime != null && now.isBefore(snoozeEndTime!)) {
        return InterventionStatus.snoozed;
      }
      return InterventionStatus.interventionRequired;
    }

    if (now.isBefore(graceEndTime)) {
      return InterventionStatus.gracePeriod;
    }

    return InterventionStatus.interventionRequired;
  }

  /// Calculates remaining grace duration in seconds relative to [now].
  int remainingGraceSeconds(DateTime now) {
    final diff = graceEndTime.difference(now).inSeconds;
    return diff > 0 ? diff : 0;
  }

  /// Calculates remaining snooze duration in seconds relative to [now].
  int remainingSnoozeSeconds(DateTime now) {
    if (!isSnoozed || snoozeEndTime == null) return 0;
    final diff = snoozeEndTime!.difference(now).inSeconds;
    return diff > 0 ? diff : 0;
  }

  InterventionState copyWith({
    String? packageName,
    AppCategoryType? category,
    DateTime? graceStartTime,
    DateTime? graceEndTime,
    int? usedMinutes,
    bool? isSnoozed,
    DateTime? snoozeStartTime,
    DateTime? snoozeEndTime,
  }) {
    return InterventionState(
      packageName: packageName ?? this.packageName,
      category: category ?? this.category,
      graceStartTime: graceStartTime ?? this.graceStartTime,
      graceEndTime: graceEndTime ?? this.graceEndTime,
      usedMinutes: usedMinutes ?? this.usedMinutes,
      isSnoozed: isSnoozed ?? this.isSnoozed,
      snoozeStartTime: snoozeStartTime ?? this.snoozeStartTime,
      snoozeEndTime: snoozeEndTime ?? this.snoozeEndTime,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InterventionState &&
          runtimeType == other.runtimeType &&
          packageName == other.packageName &&
          category == other.category &&
          graceStartTime == other.graceStartTime &&
          graceEndTime == other.graceEndTime &&
          usedMinutes == other.usedMinutes &&
          isSnoozed == other.isSnoozed &&
          snoozeStartTime == other.snoozeStartTime &&
          snoozeEndTime == other.snoozeEndTime;

  @override
  int get hashCode =>
      packageName.hashCode ^
      category.hashCode ^
      graceStartTime.hashCode ^
      graceEndTime.hashCode ^
      usedMinutes.hashCode ^
      isSnoozed.hashCode ^
      snoozeStartTime.hashCode ^
      snoozeEndTime.hashCode;

  @override
  String toString() =>
      'InterventionState('
      'package: $packageName, '
      'category: ${category.name}, '
      'graceStart: $graceStartTime, '
      'graceEnd: $graceEndTime, '
      'usedMins: $usedMinutes, '
      'isSnoozed: $isSnoozed, '
      'snoozeEnd: $snoozeEndTime'
      ')';
}
