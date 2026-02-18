"""License management for atlas-session-lifecycle Pro.

Handles local license activation, revocation, and cached validation.
Stripe API calls are only made when cache expires (every 24h).
"""

from __future__ import annotations

import json
import time
from pathlib import Path

LICENSE_DIR = Path.home() / ".atlas-session"
LICENSE_FILE = "license.json"
CACHE_FILE = ".license_cache"
CACHE_TTL = 86400  # 24 hours


def activate_license(customer_id: str) -> dict:
    """Activate a license by writing customer_id to license.json."""
    LICENSE_DIR.mkdir(parents=True, exist_ok=True)
    license_path = LICENSE_DIR / LICENSE_FILE

    data = {
        "customer_id": customer_id,
        "activated_at": time.time(),
    }
    license_path.write_text(json.dumps(data, indent=2))

    # Touch cache to mark as freshly validated
    cache_path = LICENSE_DIR / CACHE_FILE
    cache_path.touch()

    return {"status": "ok", "customer_id": customer_id}


def revoke_license() -> dict:
    """Remove local license and cache files."""
    license_path = LICENSE_DIR / LICENSE_FILE
    cache_path = LICENSE_DIR / CACHE_FILE

    license_path.unlink(missing_ok=True)
    cache_path.unlink(missing_ok=True)

    return {"status": "ok", "message": "License revoked."}


def is_license_valid() -> bool:
    """Check if a valid, non-expired license exists locally.

    Returns True only if both license.json exists AND the cache
    file is less than 24 hours old. When cache expires, the caller
    should re-validate via Stripe API and touch the cache.
    """
    license_path = LICENSE_DIR / LICENSE_FILE
    cache_path = LICENSE_DIR / CACHE_FILE

    if not license_path.exists():
        return False

    if not cache_path.exists():
        return False

    # Check cache age
    cache_age = time.time() - cache_path.stat().st_mtime
    if cache_age > CACHE_TTL:
        return False

    return True
