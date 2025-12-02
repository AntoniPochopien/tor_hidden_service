import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

class TorHiddenService {
  final _methodChannel = const MethodChannel('tor_hidden_service');
  final _eventChannel = const EventChannel('tor_hidden_service/logs');

  static const int _torHttpProxyPort = 9080;

  Stream<String> get onLog {
    return _eventChannel.receiveBroadcastStream().map((event) => event.toString());
  }

  Future<String> start() async {
    return await _methodChannel.invokeMethod('startTor');
  }

  Future<void> stop() async {
    await _methodChannel.invokeMethod('stopTor');
  }

  Future<String?> getOnionHostname() async {
    try {
      return await _methodChannel.invokeMethod('getHostname');
    } on PlatformException catch (_) {
      return null;
    }
  }

  /// Returns a standard HttpClient for HTTPS requests (e.g. standard web or SSL onions).
  HttpClient getSecureTorClient() {
    final client = HttpClient();
    client.findProxy = (uri) => "PROXY localhost:$_torHttpProxyPort";
    client.connectionTimeout = const Duration(seconds: 30);
    client.badCertificateCallback = (cert, host, port) => true;
    return client;
  }

  /// Returns a client specifically designed for unsecure (HTTP) .onion addresses.
  TorOnionClient getUnsecureTorClient() {
    return TorOnionClient(proxyPort: _torHttpProxyPort);
  }
}

/// 🌟 A custom HTTP Client that tunnels plain HTTP through Tor 🌟
class TorOnionClient {
  final int proxyPort;

  TorOnionClient({required this.proxyPort});

  Future<TorResponse> get(String url, {Map<String, String>? headers}) async {
    return _send('GET', url, headers: headers);
  }

  Future<TorResponse> post(String url, {Map<String, String>? headers, String? body}) async {
    return _send('POST', url, headers: headers, body: body);
  }

  Future<TorResponse> put(String url, {Map<String, String>? headers, String? body}) async {
    return _send('PUT', url, headers: headers, body: body);
  }

  Future<TorResponse> delete(String url, {Map<String, String>? headers}) async {
    return _send('DELETE', url, headers: headers);
  }

  Future<TorResponse> _send(String method, String url, {
    Map<String, String>? headers,
    String? body
  }) async {
    Socket? socket;
    try {
      final uri = Uri.parse(url);

      // 1. Connect to Local Tor Proxy
      socket = await Socket.connect('127.0.0.1', proxyPort,
          timeout: const Duration(seconds: 15));

      // 2. Perform CONNECT Handshake
      final targetPort = uri.port == 0 ? 80 : uri.port;
      final handshake = 'CONNECT ${uri.host}:$targetPort HTTP/1.1\r\n'
                        'Host: ${uri.host}:$targetPort\r\n'
                        '\r\n';
      socket.write(handshake);
      await socket.flush();

      // Completer to return the final response once parsing is done
      final responseCompleter = Completer<TorResponse>();

      // Buffer to accumulate incoming data
      final buffer = <int>[];

      // State flags
      bool handshakeComplete = false;

      // 3. Single Listener for the entire socket lifecycle
      final subscription = socket.listen((data) {
        buffer.addAll(data);

        // Check for Handshake completion if not yet done
        if (!handshakeComplete) {
          final tempString = utf8.decode(buffer, allowMalformed: true);
          if (tempString.contains('200 OK')) {
            // Handshake Success!
            // Clear the buffer because it contains proxy headers we don't need
            buffer.clear();
            handshakeComplete = true;

            // 4. Send the Real HTTP Request immediately
            _writeHttpRequest(socket!, method, uri, headers, body);
          } else if (tempString.contains('\r\n\r\n')) {
             // Handshake failed (e.g. 503 Service Unavailable)
             socket!.destroy();
             if (!responseCompleter.isCompleted) {
               responseCompleter.completeError("Proxy Handshake Failed (502/503)");
             }
          }
        }
        // We are in "Response Mode" -> Just keep buffering until socket closes
      }, onDone: () {
        // Socket closed by server -> Process the accumulated response
        if (handshakeComplete && !responseCompleter.isCompleted) {
          final fullString = utf8.decode(buffer, allowMalformed: true);
          responseCompleter.complete(_parseRawResponse(fullString));
        } else if (!responseCompleter.isCompleted) {
          responseCompleter.completeError("Connection closed before response received");
        }
      }, onError: (e) {
        if (!responseCompleter.isCompleted) responseCompleter.completeError(e);
      });

      return await responseCompleter.future;

    } catch (e) {
      socket?.destroy();
      throw Exception("Tor Request Failed: $e");
    }
  }

  void _writeHttpRequest(Socket socket, String method, Uri uri, Map<String, String>? headers, String? body) {
    final path = uri.path.isEmpty ? "/" : uri.path;
    final sb = StringBuffer();
    sb.write('$method $path HTTP/1.1\r\n');
    sb.write('Host: ${uri.host}\r\n');
    sb.write('Connection: close\r\n'); // Close connection after response

    headers?.forEach((key, value) {
      sb.write('$key: $value\r\n');
    });

    if (body != null) {
      final bodyBytes = utf8.encode(body);
      sb.write('Content-Length: ${bodyBytes.length}\r\n');
      if (headers == null || !headers.keys.any((k) => k.toLowerCase() == 'content-type')) {
          sb.write('Content-Type: application/json\r\n');
      }
    }

    sb.write('\r\n'); // End of headers
    if (body != null) sb.write(body);

    socket.write(sb.toString());
    socket.flush();
  }

  TorResponse _parseRawResponse(String raw) {
    // Split Headers and Body
    final splitIndex = raw.indexOf('\r\n\r\n');

    if (splitIndex == -1) {
      return TorResponse(statusCode: 500, body: raw, headers: {});
    }

    final headerString = raw.substring(0, splitIndex);
    final bodyString = raw.substring(splitIndex + 4);

    // Parse Status Code (Line 1)
    final statusLine = headerString.split('\r\n')[0]; // "HTTP/1.1 200 OK"
    final statusCode = int.tryParse(statusLine.split(' ')[1]) ?? 0;

    // Parse Headers
    final headers = <String, String>{};
    final headerLines = headerString.split('\r\n').skip(1);
    for (final line in headerLines) {
      final parts = line.split(': ');
      if (parts.length == 2) {
        headers[parts[0]] = parts[1];
      }
    }

    return TorResponse(
      statusCode: statusCode,
      body: bodyString,
      headers: headers
    );
  }
}

class TorResponse {
  final int statusCode;
  final String body;
  final Map<String, String> headers;

  TorResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  @override
  String toString() => 'TorResponse($statusCode): $body';
}