import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindgate/data/database/database_helper.dart';
import 'package:mindgate/data/models/user_settings_model.dart';
import 'package:mindgate/presentation/screens/usage_limits_screen.dart';
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

  group('UsageLimitsScreen & UserSettings persistence', () {
    testWidgets('loads saved settings from database when opened', (WidgetTester tester) async {
      const customSettings = UserSettings(
        settingId: 1,
        negativeAppLimit: 45,
        neutralAppLimit: 150,
        productiveAppLimit: -1,
        gracePeriod: 10,
        snoozeEnabled: true,
        snoozeDuration: 15,
        usageLimitsEnabled: false,
      );
      await dbHelper.saveUserSettings(customSettings);

      await tester.pumpWidget(
        MaterialApp(
          home: UsageLimitsScreen(databaseHelper: dbHelper),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('45 min'), findsOneWidget);
      expect(find.text('2 hrs 30 min'), findsOneWidget);
      expect(find.text('10 minutes'), findsOneWidget);
      expect(find.text('15 minutes'), findsOneWidget);
      expect(find.text('No limit'), findsOneWidget);
    });

    testWidgets('modifies and saves changed settings to SQLite', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: UsageLimitsScreen(databaseHelper: dbHelper),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Save Changes
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      final saved = await dbHelper.getUserSettings();

      // Check default values persisted
      expect(saved.negativeAppLimit, equals(30));
      expect(saved.neutralAppLimit, equals(120));
      expect(saved.productiveAppLimit, equals(-1));
      expect(saved.gracePeriod, equals(5));
      expect(saved.snoozeEnabled, isTrue);
      expect(saved.snoozeDuration, equals(5));
      expect(saved.usageLimitsEnabled, isTrue);
    });

    testWidgets('persists settings after reopening screen', (WidgetTester tester) async {
      const updatedSettings = UserSettings(
        settingId: 1,
        negativeAppLimit: 60,
        neutralAppLimit: 180,
        productiveAppLimit: -1,
        gracePeriod: 3,
        snoozeEnabled: false,
        snoozeDuration: 10,
        usageLimitsEnabled: true,
      );
      await dbHelper.saveUserSettings(updatedSettings);

      // Open screen 1st time
      await tester.pumpWidget(
        MaterialApp(
          home: UsageLimitsScreen(databaseHelper: dbHelper),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('60 min'), findsOneWidget);
      expect(find.text('3 hours'), findsOneWidget);
      expect(find.text('3 minutes'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);

      // Reopen screen 2nd time
      await tester.pumpWidget(
        MaterialApp(
          home: UsageLimitsScreen(databaseHelper: dbHelper),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('60 min'), findsOneWidget);
      expect(find.text('3 hours'), findsOneWidget);
      expect(find.text('3 minutes'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('productiveAppLimit is always -1 (No Limit)', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: UsageLimitsScreen(databaseHelper: dbHelper),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      final saved = await dbHelper.getUserSettings();
      expect(saved.productiveAppLimit, equals(-1));
    });
  });
}
