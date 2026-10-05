import '../models/app_category_model.dart';
import '../models/app_usage_model.dart';
import '../models/user_settings_model.dart';

class MockDataRepository {
  static const DailyUsageSummary summary = DailyUsageSummary(
    totalMinutes: 204, // 3h 24m
    productiveMinutes: 96, // 1h 36m
    neutralMinutes: 68, // 1h 08m
    negativeMinutes: 40, // 40m
    vsYesterdayPercentage: 12,
    cpiScore: 78,
    cpiStatus: "You're on track!",
  );

  static const List<AppUsageItem> topAppsToday = [
    AppUsageItem(
      appName: 'VS Code',
      packageName: 'com.microsoft.vscode',
      durationMinutes: 25,
      category: AppCategoryType.productive,
      iconKey: 'vscode',
    ),
    AppUsageItem(
      appName: 'Notion',
      packageName: 'so.notion.app',
      durationMinutes: 18,
      category: AppCategoryType.productive,
      iconKey: 'notion',
    ),
    AppUsageItem(
      appName: 'WhatsApp',
      packageName: 'com.whatsapp',
      durationMinutes: 35,
      category: AppCategoryType.neutral,
      iconKey: 'whatsapp',
    ),
    AppUsageItem(
      appName: 'Instagram',
      packageName: 'com.instagram.android',
      durationMinutes: 20,
      category: AppCategoryType.negative,
      iconKey: 'instagram',
    ),
  ];

  static List<AppCategoryInfo> allAppCategories = [
    const AppCategoryInfo(
      appName: 'YouTube',
      packageName: 'com.google.android.youtube',
      iconAsset: 'youtube',
      category: AppCategoryType.negative,
    ),
    const AppCategoryInfo(
      appName: 'WhatsApp',
      packageName: 'com.whatsapp',
      iconAsset: 'whatsapp',
      category: AppCategoryType.neutral,
    ),
    const AppCategoryInfo(
      appName: 'Chrome',
      packageName: 'com.android.chrome',
      iconAsset: 'chrome',
      category: AppCategoryType.neutral,
    ),
    const AppCategoryInfo(
      appName: 'VS Code',
      packageName: 'com.microsoft.vscode',
      iconAsset: 'vscode',
      category: AppCategoryType.productive,
    ),
    const AppCategoryInfo(
      appName: 'Notion',
      packageName: 'so.notion.app',
      iconAsset: 'notion',
      category: AppCategoryType.productive,
    ),
    const AppCategoryInfo(
      appName: 'Instagram',
      packageName: 'com.instagram.android',
      iconAsset: 'instagram',
      category: AppCategoryType.negative,
    ),
    const AppCategoryInfo(
      appName: 'Spotify',
      packageName: 'com.spotify.music',
      iconAsset: 'spotify',
      category: AppCategoryType.neutral,
    ),
    const AppCategoryInfo(
      appName: 'Gmail',
      packageName: 'com.google.android.gm',
      iconAsset: 'gmail',
      category: AppCategoryType.productive,
    ),
  ];

  static const UserSettings defaultSettings = UserSettings(
    settingId: 1,
    negativeAppLimit: 30,
    neutralAppLimit: 120,
    productiveAppLimit: -1,
    gracePeriod: 5,
    snoozeEnabled: true,
    snoozeDuration: 5,
    usageLimitsEnabled: true,
  );

  static const List<double> hourlyUsageBars = [
    5.0, 10.0, 3.0, 15.0, 45.0, 30.0, 60.0, 25.0, 35.0, 20.0, 15.0, 8.0
  ];

  static const List<double> cpi7DayTrend = [
    60.0, 52.0, 58.0, 50.0, 72.0, 68.0, 78.0
  ];
}
