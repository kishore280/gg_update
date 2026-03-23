package com.gg.updater

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/**
 * Singleton bridge between [InstallResultReceiver] and Flutter.
 *
 * Exposes an [EventChannel] ("com.gg.updater/installStatus") that Dart
 * can listen to for install outcome events. Each event is a map:
 *
 *   { "status": "success" | "failure", "message": "..." }
 *
 * The receiver fires [send] from any thread; we marshal onto the main
 * looper before calling [EventChannel.EventSink.success].
 */
object InstallResultBroadcast : EventChannel.StreamHandler {

    private const val CHANNEL = "com.gg.updater/installStatus"

    private var eventSink: EventChannel.EventSink? = null
    private var channel: EventChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger) {
        channel = EventChannel(messenger, CHANNEL).also {
            it.setStreamHandler(this)
        }
    }

    fun unregister() {
        channel?.setStreamHandler(null)
        channel = null
        eventSink = null
    }

    /**
     * Called by [InstallResultReceiver] — safe to call from any thread.
     */
    fun send(status: String, message: String?) {
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "status" to status,
                    "message" to (message ?: ""),
                ),
            )
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
