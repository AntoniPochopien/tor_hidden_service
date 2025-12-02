# Tor Hidden Service — Flutter Plugin

A Flutter plugin that allows your mobile application to host Tor v3 Onion Services and route traffic through the Tor network.

This plugin enables True P2P on mobile:

```
Host: Your app creates a public .onion address that routes to a local server inside your app.

Client: Your app can make anonymous requests to other .onion addresses.
```

### Features

```
Android Support: Uses the Guardian Project’s Tor binaries.

Host Onion Services: Maps public Onion Port 80 to local port 8080.

HTTP Connect Tunnel: Outbound proxy on port 9080 (Compatible with Flutter HttpClient).

Bootstrap Logs: Real-time access to Tor startup progress.
```

### Installation

Add the dependency:
**YAML**

```
dependencies:
    tor_hidden_service: ^0.0.2
```

### Android Configuration

**Update AndroidManifest.xml**
To ensure the Tor binaries load correctly, add `android:extractNativeLibs="true"` to your `<application>` tag:
**XML**

```
<application
    android:label="MyApp"
    android:extractNativeLibs="true"  ...>
```

**Permissions**
Add the internet permission to `android/app/src/main/AndroidManifest.xml`:
**XML**

```
<uses-permission android:name="android.permission.INTERNENT" />
```

**Gradle Setup (Optional)**
The plugin usually configures this automatically. If you see build errors regarding missing artifacts, add the Guardian Project repository to `android/build.gradle`:
**Gradle**

```
maven { url "https://raw.githubusercontent.com/guardianproject/gpmaven/master" }
```

---

### Usage

#### 1. Start Tor

Tor must be running before you can host or make requests. Bootstrap takes 20–40 seconds.
**Dart**

```dart
import 'package:tor_hidden_service/tor_hidden_service.dart';

final _torService = TorHiddenService();

// Optional: Listen to bootstrap logs
_torService.onLog.listen((log) => print("TOR: $log"));

await _torService.start();
```

#### 2. Host a Service (Incoming Traffic)

The plugin automatically maps your generated .onion address (Port 80) to your Localhost Port 8080.
To receive traffic, simply start a standard HTTP server in Flutter binding to that port.
**Dart**

```dart
import 'dart:io';

// This server will be accessible via the .onion address!
HttpServer server = await HttpServer.bind('127.0.0.1', 8080);
server.listen((request) {
  request.response.write('Hello from the Onion Network!');
  request.response.close();
});

// Get your public address
String? hostname = await _torService.getOnionHostname();
print("Hosting at: http://$hostname");
```

#### 3. Make Requests (Outgoing Traffic)

**CRITICAL:** The outbound proxy (Port 9080) is an HTTP Tunnel. It requires the `CONNECT` method. Dart's `HttpClient` only sends `CONNECT` when the URL scheme is **https://**.

To make requests to other onion sites, you must:

* Use `https://` (even if the remote site is HTTP).
* Trust the self-signed certificate (since Tor handles the encryption, SSL validation fails locally).

**Dart**

```dart
// 1. Get the pre-configured Tor Client
HttpClient client = _torService.getTorHttpClient();

// 2. Define target (Must use HTTPS to trigger CONNECT tunnel)
// Tor will unwrap the HTTPS and deliver to the hidden service.
String target = "https://facebookwkhpilnemxj7asaniu7vnjjbiltxjqhye3mhbshg7kx5tfyd.onion";

try {
  var request = await client.getUrl(Uri.parse(target));
  var response = await request.close();
  var body = await response.transform(utf8.decoder).join();
  print("Response: $body");
} catch (e) {
  print("Request failed: $e");
}
```

---

### Architecture & Ports

This plugin manages specific port mappings to enable P2P functionality.

| Type           | Port      | Description                                                                     |
| -------------- | --------- | ------------------------------------------------------------------------------- |
| SOCKS5         | 9050      | Standard Tor SOCKS proxy.                                                       |
| HTTP Tunnel    | 9080      | Outbound. Use this for Flutter HttpClient. Requires https://.                   |
| Hidden Service | 80 → 8080 | Inbound. Traffic sent to your .onion on port 80 is forwarded to localhost:8080. |

---

### Troubleshooting

* **502 Bad Gateway / Connection Closed:**
  You sent a plain `http://` request to the proxy. Change your URL to `https://` to force Dart to use the required CONNECT method.

* **HandshakeException:**
  You're using `https://` but haven't configured the client to trust the certificate.
  Use:

  ```dart
  client.badCertificateCallback = (cert, host, port) => true;
  ```

---

### Disclaimer

This plugin is intended for educational and research purposes. While Tor enhances privacy, your application logic may still expose identifying information. Understand Tor’s limitations before relying on it in sensitive contexts.
