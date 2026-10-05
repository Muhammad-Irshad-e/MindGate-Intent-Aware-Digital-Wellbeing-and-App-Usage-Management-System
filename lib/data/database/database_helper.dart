import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/app_category_model.dart';
import '../models/app_usage_record.dart';
import '../models/user_settings_model.dart';

/// MindGate local SQLite database manager.
///
/// Handles database initialization, table creation, schema versioning,
/// and parameterized CRUD operations for app categories, usage records, and user settings.
class DatabaseHelper {
  static const String _dbName = 'mindgate.db';
  static const int _dbVersion = 1;

  // Table names
  static const String tableAppCategories = 'app_categories';
  static const String tableUsageRecords  = 'usage_records';
  static const String tableUserSettings  = 'user_settings';

  static DatabaseHelper? _instance;
  Database? _database;

  DatabaseHelper._internal();

  /// Returns singleton instance of [DatabaseHelper].
  factory DatabaseHelper() {
    _instance ??= DatabaseHelper._internal();
    return _instance!;
  }

  /// Allows injecting a custom [Database] instance (e.g. for testing with sqflite_ffi).
  DatabaseHelper.withDatabase(this._database) {
    _instance = this;
  }

  /// Gets initialized SQLite database reference.
  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // 1. app_categories table
    await db.execute('''
      CREATE TABLE $tableAppCategories (
        packageName TEXT PRIMARY KEY,
        appName TEXT NOT NULL,
        iconAsset TEXT NOT NULL,
        category TEXT NOT NULL
      )
    ''');

    // 2. usage_records table
    await db.execute('''
      CREATE TABLE $tableUsageRecords (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        packageName TEXT NOT NULL,
        startTime INTEGER NOT NULL,
        endTime INTEGER NOT NULL,
        duration INTEGER NOT NULL
      )
    ''');

    // 3. user_settings table
    await db.execute('''
      CREATE TABLE $tableUserSettings (
        settingId INTEGER PRIMARY KEY,
        negativeAppLimit INTEGER NOT NULL,
        neutralAppLimit INTEGER NOT NULL,
        productiveAppLimit INTEGER NOT NULL,
        gracePeriod INTEGER NOT NULL,
        snoozeEnabled INTEGER NOT NULL,
        snoozeDuration INTEGER NOT NULL,
        usageLimitsEnabled INTEGER NOT NULL
      )
    ''');

    // Insert initial default user settings row
    const defaultSettings = UserSettings(
      settingId: 1,
      negativeAppLimit: 30,
      neutralAppLimit: 120,
      productiveAppLimit: -1,
      gracePeriod: 5,
      snoozeEnabled: true,
      snoozeDuration: 5,
      usageLimitsEnabled: true,
    );
    await db.insert(
      tableUserSettings,
      defaultSettings.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── APP CATEGORIES CRUD ───────────────────────────────────────────────────

  /// Inserts or updates an application category record.
  Future<void> insertOrUpdateAppCategory(AppCategoryInfo categoryInfo) async {
    final db = await database;
    await db.insert(
      tableAppCategories,
      categoryInfo.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Inserts or updates a list of application category records in a batch transaction.
  Future<void> saveAppCategoriesBatch(List<AppCategoryInfo> categories) async {
    final db = await database;
    final batch = db.batch();
    for (final cat in categories) {
      batch.insert(
        tableAppCategories,
        cat.toDbMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Retrieves all persisted application categories.
  Future<List<AppCategoryInfo>> getAllAppCategories() async {
    final db = await database;
    final maps = await db.query(tableAppCategories, orderBy: 'appName ASC');
    return maps.map((m) => AppCategoryInfo.fromDbMap(m)).toList();
  }

  /// Retrieves an application category by package name.
  Future<AppCategoryInfo?> getAppCategoryByPackageName(String packageName) async {
    final db = await database;
    final maps = await db.query(
      tableAppCategories,
      where: 'packageName = ?',
      whereArgs: [packageName],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return AppCategoryInfo.fromDbMap(maps.first);
  }

  /// Updates the category classification for a given package name.
  Future<void> updateAppCategory(String packageName, AppCategoryType category) async {
    final db = await database;
    await db.update(
      tableAppCategories,
      {'category': category.name},
      where: 'packageName = ?',
      whereArgs: [packageName],
    );
  }

  // ── USAGE RECORDS CRUD ─────────────────────────────────────────────────────

  /// Inserts a foreground app usage session record.
  /// Deduplicates records with identical packageName, startTime, and endTime.
  Future<int> insertUsageRecord(AppUsageRecord record) async {
    final db = await database;
    final existing = await db.query(
      tableUsageRecords,
      where: 'packageName = ? AND startTime = ? AND endTime = ?',
      whereArgs: [record.packageName, record.startTime, record.endTime],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return existing.first['id'] as int? ?? 0;
    }
    return await db.insert(tableUsageRecords, record.toDbMap());
  }

  /// Retrieves all recorded usage session records.
  Future<List<AppUsageRecord>> getAllUsageRecords() async {
    final db = await database;
    final maps = await db.query(tableUsageRecords, orderBy: 'startTime DESC');
    return maps.map((m) => AppUsageRecord.fromDbMap(m)).toList();
  }

  /// Retrieves usage records for a specific time range [startTime] to [endTime] (epoch ms).
  ///
  /// Uses interval overlap semantics: record.endTime > rangeStart AND record.startTime < rangeEnd.
  Future<List<AppUsageRecord>> getUsageRecordsByDateRange(int startTime, int endTime) async {
    final db = await database;
    final maps = await db.query(
      tableUsageRecords,
      where: 'endTime > ? AND startTime < ?',
      whereArgs: [startTime, endTime],
      orderBy: 'startTime ASC',
    );
    return maps.map((m) => AppUsageRecord.fromDbMap(m)).toList();
  }

  /// Retrieves usage records for a specific package name.
  Future<List<AppUsageRecord>> getUsageRecordsForPackage(String packageName) async {
    final db = await database;
    final maps = await db.query(
      tableUsageRecords,
      where: 'packageName = ?',
      whereArgs: [packageName],
      orderBy: 'startTime DESC',
    );
    return maps.map((m) => AppUsageRecord.fromDbMap(m)).toList();
  }

  // ── USER SETTINGS CRUD ────────────────────────────────────────────────────

  /// Saves or updates user settings.
  Future<void> saveUserSettings(UserSettings settings) async {
    final db = await database;
    await db.insert(
      tableUserSettings,
      settings.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves user settings, returning default settings if no record exists.
  Future<UserSettings> getUserSettings() async {
    final db = await database;
    final maps = await db.query(
      tableUserSettings,
      where: 'settingId = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (maps.isEmpty) {
      const defaults = UserSettings(
        settingId: 1,
        negativeAppLimit: 30,
        neutralAppLimit: 120,
        productiveAppLimit: -1,
        gracePeriod: 5,
        snoozeEnabled: true,
        snoozeDuration: 5,
        usageLimitsEnabled: true,
      );
      await saveUserSettings(defaults);
      return defaults;
    }
    return UserSettings.fromDbMap(maps.first);
  }

  /// Close database instance connection.
  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
    _instance = null;
  }
}
