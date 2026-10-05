/// Represents the Cognitive Productivity Index (CPI) calculation result for a given time period.
class CpiResult {
  /// Total productive app usage duration in milliseconds.
  final int productiveDurationMs;

  /// Total neutral app usage duration in milliseconds.
  final int neutralDurationMs;

  /// Total negative app usage duration in milliseconds.
  final int negativeDurationMs;

  /// Total classified usage duration in milliseconds (productive + neutral + negative).
  final int totalDurationMs;

  /// Cognitive Productivity Index score ranging from 0 to 100.
  final int cpiScore;

  const CpiResult({
    required this.productiveDurationMs,
    required this.neutralDurationMs,
    required this.negativeDurationMs,
    required this.totalDurationMs,
    required this.cpiScore,
  });

  /// Duration in whole minutes (rounded down).
  int get productiveMinutes => productiveDurationMs ~/ 60000;
  int get neutralMinutes => neutralDurationMs ~/ 60000;
  int get negativeMinutes => negativeDurationMs ~/ 60000;
  int get totalMinutes => totalDurationMs ~/ 60000;

  /// Category percentage proportions (rounded to integer %).
  int get productivePercentage => totalDurationMs == 0
      ? 0
      : ((productiveDurationMs / totalDurationMs) * 100).round();

  int get neutralPercentage => totalDurationMs == 0
      ? 0
      : ((neutralDurationMs / totalDurationMs) * 100).round();

  int get negativePercentage => totalDurationMs == 0
      ? 0
      : ((negativeDurationMs / totalDurationMs) * 100).round();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CpiResult &&
          runtimeType == other.runtimeType &&
          productiveDurationMs == other.productiveDurationMs &&
          neutralDurationMs == other.neutralDurationMs &&
          negativeDurationMs == other.negativeDurationMs &&
          totalDurationMs == other.totalDurationMs &&
          cpiScore == other.cpiScore;

  @override
  int get hashCode =>
      productiveDurationMs.hashCode ^
      neutralDurationMs.hashCode ^
      negativeDurationMs.hashCode ^
      totalDurationMs.hashCode ^
      cpiScore.hashCode;

  @override
  String toString() =>
      'CpiResult('
      'score: $cpiScore%, '
      'productive: ${productiveMinutes}m, '
      'neutral: ${neutralMinutes}m, '
      'negative: ${negativeMinutes}m, '
      'total: ${totalMinutes}m'
      ')';
}
