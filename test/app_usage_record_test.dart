import 'package:flutter_test/flutter_test.dart';
import 'package:mindgate/data/models/app_usage_record.dart';

void main() {
  group('AppUsageRecord', () {
    test('creates AppUsageRecord correctly from constructor', () {
      const record = AppUsageRecord(
        packageName: 'com.google.android.youtube',
        startTime: 1000000,
        endTime: 1060000,
        duration: 60000,
      );

      expect(record.packageName, equals('com.google.android.youtube'));
      expect(record.startTime, equals(1000000));
      expect(record.endTime, equals(1060000));
      expect(record.duration, equals(60000));
      expect(record.durationMinutes, equals(1));
    });

    test('parses AppUsageRecord from map correctly', () {
      final map = <String, dynamic>{
        'packageName': 'com.instagram.android',
        'startTime': 1700000000000,
        'endTime': 1700000120000,
        'duration': 120000,
      };

      final record = AppUsageRecord.fromMap(map);

      expect(record.packageName, equals('com.instagram.android'));
      expect(record.startTime, equals(1700000000000));
      expect(record.endTime, equals(1700000120000));
      expect(record.duration, equals(120000));
      expect(record.formattedDuration, equals('2m 0s'));
    });

    test('handles double numbers in map safely', () {
      final map = <String, dynamic>{
        'packageName': 'com.whatsapp',
        'startTime': 1000.0,
        'endTime': 5000.0,
        'duration': 4000.0,
      };

      final record = AppUsageRecord.fromMap(map);

      expect(record.packageName, equals('com.whatsapp'));
      expect(record.startTime, equals(1000));
      expect(record.endTime, equals(5000));
      expect(record.duration, equals(4000));
      expect(record.formattedDuration, equals('4s'));
    });

    test('handles missing or malformed map values safely', () {
      final map = <String, dynamic>{};

      final record = AppUsageRecord.fromMap(map);

      expect(record.packageName, equals(''));
      expect(record.startTime, equals(0));
      expect(record.endTime, equals(0));
      expect(record.duration, equals(0));
      expect(record.formattedDuration, equals('0s'));
    });

    test('formats duration correctly for hours, minutes, and seconds', () {
      const recordHours = AppUsageRecord(
        packageName: 'com.example.app',
        startTime: 0,
        endTime: 8040000, // 2h 14m
        duration: 8040000,
      );

      const recordMinutes = AppUsageRecord(
        packageName: 'com.example.app',
        startTime: 0,
        endTime: 2225000, // 37m 5s
        duration: 2225000,
      );

      const recordSeconds = AppUsageRecord(
        packageName: 'com.example.app',
        startTime: 0,
        endTime: 12000, // 12s
        duration: 12000,
      );

      expect(recordHours.formattedDuration, equals('2h 14m'));
      expect(recordMinutes.formattedDuration, equals('37m 5s'));
      expect(recordSeconds.formattedDuration, equals('12s'));
    });
  });
}
