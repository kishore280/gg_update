# Paste this into your Frappe custom app:
# e.g., gg_multisite_sync/api/app_update.py
#
# DocType: "App Release" (regular, NOT Single)
# Fields:
#   - version (Data, reqd) e.g., "2.1.0" — used as name/title
#   - min_version (Data) e.g., "1.8.0" — versions below this get force update
#   - download_url (Data, reqd) e.g., "https://cdn.gg.com/pos-2.1.0.apk"
#   - file_size (Int) e.g., 45678901
#   - sha256 (Data) e.g., "a1b2c3..."
#   - changelog (Small Text)
#   - update_message (Small Text)
#   - force_update (Check) — mark this release as mandatory
#   - enabled (Check, default 1) — uncheck to hide a release
#
# Single DocType: "App Update Settings" (for global toggles)
# Fields:
#   - active_release (Link -> App Release) — pick which release to serve
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
    settings = frappe.get_single("App Update Settings")

    # Maintenance mode — blocks everything
    if settings.maintenance_mode:
        return {
            "status": "maintenance",
            "maintenance_message": settings.maintenance_message
            or "App is under maintenance. Please try again later.",
        }

    # Use the release picked in settings, fallback to latest enabled
    if settings.active_release:
        release = frappe.get_doc("App Release", settings.active_release)
    else:
        releases = frappe.get_all(
            "App Release",
            filters={"enabled": 1},
            fields=["name"],
            order_by="creation desc",
            limit=1,
        )
        if not releases:
            return {"status": "none"}
        release = frappe.get_doc("App Release", releases[0].name)

    if not release.enabled:
        return {"status": "none"}
    client_v = _parse_version(version)
    latest_v = _parse_version(release.version)

    # Already up to date
    if client_v >= latest_v:
        return {"status": "none"}

    # Force update — either release is marked force, or client is below min_version
    min_v = _parse_version(release.min_version or "0.0.0")
    is_force = release.force_update or client_v < min_v

    return {
        "status": "hard" if is_force else "soft",
        "latest_version": release.version,
        "min_version": release.min_version,
        "download_url": release.download_url,
        "file_size": release.file_size,
        "sha256": release.sha256,
        "changelog": release.changelog,
        "message": release.update_message,
    }


def _parse_version(v):
    """Parse '1.2.3' into a tuple (1, 2, 3) for comparison."""
    try:
        parts = v.replace("v", "").split(".")
        return tuple(int(p) for p in parts)
    except Exception:
        return (0, 0, 0)
