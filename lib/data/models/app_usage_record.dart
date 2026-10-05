/// Represents a single completed foreground application usage session,
/// as detected by the [MindGateAccessibilityService] on the Android side.
///
/// All timestamps are epoch milliseconds, matching [System.currentTimeMillis()]
/// on the Kotlin side.
class AppUsageRecord {
  /// The Android package name of the application (e.g. "com.google.android.youtube").
  final String packageName;

  /// Epoch milliseconds when this package became the foreground application.
  final int startTime;

  /// Epoch milliseconds when this package left the foreground.
  final int endTime;

  /// Session duration in milliseconds (endTime - startTime).
  final int duration;

  const AppUsageRecord({
    required this.packageName,
    required this.startTime,
    required this.endTime,
    required this.duration,
  });

  /// Creates an [AppUsageRecord] from the platform map received via EventChannel.
  ///
  /// Uses safe conversions so a malformed or partial map does not crash the app.
  factory AppUsageRecord.fromMap(Map<dynamic, dynamic> map) {
    return AppUsageRecord(
      packageName: map['packageName'] as String? ?? '',
      startTime: _toInt(map['startTime']),
      endTime: _toInt(map['endTime']),
      duration: _toInt(map['duration']),
    );
  }

  /// Converts this record into a SQLite row map.
  Map<String, dynamic> toDbMap() {
    return {
      'packageName': packageName,
      'startTime': startTime,
      'endTime': endTime,
      'duration': duration,
    };
  }

  /// Constructs an [AppUsageRecord] from a SQLite row map.
  factory AppUsageRecord.fromDbMap(Map<String, dynamic> map) {
    return AppUsageRecord(
      packageName: map['packageName'] as String? ?? '',
      startTime: _toInt(map['startTime']),
      endTime: _toInt(map['endTime']),
      duration: _toInt(map['duration']),
    );
  }

  /// Safely converts a platform value (may be [int] or [double]) to [int].
  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return 0;
  }

  /// Duration formatted as a human-readable string.
  ///
  /// Examples: "2h 14m", "37m 5s", "12s"
  String get formattedDuration {
    final totalSeconds = duration ~/ 1000;
    final hours   = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }

  /// Duration in whole minutes (rounded down).
  int get durationMinutes => duration ~/ 60000;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppUsageRecord &&
          runtimeType == other.runtimeType &&
          packageName == other.packageName &&
          startTime == other.startTime &&
          endTime == other.endTime &&
          duration == other.duration;

  @override
  int get hashCode =>
      packageName.hashCode ^
      startTime.hashCode ^
      endTime.hashCode ^
      duration.hashCode;

  @override
  String toString() =>
      'AppUsageRecord('
      'packageName: $packageName, '
      'startTime: $startTime, '
      'endTime: $endTime, '
      'duration: $formattedDuration'
      ')';
}
