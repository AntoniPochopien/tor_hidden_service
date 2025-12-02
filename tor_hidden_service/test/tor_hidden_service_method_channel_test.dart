import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tor_hidden_service/tor_hidden_service_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelTorHiddenService platform = MethodChannelTorHiddenService();
  const MethodChannel channel = MethodChannel('tor_hidden_service');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        return '42';
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });
}
