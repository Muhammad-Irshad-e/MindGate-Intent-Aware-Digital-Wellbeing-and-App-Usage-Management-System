import 'app_category_model.dart';

class AppUsageItem {
  final String appName;
  final String packageName;
  final int durationMinutes;
  final AppCategoryType category;
  final String iconKey;

  const AppUsageItem({
    required this.appName,
    required this.packageName,
    required this.durationMinutes,
    required this.category,
    required this.iconKey,
  });

  String get formattedDuration {
    final hours = durationMinutes ~/ 60;
    final mins = durationMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }
}

class DailyUsageSummary {
  final int totalMinutes;
  final int productiveMinutes;
  final int neutralMinutes;
  final int negativeMinutes;
  final int vsYesterdayPercentage;
  final int cpiScore;
  final String cpiStatus;

  const DailyUsageSummary({
    required this.totalMinutes,
    required this.productiveMinutes,
    required this.neutralMinutes,
    required this.negativeMinutes,
    required this.vsYesterdayPercentage,
    required this.cpiScore,
    required this.cpiStatus,
  });

  String get formattedTotalTime {
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    return '${hours}h ${mins}m';
  }

  int get productivePercentage => totalMinutes == 0 ? 0 : ((productiveMinutes / totalMinutes) * 100).round();
  int get neutralPercentage => totalMinutes == 0 ? 0 : ((neutralMinutes / totalMinutes) * 100).round();
  int get negativePercentage => totalMinutes == 0 ? 0 : ((negativeMinutes / totalMinutes) * 100).round();

  String formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }
}
