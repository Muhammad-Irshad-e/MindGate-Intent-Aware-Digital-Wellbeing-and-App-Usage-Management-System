import 'package:flutter_test/flutter_test.dart';
import 'package:mindgate/data/models/app_info.dart';

void main() {
  group('AppInfo Model Tests', () {
    test('creates AppInfo correctly via constructor', () {
      const app = AppInfo(
        packageName: 'com.google.android.youtube',
        appName: 'YouTube',
      );

      expect(app.packageName, equals('com.google.android.youtube'));
      expect(app.appName, equals('YouTube'));
    });

    test('creates AppInfo correctly from valid Map', () {
      final map = {
        'packageName': 'com.whatsapp',
        'appName': 'WhatsApp',
      };

      final app = AppInfo.fromMap(map);

      expect(app.packageName, equals('com.whatsapp'));
      expect(app.appName, equals('WhatsApp'));
    });

    test('handles empty or malformed Map safely', () {
      final map = <String, dynamic>{};

      final app = AppInfo.fromMap(map);

      expect(app.packageName, isEmpty);
      expect(app.appName, isEmpty);
    });

    test('serializes AppInfo to Map correctly', () {
      const app = AppInfo(
        packageName: 'com.instagram.android',
        appName: 'Instagram',
      );

      final map = app.toMap();

      expect(map['packageName'], equals('com.instagram.android'));
      expect(map['appName'], equals('Instagram'));
    });

    test('equality and hashCode work as expected', () {
      const app1 = AppInfo(packageName: 'com.example.app', appName: 'Example');
      const app2 = AppInfo(packageName: 'com.example.app', appName: 'Example');
      const app3 = AppInfo(packageName: 'com.example.other', appName: 'Other');

      expect(app1, equals(app2));
      expect(app1.hashCode, equals(app2.hashCode));
      expect(app1, isNot(equals(app3)));
    });
  });
}
