import 'package:flutter_test/flutter_test.dart';
import 'package:tor_hidden_service/tor_hidden_service.dart';
import 'package:tor_hidden_service/tor_hidden_service_platform_interface.dart';
import 'package:tor_hidden_service/tor_hidden_service_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockTorHiddenServicePlatform
    with MockPlatformInterfaceMixin
    implements TorHiddenServicePlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final TorHiddenServicePlatform initialPlatform = TorHiddenServicePlatform.instance;

  test('$MethodChannelTorHiddenService is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelTorHiddenService>());
  });

  test('getPlatformVersion', () async {
    TorHiddenService torHiddenServicePlugin = TorHiddenService();
    MockTorHiddenServicePlatform fakePlatform = MockTorHiddenServicePlatform();
    TorHiddenServicePlatform.instance = fakePlatform;

    expect(await torHiddenServicePlugin.getPlatformVersion(), '42');
  });
}
