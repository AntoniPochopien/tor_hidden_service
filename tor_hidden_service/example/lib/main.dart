import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tor_hidden_service/tor_hidden_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _torService = TorHiddenService();
  final ScrollController _scrollController = ScrollController();

  String _status = 'Idle';
  String _onionUrl = 'Not generated yet';
  String _torIp = 'Unknown';
  String _loopbackResult = 'Not tested';

  final List<String> _logs = [];
  bool _isRunning = false;
  HttpServer? _localServer;

  // 🌟 DEFINE THE CLIENT
  late TorOnionClient _onionClient;

  @override
  void initState() {
    super.initState();
    // Initialize the client
    _onionClient = _torService.getUnsecureTorClient();

    _torService.onLog.listen((log) {
      if (mounted) {
        setState(() => _logs.add(log));
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  // 🌟 HOSTING LOGIC
  Future<void> _startLocalServer() async {
    if (_localServer != null) {
      setState(() => _logs.add('🎯 Local server already running.'));
      return;
    }
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
      _localServer = server;
      setState(() => _logs.add('🎯 Local server running on port 8080'));

      server.listen((HttpRequest request) async {
        // Handle POST requests to prove full functionality
        if (request.method == 'POST') {
           String content = await utf8.decodeStream(request);
           setState(() => _logs.add("📨 SERVER RECEIVED POST: $content"));
        }

        request.response
          ..headers.contentType = ContentType.html
          ..write('<h1>Hello from Flutter Onion!</h1>')
          ..close();
      });
    } catch (e) {
      setState(() => _logs.add("❌ Server bind error: $e"));
    }
  }

  Future<void> _initTor() async {
    setState(() {
      _status = 'Starting...';
      _isRunning = true;
      _logs.clear();
      _logs.add("⏳ Requesting Tor Start...");
    });

    try {
      await _startLocalServer();
      await _torService.start();
      final hostname = await _torService.getOnionHostname();

      setState(() {
        _status = 'Running';
        _onionUrl = hostname ?? 'Error getting hostname';
        _logs.add("✅ Hidden Service Hostname: $_onionUrl");
        _logs.add("⚠️ NOTE: Wait ~60s before Loopback testing.");
      });
    } catch (e) {
      setState(() {
        _status = 'Error';
        _logs.add("CRITICAL ERROR: $e");
      });
    }
  }

  Future<void> _stopTor() async {
    await _localServer?.close(force: true);
    _localServer = null;
    await _torService.stop();

    setState(() {
      _status = 'Stopped';
      _isRunning = false;
      _onionUrl = 'Not generated yet';
      _torIp = 'Unknown';
      _loopbackResult = 'Not tested';
      _logs.add("🛑 Tor service stopped.");
    });
  }

  Future<void> _testTorConnection() async {
    if (!_isRunning) return;

    setState(() {
      _logs.add("🌍 Testing External IP...");
      _torIp = "Fetching...";
    });

    try {
      final client = _torService.getSecureTorClient();
      final request = await client.getUrl(Uri.parse('https://api.ipify.org'));
      final response = await request.close().timeout(const Duration(seconds: 30));
      final responseBody = await response.transform(utf8.decoder).join();

      setState(() {
        _torIp = responseBody;
        _logs.add("✅ External IP Success: $_torIp");
      });
    } catch (e) {
      setState(() {
        _torIp = "Error";
        _logs.add("❌ External Connection Failed: $e");
      });
    }
  }

  // 🔄 LOOPBACK TEST (Using the new CLEAN Client API)
  Future<void> _testLoopback() async {
    if (!_isRunning || !_onionUrl.contains(".onion")) return;

    setState(() {
      _logs.add("🔄 Starting Loopback via TorClient...");
      _loopbackResult = "Connecting...";
    });

    try {
      final url = 'http://$_onionUrl';

      // 1. Test GET
      _logs.add("➡️ Sending GET to $url");
      final response = await _onionClient.get(url);

      if (response.statusCode == 200 && response.body.contains("Hello from Flutter Onion")) {
        _logs.add("✅ GET Success: ${response.statusCode}");
      } else {
        throw Exception("GET Failed: ${response.statusCode}");
      }

      // 2. Test POST (To prove we can send data)
      _logs.add("➡️ Sending POST to $url");
      final postResponse = await _onionClient.post(
        url,
        body: '{"status": "alive"}',
        headers: {'Content-Type': 'application/json'}
      );

      if (postResponse.statusCode == 200) {
        setState(() {
          _loopbackResult = "Success!";
          _logs.add("✅ POST Success! Loopback Verified.");
        });
      } else {
         throw Exception("POST Failed: ${postResponse.statusCode}");
      }

    } catch (e) {
      setState(() {
        _loopbackResult = "Error";
        _logs.add("❌ Loopback Error: $e");
      });
    }
  }

  void _copyToClipboard() {
    if (_onionUrl.contains(".onion")) {
      Clipboard.setData(ClipboardData(text: _onionUrl));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Onion URL copied to clipboard!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.light(useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('Tor Hidden Service')),
        body: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[200],
              child: Column(
                children: [
                  Text('Status: $_status', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: _copyToClipboard,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blueAccent)
                      ),
                      child: Text(
                        _onionUrl.length > 20 ? "${_onionUrl.substring(0, 15)}..." : _onionUrl,
                        style: const TextStyle(color: Colors.blue, fontFamily: 'Courier')
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isRunning ? null : _initTor,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start'),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: _isRunning ? _stopTor : null,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red[100]),
                        icon: const Icon(Icons.stop, color: Colors.red),
                        label: const Text('Stop', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Tor IP: $_torIp", style: const TextStyle(fontSize: 12)),
                          Text("Loopback: $_loopbackResult", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Column(
                        children: [
                          OutlinedButton(
                            onPressed: _testTorConnection,
                            child: const Text('Check IP (HTTPS)'),
                          ),
                          const SizedBox(height: 4),
                          ElevatedButton(
                            onPressed: _testLoopback,
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green[100]),
                            child: const Text('Test Client (Get/Post)'),
                          ),
                        ],
                      )
                    ],
                  )
                ],
              ),
            ),

            Expanded(
              child: Container(
                color: Colors.black,
                width: double.infinity,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: _logs.length,
                  itemBuilder: (context, index) => Text(
                    _logs[index],
                    style: const TextStyle(color: Colors.green, fontFamily: 'Courier', fontSize: 12)
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}