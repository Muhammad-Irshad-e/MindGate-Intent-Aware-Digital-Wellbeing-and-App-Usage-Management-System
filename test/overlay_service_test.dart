import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindgate/services/overlay_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.mindgate/overlay');
  final log = <MethodCall>[];

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      log.add(methodCall);
      switch (methodCall.method) {
        case 'showOverlay':
          return true;
        case 'hideOverlay':
          return true;
        case 'isOverlayShowing':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('showOverlay sends correct arguments to native channel', () async {
    final service = OverlayService();

    final success = await service.showOverlay(
      packageName: 'com.instagram.android',
      appName: 'Instagram',
      categoryName: 'Negative',
      usedMinutes: 35,
      remainingSeconds: 299,
      snoozeEnabled: true,
      snoozeDuration: 5,
    );

    expect(success, isTrue);
    expect(log.length, equals(1));
    expect(log.first.method, equals('showOverlay'));
    final args = log.first.arguments as Map;
    expect(args['packageName'], equals('com.instagram.android'));
    expect(args['appName'], equals('Instagram'));
    expect(args['categoryName'], equals('Negative'));
    expect(args['usedMinutes'], equals(35));
    expect(args['remainingSeconds'], equals(299));
    expect(args['snoozeEnabled'], isTrue);
    expect(args['snoozeDuration'], equals(5));
  });

  test('hideOverlay sends hideOverlay command to native channel', () async {
    final service = OverlayService();

    final success = await service.hideOverlay();

    expect(success, isTrue);
    expect(log.length, equals(1));
    expect(log.first.method, equals('hideOverlay'));
  });

  test('isOverlayShowing queries native overlay visibility', () async {
    final service = OverlayService();

    final showing = await service.isOverlayShowing();

    expect(showing, isTrue);
    expect(log.length, equals(1));
    expect(log.first.method, equals('isOverlayShowing'));
  });

  test('handles native callbacks for onTakeBreak and onSnooze', () async {
    bool tookBreak = false;
    bool snoozed = false;

    OverlayService(
      onTakeBreak: () => tookBreak = true,
      onSnooze: () => snoozed = true,
    );

    // Simulate incoming native calls via binary messenger
    final codec = const StandardMethodCodec();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    final takeBreakCall = codec.encodeMethodCall(const MethodCall('onTakeBreak'));
    await messenger.handlePlatformMessage('com.mindgate/overlay', takeBreakCall, (_) {});
    expect(tookBreak, isTrue);

    final snoozeCall = codec.encodeMethodCall(const MethodCall('onSnooze'));
    await messenger.handlePlatformMessage('com.mindgate/overlay', snoozeCall, (_) {});
    expect(snoozed, isTrue);
  });
}
