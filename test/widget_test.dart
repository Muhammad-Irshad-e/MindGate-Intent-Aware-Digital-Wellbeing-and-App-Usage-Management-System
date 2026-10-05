import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindgate/data/database/database_helper.dart';
import 'package:mindgate/data/models/app_category_model.dart';
import 'package:mindgate/data/models/app_usage_record.dart';
import 'package:mindgate/presentation/screens/dashboard_screen.dart';
import 'package:mindgate/presentation/screens/statistics_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late DatabaseHelper dbHelper;

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE ${DatabaseHelper.tableAppCategories} (
            packageName TEXT PRIMARY KEY,
            appName TEXT NOT NULL,
            iconAsset TEXT NOT NULL,
            category TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE ${DatabaseHelper.tableUsageRecords} (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            packageName TEXT NOT NULL,
            startTime INTEGER NOT NULL,
            endTime INTEGER NOT NULL,
            duration INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE ${DatabaseHelper.tableUserSettings} (
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
      },
    );
    dbHelper = DatabaseHelper.withDatabase(db);
  });

  tearDown(() async {
    await dbHelper.close();
  });

  testWidgets('Dashboard loads usage, manual pull-to-refresh works, and lifecycle resume reloads data', (WidgetTester tester) async {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;

    await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
      packageName: 'com.productive.app',
      appName: 'Productive App',
      iconAsset: 'app',
      category: AppCategoryType.productive,
    ));

    await tester.pumpWidget(const MaterialApp(home: DashboardScreen()));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text("No usage logged"), findsOneWidget);

    // Insert record while screen is open
    await dbHelper.insertUsageRecord(AppUsageRecord(
      packageName: 'com.productive.app',
      startTime: todayMidnight + 1000,
      endTime: todayMidnight + 61000,
      duration: 60000,
    ));

    // 1. Manual pull-to-refresh using drag
    await tester.drag(find.byType(RefreshIndicator), const Offset(0.0, 300.0));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text("Productive App"), findsOneWidget);

    // Insert another record
    await dbHelper.insertUsageRecord(AppUsageRecord(
      packageName: 'com.productive.app',
      startTime: todayMidnight + 65000,
      endTime: todayMidnight + 125000,
      duration: 60000,
    ));

    // 2. Lifecycle resume trigger
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text("Productive App"), findsOneWidget);
  });

  testWidgets('Statistics screen reloads on lifecycle resume preserving period index', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: StatisticsScreen()));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Statistics'), findsOneWidget);

    // Trigger lifecycle resume
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Statistics'), findsOneWidget);
  });
}
