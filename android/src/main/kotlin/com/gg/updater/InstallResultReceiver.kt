package com.gg.updater

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.util.Log

/**
 * Receives install-status broadcasts from [PackageInstaller] sessions.
 *
 * Registered in AndroidManifest with `exported=false` so only our own
 * PendingIntent (from [GgUpdaterPlugin.installViaPackageInstaller]) can
 * trigger it.
 *
 * Three possible outcomes:
 *  1. [PackageInstaller.STATUS_PENDING_USER_ACTION] — system needs user
 *     confirmation; we launch the provided confirmation intent.
 *  2. [PackageInstaller.STATUS_SUCCESS] — install completed.
 *  3. Any other status — install failed; we log the error message.
 *
 * Results are forwarded to Flutter via [InstallResultBroadcast].
 */
class InstallResultReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE,
        )
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)

        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                // System requires user confirmation — launch the confirmation UI.
                @Suppress("DEPRECATION")
                val confirmIntent = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                if (confirmIntent != null) {
                    confirmIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(confirmIntent)
                } else {
                    Log.w(TAG, "STATUS_PENDING_USER_ACTION but no confirmation intent")
                }
            }

            PackageInstaller.STATUS_SUCCESS -> {
                Log.i(TAG, "Package installed successfully")
                InstallResultBroadcast.send(status = "success", message = null)
            }

            else -> {
                val statusName = statusCodeToName(status)
                Log.w(TAG, "Install failed [$statusName]: $message")
                InstallResultBroadcast.send(
                    status = "failure",
                    message = message ?: "Install failed ($statusName)",
                )
            }
        }
    }

    private fun statusCodeToName(code: Int): String = when (code) {
        PackageInstaller.STATUS_FAILURE -> "STATUS_FAILURE"
        PackageInstaller.STATUS_FAILURE_ABORTED -> "STATUS_FAILURE_ABORTED"
        PackageInstaller.STATUS_FAILURE_BLOCKED -> "STATUS_FAILURE_BLOCKED"
        PackageInstaller.STATUS_FAILURE_CONFLICT -> "STATUS_FAILURE_CONFLICT"
        PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> "STATUS_FAILURE_INCOMPATIBLE"
        PackageInstaller.STATUS_FAILURE_INVALID -> "STATUS_FAILURE_INVALID"
        PackageInstaller.STATUS_FAILURE_STORAGE -> "STATUS_FAILURE_STORAGE"
        else -> "UNKNOWN($code)"
    }

    companion object {
        private const val TAG = "GgUpdaterInstall"
    }
}
