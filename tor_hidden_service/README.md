# Tor Hidden Service — Flutter Plugin

A Flutter plugin that allows your mobile application to host Tor v3 Onion Services and route traffic through the Tor network. Your app can create its own .onion address, communicate through Tor’s encrypted pathways, and surface live bootstrap logs straight to your interface.

Features

• Android support using the Guardian Project’s Tor binaries

• Host v3 Onion Services directly from Flutter

• Built-in HTTP proxy on port 9080, compatible with Flutter’s HttpClient

• Real-time access to Tor bootstrap logs (5% → 50% → 100%)

# Installation

Add the dependency:

    dependencies:
        tor_hidden_service: ^0.0.1

# Android Setup

1. Permissions
   Add the following to android/app/src/main/AndroidManifest.xml:

    

    <uses-permission android:name="android.permission.INTERNET"/>



2. Guardian Project Binaries
   The Tor binary is not bundled with the plugin. It is downloaded during the build process from the Guardian Project Maven repository.

If your build reports missing Tor dependencies, ensure your Gradle configuration includes:

    maven { url "[https://raw.githubusercontent.com/guardianproject/gpmaven/master](https://raw.githubusercontent.com/guardianproject/gpmaven/master)" }

Most projects are automatically configured by the plugin, but some Gradle structures require this line explicitly.


# Usage

1. Starting the Hidden Service
   Tor must be running before you can retrieve the onion hostname or issue proxy requests. Bootstrap usually completes within 20–40 seconds.


    import 'package:tor_hidden_service/tor_hidden_service.dart';
    
    final _torService = TorHiddenService();
    
    _torService.onLog.listen((log) {
    print("TOR LOG: $log");
    });
    
    try {
    await _torService.start();
    print("Tor started successfully!");
    } catch (e) {
    print("Failed to start Tor: $e");
    }

2. Getting the Onion Hostname
   This returns the public .onion URL. Make sure a local server is active on a port such as 8080.


3. Using Tor as an HTTP Proxy
   You can route outbound requests, including requests to other .onion addresses, through the Tor network:

        HttpClient client = _torService.getTorHttpClient();
        
        try {
        var request = await client.getUrl(Uri.parse("[https://api.ipify.org](https://api.ipify.org)"));
        var response = await request.close();
        var body = await response.transform(utf8.decoder).join();
        
        print("My Tor IP is: $body");
        } catch (e) {
        print("Request failed: $e");
        }

4. Stopping Tor

    await _torService.stop();

# Architecture

This plugin uses Tor’s Android wrapper libraries.

Binaries

• libtor.so (fetched from Guardian Project Maven and unpacked at runtime when required)


Ports

• SOCKS5: 9050

• HTTP Tunnel: 9080

• Hidden Service: 80 (Tor) mapped to 8080 (local)


# Disclaimer

This plugin is intended for educational and research purposes. While Tor enhances privacy, your application may still expose identifying information depending on its design. Understand Tor’s limitations before relying on it in sensitive contexts.
