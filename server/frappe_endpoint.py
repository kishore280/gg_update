# Paste this into your Frappe custom app:
# e.g., gg_multisite_sync/api/app_update.py
#
# Then create a Single DocType called "App Update Config" with fields:
#   - android_latest_version (Data) e.g., "2.1.0"
#   - android_min_version (Data) e.g., "1.8.0"
#   - android_download_url (Data) e.g., "https://cdn.gg.com/pos-2.1.0.apk"
#   - android_file_size (Int) e.g., 45678901
#   - android_sha256 (Data) e.g., "a1b2c3..." (SHA256 hash of the APK)
#   - changelog (Small Text)
#   - force_update_message (Small Text)
#   - soft_update_message (Small Text)
#   - maintenance_mode (Check)
#   - maintenance_message (Small Text)

import frappe

@frappe.whitelist(allow_guest=True, methods=["GET"])
def check_update(platform="android", version="0.0.0"):
    """
    GET /api/method/gg_multisite_sync.api.app_update.check_update
        ?platform=android&version=1.2.0

    Returns JSON that gg_updater Flutter package expects.
    """
    config = frappe.get_single("App Update Config")

    # Maintenance mode — blocks everything
    if config.maintenance_mode:
        return {
            "status": "maintenance",
            "maintenance_message": config.maintenance_message or "App is under maintenance. Please try again later.",
        }

    client_v = _parse_version(version)
    min_v = _parse_version(config.android_min_version or "0.0.0")
    latest_v = _parse_version(config.android_latest_version or "0.0.0")

    # Force update — below minimum version
    if client_v < min_v:
        return {
            "status": "hard",
            "latest_version": config.android_latest_version,
            "min_version": config.android_min_version,
            "download_url": config.android_download_url,
            "file_size": config.android_file_size,
            "sha256": config.android_sha256,
            "changelog": config.changelog,
            "message": config.force_update_message or "Please update to continue.",
        }

    # Soft update — newer version available
    if client_v < latest_v:
        return {
            "status": "soft",
            "latest_version": config.android_latest_version,
            "download_url": config.android_download_url,
            "file_size": config.android_file_size,
            "sha256": config.android_sha256,
            "changelog": config.changelog,
            "message": config.soft_update_message,
        }

    # Up to date
    return {"status": "none"}


def _parse_version(v):
    """Parse '1.2.3' into a tuple (1, 2, 3) for comparison."""
    try:
        parts = v.replace("v", "").split(".")
        return tuple(int(p) for p in parts)
    except Exception:
        return (0, 0, 0)
