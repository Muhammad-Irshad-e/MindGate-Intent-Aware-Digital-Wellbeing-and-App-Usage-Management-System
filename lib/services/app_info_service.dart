import 'package:flutter/services.dart';
import '../data/database/database_helper.dart';
import '../data/mock/mock_data.dart';
import '../data/models/app_category_model.dart';
import '../data/models/app_info.dart';
import 'classifier/application_classifier.dart';

/// Provides application information and category management services backed by local SQLite storage.
class AppInfoService {
  static const MethodChannel _appsChannel = MethodChannel('com.mindgate/apps');

  final DatabaseHelper _dbHelper;
  final ApplicationClassifier _classifier;

  AppInfoService({
    DatabaseHelper? dbHelper,
    ApplicationClassifier? classifier,
  })  : _dbHelper = dbHelper ?? DatabaseHelper(),
        _classifier = classifier ?? const HeuristicApplicationClassifier();

  /// Returns active [ApplicationClassifier] instance.
  ApplicationClassifier get classifier => _classifier;

  /// Returns installed launchable applications from Android native platform.
  Future<List<AppInfo>> getInstalledApps() async {
    try {
      final rawApps =
          await _appsChannel.invokeMethod<List<dynamic>>('getInstalledApps');
      if (rawApps == null || rawApps.isEmpty) return [];

      return rawApps
          .whereType<Map>()
          .map((m) => AppInfo.fromMap(m))
          .where((app) => app.packageName.isNotEmpty && app.appName.isNotEmpty)
          .toList();
    } on PlatformException {
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Assigns a default category using internal [ApplicationClassifier].
  AppCategoryType assignDefaultCategory(String packageName, [String appName = '']) {
    return _classifier.classify(AppInfo(packageName: packageName, appName: appName));
  }

  /// Loads application categories, retrieving from SQLite or syncing with platform installed apps.
  Future<List<AppCategoryInfo>> getAppCategories() async {
    try {
      final existingDbCategories = await _dbHelper.getAllAppCategories();
      final installedApps = await getInstalledApps();

      if (installedApps.isEmpty) {
        if (existingDbCategories.isNotEmpty) {
          return existingDbCategories;
        }
        // Fallback to mock categories on non-Android platform or missing apps
        final mockList = MockDataRepository.allAppCategories.map((cat) {
          return AppCategoryInfo(
            packageName: cat.packageName,
            appName: cat.appName,
            iconAsset: cat.iconAsset,
            category: _classifier.classify(AppInfo(packageName: cat.packageName, appName: cat.appName)),
          );
        }).toList();
        await _dbHelper.saveAppCategoriesBatch(mockList);
        return mockList;
      }

      final existingMap = {
        for (var cat in existingDbCategories) cat.packageName: cat
      };

      final List<AppCategoryInfo> result = [];
      final List<AppCategoryInfo> toInsert = [];

      for (final app in installedApps) {
        if (existingMap.containsKey(app.packageName)) {
          // Respect existing SQLite entry (including manual user overrides)
          result.add(existingMap[app.packageName]!);
        } else {
          final newCat = AppCategoryInfo(
            packageName: app.packageName,
            appName: app.appName,
            iconAsset: _deriveIconAsset(app.packageName),
            category: _classifier.classify(app),
          );
          result.add(newCat);
          toInsert.add(newCat);
        }
      }

      if (toInsert.isNotEmpty) {
        await _dbHelper.saveAppCategoriesBatch(toInsert);
      }

      return result;
    } catch (_) {
      return List.from(MockDataRepository.allAppCategories);
    }
  }

  /// Persists a category update for an application into local SQLite storage.
  Future<void> updateCategory(String packageName, AppCategoryType newCategory) async {
    try {
      await _dbHelper.updateAppCategory(packageName, newCategory);
    } catch (_) {}
  }

  String _deriveIconAsset(String packageName) {
    final lower = packageName.toLowerCase();
    if (lower.contains('youtube')) return 'youtube';
    if (lower.contains('whatsapp')) return 'whatsapp';
    if (lower.contains('chrome')) return 'chrome';
    if (lower.contains('vscode')) return 'vscode';
    if (lower.contains('notion')) return 'notion';
    if (lower.contains('instagram')) return 'instagram';
    if (lower.contains('spotify')) return 'spotify';
    if (lower.contains('gmail') || lower.endsWith('.gm')) return 'gmail';
    return packageName;
  }
}
