package com.gg.updater

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.lang.ref.WeakReference

class GgUpdaterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

    private lateinit var channel: MethodChannel
    private var activityRef: WeakReference<Activity>? = null
    private var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.gg.updater")
        channel.setMethodCallHandler(this)
        InstallResultBroadcast.register(binding.binaryMessenger)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        InstallResultBroadcast.unregister()
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityRef = WeakReference(binding.activity)
    }

    override fun onDetachedFromActivity() {
        activityRef = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityRef = WeakReference(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityRef = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "installApk" -> {
                val filePath = call.argument<String>("filePath")
                if (filePath == null) {
                    result.error("ARG_ERROR", "filePath is required", null)
                    return
                }
                try {
                    installApk(filePath)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("INSTALL_ERROR", e.message, null)
                }
            }

            "canInstallApks" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    result.success(context?.packageManager?.canRequestPackageInstalls() ?: false)
                } else {
                    result.success(true)
                }
            }

            "openInstallPermissionSettings" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:${context?.packageName}")
                    )
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context?.startActivity(intent)
                }
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    private fun installApk(filePath: String) {
        val ctx = activityRef?.get() ?: context ?: throw Exception("No context available")
        val file = File(filePath)
        if (!file.exists()) throw Exception("APK file not found: $filePath")

        // Try PackageInstaller session API first (recommended for API 21+)
        try {
            installViaPackageInstaller(ctx, file)
            return
        } catch (e: Exception) {
            Log.w(TAG, "PackageInstaller failed, falling back to intent", e)
        }

        installViaIntent(ctx, file)
    }

    /**
     * Modern installation via PackageInstaller session API.
     * Writes the APK in chunks, provides install result via PendingIntent callback.
     */
    private fun installViaPackageInstaller(ctx: Context, file: File) {
        val installer = ctx.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL
        )
        params.setSize(file.length())

        val sessionId = installer.createSession(params)
        val session = installer.openSession(sessionId)

        try {
            // Write APK to session in 64KB chunks
            session.openWrite("update.apk", 0, file.length()).use { outputStream ->
                FileInputStream(file).use { inputStream ->
                    val buffer = ByteArray(65536)
                    var bytesRead: Int
                    while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                        outputStream.write(buffer, 0, bytesRead)
                    }
                    session.fsync(outputStream)
                }
            }

            // Create a PendingIntent for the install result callback
            val intent = Intent(INSTALL_ACTION).apply {
                setPackage(ctx.packageName)
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pendingIntent = PendingIntent.getBroadcast(ctx, sessionId, intent, flags)

            session.commit(pendingIntent.intentSender)
        } catch (e: Exception) {
            session.abandon()
            throw e
        }
    }

    /**
     * Legacy installation via ACTION_VIEW intent.
     * Fallback for devices where PackageInstaller fails.
     */
    private fun installViaIntent(ctx: Context, file: File) {
        val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            androidx.core.content.FileProvider.getUriForFile(
                ctx, "${ctx.packageName}.gg_updater.provider", file
            )
        } else {
            Uri.fromFile(file)
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        // Don't use resolveActivity — returns null on Android 11+ due to package visibility
        ctx.startActivity(intent)
    }

    companion object {
        private const val TAG = "GgUpdaterPlugin"
        private const val INSTALL_ACTION = "com.gg.updater.INSTALL_RESULT"
    }
}
