import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

class TorHiddenService {
  final _methodChannel = const MethodChannel('tor_hidden_service');
  final _eventChannel = const EventChannel('tor_hidden_service/logs');

  // The HTTP Tunnel port defined in Kotlin/Java (Usually 9080)
  static const int _torHttpProxyPort = 9080;

  /// Listen to this stream to get real-time logs from the Tor process
  Stream<String> get onLog {
    return _eventChannel.receiveBroadcastStream().map((event) => event.toString());
  }

  Future<String> start() async {
    await _startLocalServer();
    // This call will hang until Tor bootstraps to 100%
    final String result = await _methodChannel.invokeMethod('startTor');
    return result;
  }

  Future<void> stop() async {
    await _methodChannel.invokeMethod('stopTor');
  }

  Future<String?> getOnionHostname() async {
    try {
      final String hostname = await _methodChannel.invokeMethod('getHostname');
      return hostname;
    } on PlatformException catch (_) {
      return null;
    }
  }

  /// Returns an HttpClient configured to route traffic through Tor.
  /// IGNORES SSL/TLS CERTIFICATE ERRORS for self-signed Onion sites.
  HttpClient getTorHttpClient() {
    final client = HttpClient();

    // 1. Configure the proxy
    client.findProxy = (uri) {
      return "PROXY localhost:$_torHttpProxyPort";
    };

    // 2. CRITICAL FIX: Trust Self-Signed Certificates
    // This allows Flutter to connect to Go peers using generated certs.
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;

    return client;
  }

  Future<void> _startLocalServer() async {
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8080);
      print('🎯 Local server running on port 8080');
      server.listen((HttpRequest request) {
        request.response
          ..headers.contentType = ContentType.html
          ..write('<h1>Hello from Flutter Onion!</h1>')
          ..close();
      });
    } catch (e) {
      print("Server check (likely already running): $e");
    }
  }
}