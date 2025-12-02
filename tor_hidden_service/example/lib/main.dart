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

  final List<String> _logs = [];
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    // Subscribe to logs immediately
    _torService.onLog.listen((log) {
      setState(() {
        _logs.add(log);
      });
      // Auto-scroll to bottom
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _initTor() async {
    setState(() {
      _status = 'Starting...';
      _isRunning = true;
      _logs.clear();
      _logs.add("⏳ Requesting Tor Start...");
    });

    try {
      await _torService.start();

      // Get the address
      final hostname = await _torService.getOnionHostname();

      setState(() {
        _status = 'Running';
        _onionUrl = hostname ?? 'Error getting hostname';
      });
    } catch (e) {
      setState(() {
        _status = 'Error';
        _logs.add("CRITICAL ERROR: $e");
      });
    }
  }

  Future<void> _stopTor() async {
    await _torService.stop();
    setState(() {
      _status = 'Stopped';
      _isRunning = false;
      _onionUrl = 'Not generated yet';
      _torIp = 'Unknown';
    });
  }

  Future<void> _testTorConnection() async {
    if (!_isRunning) {
      setState(() => _logs.add("⚠️ Tor is not running!"));
      return;
    }

    setState(() {
      _logs.add("🌍 Testing Tor Proxy Connection...");
      _torIp = "Fetching...";
    });

    try {
      // 1. Get the "Torified" Client
      final client = _torService.getTorHttpClient();

      // 2. Make a request to a site that echoes IP
      final request = await client.getUrl(Uri.parse('https://api.ipify.org'));

      // Set a timeout
      final response = await request.close().timeout(const Duration(seconds: 15));
      final responseBody = await response.transform(utf8.decoder).join();

      setState(() {
        _torIp = responseBody;
        _logs.add("✅ SUCCESS! Tor Exit Node IP: $_torIp");
      });

    } catch (e) {
      setState(() {
        _torIp = "Error";
        _logs.add("❌ Connection Failed: $e");
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
            // --- TOP CONTROL PANEL ---
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[200],
              child: Column(
                children: [
                  Text('Status: $_status', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),

                  // Onion URL with Tap-to-Copy
                  InkWell(
                    onTap: _copyToClipboard,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blueAccent)
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.copy, size: 16, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(
                            _onionUrl.length > 20 ? "${_onionUrl.substring(0, 15)}..." : _onionUrl,
                            style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Courier'
                            )
                          ),
                        ],
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

                  // IP Check Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Tor IP: $_torIp", style: const TextStyle(fontWeight: FontWeight.bold)),
                      ElevatedButton(
                        onPressed: _testTorConnection,
                        child: const Text('Check IP'),
                      )
                    ],
                  )
                ],
              ),
            ),

            // --- LOG CONSOLE HEADER ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.black87,
              child: const Text(
                "Tor Log Output",
                style: TextStyle(color: Colors.greenAccent, fontFamily: 'Courier', fontWeight: FontWeight.bold)
              ),
            ),

            // --- LOG CONSOLE ---
            Expanded(
              child: Container(
                color: Colors.black,
                width: double.infinity,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    return Text(
                      log,
                      style: const TextStyle(
                        color: Colors.green,
                        fontFamily: 'Courier',
                        fontSize: 12
                      )
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}