# Paste this into your Frappe custom app:
# e.g., your_app/api/app_update.py
#
# DocType: "App Release" (regular, NOT Single)
# Fields:
#   - version (Data, reqd) e.g., "2.1.0" — used as name/title
#   - min_version (Data) e.g., "1.8.0" — versions below this get force update
#   - download_url (Data, reqd) e.g., "https://cdn.example.com/app-2.1.0.apk"
#   - file_size (Int) e.g., 45678901
#   - sha256 (Data) e.g., "a1b2c3..." — preferred for integrity check
#   - sha1 (Data) e.g., "a1b2c3..." — or sha1_file (Attach) to read from uploaded file
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
from semver import Version


@frappe.whitelist(allow_guest=True, methods=["GET"])
def check_update(platform="android", version="0.0.0"):
    """
    GET /api/method/your_app.api.app_update.check_update
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
        "sha1": _resolve_sha1(release),
        "changelog": release.changelog,
        "message": release.update_message,
    }


def _resolve_sha1(release):
    """Return sha1: from sha1_file (Attach) if set, else sha1 (Data) field."""
    file_url = getattr(release, "sha1_file", None)
    if file_url:
        try:
            name = frappe.db.get_value("File", {"file_url": file_url}, "name")
            if name:
                content = frappe.get_doc("File", name).get_content()
                if isinstance(content, bytes):
                    content = content.decode("utf-8", errors="replace")
                if content:
                    return content.strip()
        except Exception:
            pass
    return getattr(release, "sha1", None)


def _parse_version(v):
    """Parse a semver string for comparison.

    Flutter/Dart use semver natively, so python-semver is the natural fit.
    Handles pre-release (1.0.0-beta < 1.0.0) and build metadata correctly.
    """
    try:
        return Version.parse(v.strip().lstrip("vV"))
    except ValueError:
        return Version(0, 0, 0)
