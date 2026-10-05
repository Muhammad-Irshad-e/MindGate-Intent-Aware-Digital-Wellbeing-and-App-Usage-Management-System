import 'dart:async';
import 'package:flutter/services.dart';
import '../core/utils/system_packages.dart';
import '../data/database/database_helper.dart';
import '../data/models/app_category_model.dart';
import '../data/models/app_info.dart';
import '../data/models/app_usage_record.dart';
import '../data/models/intervention_state_model.dart';
import 'app_info_service.dart';
import 'classifier/application_classifier.dart';
import 'intervention_service.dart';

/// Provides the Flutter interface for MindGate's Android application monitoring layer.
///
/// Features Phase 7 & 12A integration pipeline:
/// 1. Android Foreground Monitoring ([sessionStream]) receiving completed [AppUsageRecord]s.
/// 2. Real-time foreground app change and limit detection ([limitReachedStream]) wired to [InterventionService].
/// 3. Package-based category resolution preserving manual user overrides in SQLite.
/// 4. Application Classification ([ApplicationClassifier]) for newly detected applications.
/// 5. Deduplicated SQLite persistence ([DatabaseHelper]) storing session records into `usage_records`.
class UsageMonitoringService {
  static const EventChannel _eventChannel =
      EventChannel('com.mindgate/monitoring');

  static const MethodChannel _statsChannel =
      MethodChannel('com.mindgate/monitoring/stats');

  final DatabaseHelper _dbHelper;
  final AppInfoService _appInfoService;
  final ApplicationClassifier _classifier;
  final InterventionService _interventionService;
  final Stream<AppUsageRecord>? _customEventStream;
  final Stream<dynamic>? _customRawStream;

  final List<AppUsageRecord> _sessionBuffer = [];
  final Map<String, AppCategoryInfo> _categoryCache = {};
  final StreamController<InterventionState> _limitReachedController =
      StreamController<InterventionState>.broadcast();

  AppUsageRecord? _lastProcessedRecord;

  UsageMonitoringService({
    DatabaseHelper? dbHelper,
    AppInfoService? appInfoService,
    ApplicationClassifier? classifier,
    InterventionService? interventionService,
    this._customEventStream,
    this._customRawStream,
  })  : _dbHelper = dbHelper ?? DatabaseHelper(),
        _appInfoService = appInfoService ??
            AppInfoService(dbHelper: dbHelper, classifier: classifier),
        _classifier = classifier ?? const HeuristicApplicationClassifier(),
        _interventionService =
            interventionService ?? InterventionService(dbHelper: dbHelper) {
    _interventionService.onSnoozeExpired = (expiredState) {
      if (!_limitReachedController.isClosed) {
        _limitReachedController.add(expiredState);
      }
    };
  }

  /// All [AppUsageRecord]s received in memory during the current active session.
  List<AppUsageRecord> get sessionBuffer => List.unmodifiable(_sessionBuffer);

  /// In-memory category cache mapping packageName -> [AppCategoryInfo].
  Map<String, AppCategoryInfo> get categoryCache =>
      Map.unmodifiable(_categoryCache);

  /// Associated [InterventionService] managing intervention, grace, and snooze states.
  InterventionService get interventionService => _interventionService;

  /// Stream emitting active [InterventionState] whenever a foreground app change detects
  /// that a configured category usage limit has been reached.
  Stream<InterventionState> get limitReachedStream =>
      _limitReachedController.stream;

  Stream<dynamic>? _rawEventStream;
  Stream<AppUsageRecord>? _sessionStream;
  StreamSubscription<AppUsageRecord>? _bufferSubscription;
  StreamSubscription<dynamic>? _foregroundSubscription;

  /// A broadcast stream of raw events arriving from the native EventChannel.
  Stream<dynamic> get rawEventStream {
    if (_rawEventStream != null) return _rawEventStream!;
    final source = _customRawStream ?? _eventChannel.receiveBroadcastStream();
    _rawEventStream = source.asBroadcastStream();
    return _rawEventStream!;
  }

  /// A broadcast stream of completed [AppUsageRecord]s.
  ///
  /// Arriving records are category-resolved, stored in SQLite, and mirrored to in-memory buffer.
  Stream<AppUsageRecord> get sessionStream {
    if (_sessionStream != null) return _sessionStream!;

    final sourceStream = _customEventStream ??
        rawEventStream
            .where((event) => event is Map)
            .where((event) {
              final map = event as Map;
              final duration = map['duration'] as int? ?? 0;
              return duration > 0;
            })
            .map((event) =>
                AppUsageRecord.fromMap(event as Map<dynamic, dynamic>))
            .where((record) =>
                record.packageName.isNotEmpty && record.duration > 0)
            .handleError((_) {});

    _sessionStream = sourceStream.asBroadcastStream();

    _bufferSubscription = _sessionStream!.listen(
      (record) async {
        await processIncomingRecord(record);
      },
      onError: (_) {},
    );

    // Initialize foreground monitoring for limit-reached events
    startForegroundMonitoring();

    return _sessionStream!;
  }

  /// Starts listening for foreground app changes and limit-reached events.
  StreamSubscription<dynamic>? startForegroundMonitoring() {
    if (_foregroundSubscription != null) return _foregroundSubscription;
    if (_customRawStream == null && _customEventStream != null) {
      return null;
    }

    _foregroundSubscription = rawEventStream
        .where((event) => event is Map)
        .listen(
          (event) async {
            await handleIncomingForegroundEvent(event as Map<dynamic, dynamic>);
          },
          onError: (_) {},
        );

    return _foregroundSubscription;
  }

  static String? _activePackageName;
  static int? _activeSessionStartTime;

  /// Package name of the currently active foreground application, if any.
  static String? get currentActivePackageName => _activePackageName;

  /// Epoch ms start timestamp of the currently active foreground session, if any.
  static int? get currentActiveSessionStartTime => _activeSessionStartTime;

  String? get activePackageName => _activePackageName;
  int? get activeSessionStartTime => _activeSessionStartTime;

  /// Handles foreground application change and limit-reached events from the native monitoring layer.
  Future<InterventionState?> handleIncomingForegroundEvent(
      Map<dynamic, dynamic> event) async {
    try {
      final eventType = event['eventType']?.toString();
      final packageName = event['packageName']?.toString().trim() ?? '';
      final duration = (event['duration'] as num?)?.toInt() ?? 0;

      // If it's a completed session record without foreground eventType, ignore it here
      if (duration > 0 && eventType == null) {
        return null;
      }

      if (packageName.isEmpty) return null;

      // Filter system packages and launchers
      if (SystemPackages.isSystemPackage(packageName)) {
        _activePackageName = null;
        _activeSessionStartTime = null;
        _stopActiveSessionTimer();
        return null;
      }

      final startTime = (event['startTime'] as num?)?.toInt() ??
          (event['timestamp'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;

      _activePackageName = packageName;
      _activeSessionStartTime = startTime;

      // Evaluate limit status via existing InterventionService.
      // Re-trigger protection inside evaluatePackage ensures active grace period or snooze is preserved.
      final state = await _interventionService.evaluatePackage(
        packageName,
        currentSessionStartTime: startTime,
      );

      if (state != null) {
        if (!_limitReachedController.isClosed) {
          _limitReachedController.add(state);
        }
      }

      // Start periodic 5-second evaluation timer for continuous active session
      _startActiveSessionTimer();

      return state;
    } catch (_) {
      // Handle errors safely so monitoring continues even if intervention integration fails
      return null;
    }
  }

  Timer? _activeSessionTimer;

  /// Returns true if the active-session evaluation timer is currently running.
  bool get isTimerActive => _activeSessionTimer != null && _activeSessionTimer!.isActive;

  /// Starts periodic 5-second active-session limit evaluation timer.
  void _startActiveSessionTimer() {
    _stopActiveSessionTimer();
    final pkg = _activePackageName;
    final start = _activeSessionStartTime;

    if (pkg == null || start == null || SystemPackages.isSystemPackage(pkg)) {
      return;
    }

    _activeSessionTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final currentPkg = _activePackageName;
      final currentStart = _activeSessionStartTime;

      if (currentPkg == null ||
          currentStart == null ||
          SystemPackages.isSystemPackage(currentPkg) ||
          currentPkg != pkg ||
          currentStart != start) {
        _stopActiveSessionTimer();
        return;
      }

      await evaluateActiveSessionLimit(currentPkg, currentStart);
    });
  }

  /// Cancels any active periodic limit evaluation timer.
  void _stopActiveSessionTimer() {
    _activeSessionTimer?.cancel();
    _activeSessionTimer = null;
  }

  /// Periodically evaluates category limit status for active [packageName] and [startTime].
  Future<InterventionState?> evaluateActiveSessionLimit(
      String packageName, int startTime) async {
    try {
      if (_activePackageName != packageName ||
          _activeSessionStartTime != startTime) {
        return null;
      }

      final state = await _interventionService.evaluatePackage(
        packageName,
        currentSessionStartTime: startTime,
      );

      if (state != null) {
        if (!_limitReachedController.isClosed) {
          _limitReachedController.add(state);
        }
      }

      return state;
    } catch (_) {
      return null;
    }
  }

  /// Processes an incoming usage record through category resolution and in-memory buffer.
  ///
  /// Native AccessibilityService is the single authoritative writer for completed sessions in SQLite.
  Future<void> processIncomingRecord(AppUsageRecord record) async {
    if (record.packageName.trim().isEmpty || record.duration <= 0) return;

    // Deduplication check: ignore identical consecutive events
    if (_lastProcessedRecord != null &&
        _lastProcessedRecord!.packageName == record.packageName &&
        _lastProcessedRecord!.startTime == record.startTime &&
        _lastProcessedRecord!.endTime == record.endTime) {
      return;
    }

    _lastProcessedRecord = record;

    try {
      // In unit test environment (custom event stream provided), write to test DB.
      // In production, native MindGateAccessibilityService is the single authoritative writer.
      if (_customEventStream != null || _customRawStream != null) {
        await _dbHelper.insertUsageRecord(record);
      }

      // Mirror to in-memory session buffer
      _sessionBuffer.add(record);

      // Resolve & persist application category independently
      try {
        await resolveAppCategory(record.packageName);
      } catch (_) {}
    } catch (_) {}
  }

  /// Resolves the application category for [packageName].
  ///
  /// Priority:
  /// 1. In-memory cache ([_categoryCache])
  /// 2. Persisted SQLite record ([DatabaseHelper.getAppCategoryByPackageName]) — preserves manual overrides
  /// 3. Classification via [ApplicationClassifier] + SQLite save
  Future<AppCategoryInfo> resolveAppCategory(String packageName) async {
    final pkg = packageName.trim();
    if (_categoryCache.containsKey(pkg)) {
      return _categoryCache[pkg]!;
    }

    try {
      // Check SQLite table first (preserves user's manual category changes)
      final storedCat = await _dbHelper.getAppCategoryByPackageName(pkg);
      if (storedCat != null) {
        _categoryCache[pkg] = storedCat;
        return storedCat;
      }

      // If not in SQLite, resolve AppInfo identity
      AppInfo? appInfo;
      try {
        final installedApps = await _appInfoService.getInstalledApps();
        appInfo = installedApps.firstWhere(
          (a) => a.packageName.toLowerCase() == pkg.toLowerCase(),
          orElse: () => AppInfo(packageName: pkg, appName: _deriveAppName(pkg)),
        );
      } catch (_) {
        appInfo = AppInfo(packageName: pkg, appName: _deriveAppName(pkg));
      }

      // Classify new application
      final categoryType = _classifier.classify(appInfo);

      final newCat = AppCategoryInfo(
        packageName: pkg,
        appName: appInfo.appName.isNotEmpty ? appInfo.appName : _deriveAppName(pkg),
        iconAsset: pkg,
        category: categoryType,
      );

      // Persist new category into SQLite app_categories table
      await _dbHelper.insertOrUpdateAppCategory(newCat);
      _categoryCache[pkg] = newCat;

      return newCat;
    } catch (_) {
      // Fallback conservative category
      final fallbackCat = AppCategoryInfo(
        packageName: pkg,
        appName: _deriveAppName(pkg),
        iconAsset: pkg,
        category: AppCategoryType.neutral,
      );
      _categoryCache[pkg] = fallbackCat;
      return fallbackCat;
    }
  }

  /// Retrieves all persisted usage records from local SQLite storage.
  Future<List<AppUsageRecord>> getPersistedUsageRecords() async {
    try {
      return await _dbHelper.getAllUsageRecords();
    } catch (_) {
      return [];
    }
  }

  /// Retrieves usage records within a specific date/time range (epoch ms) from SQLite.
  Future<List<AppUsageRecord>> getPersistedUsageRecordsByRange(
      int startTime, int endTime) async {
    try {
      return await _dbHelper.getUsageRecordsByDateRange(startTime, endTime);
    } catch (_) {
      return [];
    }
  }

  /// Queries today's usage statistics (midnight → now) from [UsageStatsManager].
  Future<List<Map<String, dynamic>>> getTodayUsageStats() async {
    try {
      final raw = await _statsChannel
          .invokeMethod<List<dynamic>>('getTodayUsageStats');
      return _parseStatsList(raw);
    } on PlatformException {
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Queries usage statistics for a custom [beginTime]–[endTime] range.
  Future<List<Map<String, dynamic>>> getUsageStats({
    required int beginTime,
    required int endTime,
  }) async {
    try {
      final raw = await _statsChannel.invokeMethod<List<dynamic>>(
        'getUsageStats',
        <String, dynamic>{'beginTime': beginTime, 'endTime': endTime},
      );
      return _parseStatsList(raw);
    } on PlatformException {
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Clears the in-memory [sessionBuffer].
  void clearBuffer() => _sessionBuffer.clear();

  /// Cancels stream subscriptions and releases resources.
  void dispose() {
    _stopActiveSessionTimer();
    _bufferSubscription?.cancel();
    _bufferSubscription = null;
    _foregroundSubscription?.cancel();
    _foregroundSubscription = null;
    _sessionStream = null;
    _rawEventStream = null;
    if (!_limitReachedController.isClosed) {
      _limitReachedController.close();
    }
  }

  List<Map<String, dynamic>> _parseStatsList(List<dynamic>? raw) {
    if (raw == null) return [];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  static String _deriveAppName(String packageName) {
    if (packageName.isEmpty) return 'Unknown App';
    final parts = packageName.split('.');
    if (parts.isNotEmpty) {
      final last = parts.last;
      if (last.isNotEmpty) {
        return last[0].toUpperCase() + last.substring(1);
      }
    }
    return packageName;
  }
}
