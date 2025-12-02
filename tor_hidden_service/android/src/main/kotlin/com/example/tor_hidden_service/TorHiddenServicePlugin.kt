package com.example.tor_hidden_service

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.FileOutputStream
import java.util.concurrent.Executors
import java.util.zip.ZipFile

class TorHiddenServicePlugin: FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var channel : MethodChannel
    private lateinit var eventChannel : EventChannel
    private lateinit var context : Context

    // Sink to send logs to Flutter
    private var eventSink: EventChannel.EventSink? = null

    private var torProcess: Process? = null
    private val executor = Executors.newSingleThreadExecutor()
    private val uiHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "tor_hidden_service")
        channel.setMethodCallHandler(this)

        // Setup the Event Channel for logging
        eventChannel = EventChannel(binding.binaryMessenger, "tor_hidden_service/logs")
        eventChannel.setStreamHandler(this)

        context = binding.applicationContext
    }

    // --- Event Channel Methods ---
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // --- Method Channel Methods ---
    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "startTor" -> executor.submit { startTor(result) }
            "stopTor" -> {
                torProcess?.destroy()
                result.success("Stopped")
            }
            "getHostname" -> getHostname(result)
            else -> result.notImplemented()
        }
    }

    private fun startTor(result: Result) {
        try {
            logToFlutter("Checking for Tor binary...")

            // Initial assumption: It's in the native library directory
            var torBinary = File(context.applicationInfo.nativeLibraryDir, "libtor.so")

            if (!torBinary.exists()) {
                logToFlutter("Binary not found in native libs. Attempting manual extraction...")

                val extracted = extractFileFromApk("libtor.so")
                if (extracted != null) {
                    torBinary = extracted
                } else {
                    uiThread(result) { error("BINARY_MISSING", "Could not locate or extract libtor.so", null) }
                    return
                }
            }

            // Double check it exists and is executable
            if (!torBinary.exists()) {
                 uiThread(result) { error("BINARY_MISSING", "Tor binary file does not exist", null) }
                 return
            }

            torBinary.setExecutable(true, true)

            // Setup Data Dirs
            val torDir = context.getDir("tor_data", Context.MODE_PRIVATE)
            val hsDir = File(torDir, "hs")
            if (!hsDir.exists()) hsDir.mkdirs()

            // Write Config
            val torrcFile = File(torDir, "torrc")
            torrcFile.writeText("""
                DataDirectory ${torDir.absolutePath}
                HiddenServiceDir ${hsDir.absolutePath}
                HiddenServicePort 80 127.0.0.1:8080
                SOCKSPort 9050
                HTTPTunnelPort 9080
                Log notice stdout
            """.trimIndent())

            logToFlutter("Starting Tor process...")

            val pb = ProcessBuilder(torBinary.absolutePath, "-f", torrcFile.absolutePath)
            pb.directory(torDir)
            val env = pb.environment()
            env["LD_LIBRARY_PATH"] = context.applicationInfo.nativeLibraryDir

            torProcess = pb.start()

            // Monitor Logs
            val reader = BufferedReader(InputStreamReader(torProcess!!.inputStream))
            var line: String?
            var bootstrapped = false

            val startTime = System.currentTimeMillis()

            // We loop specifically looking for bootstrap messages
            while (true) {
                if (reader.ready()) {
                    line = reader.readLine()
                    if (line == null) break

                    // Send every log line to Flutter
                    logToFlutter(line)

                    if (line.contains("Bootstrapped 100%")) {
                        bootstrapped = true
                        break
                    }
                }

                if (System.currentTimeMillis() - startTime > 60000) { // 60s timeout
                    logToFlutter("Error: Timeout waiting for bootstrap")
                    break
                }
                Thread.sleep(100)
            }

            if (bootstrapped) {
                uiThread(result) { success("Tor Started") }
            } else {
                uiThread(result) { error("TIMEOUT", "Tor did not bootstrap in time", null) }
            }

        } catch (e: Exception) {
            logToFlutter("Exception: ${e.message}")
            uiThread(result) { error("EXCEPTION", e.message, null) }
        }
    }

    private fun logToFlutter(message: String) {
        // Events must be sent on Main Thread
        uiHandler.post {
            eventSink?.success(message)
        }
    }

    private fun extractFileFromApk(filename: String): File? {
        try {
            val apkFile = File(context.applicationInfo.sourceDir)
            val zip = ZipFile(apkFile)
            val targetFile = File(context.cacheDir, filename)

            val abis = Build.SUPPORTED_ABIS
            var foundEntry: java.util.zip.ZipEntry? = null

            for (abi in abis) {
                val entryPath = "lib/$abi/$filename"
                val entry = zip.getEntry(entryPath)
                if (entry != null) {
                    foundEntry = entry
                    break
                }
            }

            if (foundEntry == null) return null

            zip.getInputStream(foundEntry).use { input ->
                FileOutputStream(targetFile).use { output ->
                    input.copyTo(output)
                }
            }
            return targetFile
        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
    }

    private fun getHostname(result: Result) {
        val torDir = context.getDir("tor_data", Context.MODE_PRIVATE)
        val hostnameFile = File(torDir, "hs/hostname")
        if (hostnameFile.exists()) {
            result.success(hostnameFile.readText().trim())
        } else {
            result.error("NOT_READY", "Hostname file not created yet", null)
        }
    }

    private fun uiThread(result: Result, block: Result.() -> Unit) {
        uiHandler.post { block(result) }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        torProcess?.destroy()
    }
}