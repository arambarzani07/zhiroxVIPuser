from __future__ import annotations

import self_update


def find_next_release(current_version: str, session=self_update.requests) -> dict | None:
    """Return the oldest required newer release, not merely the newest one.

    Sequential upgrades keep long-offline gateways compatible with future update
    protocol migrations. A bridge release can teach an old gateway a new update
    protocol before a later release starts requiring it.
    """
    current = self_update.version_key(current_version)
    candidates: list[tuple[tuple[int, int, int, int], dict]] = []
    baseline_seen = False

    for page in range(1, self_update.MAX_RELEASE_PAGES + 1):
        url = (
            f"{self_update.RELEASES_URL}?per_page={self_update.RELEASE_PAGE_SIZE}"
            f"&page={page}"
        )
        response = self_update._get_with_retry(
            session,
            url,
            headers=self_update._HEADERS,
            timeout=(8, 20),
        )
        payload = response.json()
        if not isinstance(payload, list):
            raise RuntimeError("update_release_list_invalid")

        for release in payload:
            if not isinstance(release, dict):
                continue
            version = self_update._release_version(release)
            if not version:
                continue
            try:
                parsed = self_update.version_key(version)
            except ValueError:
                continue

            if parsed <= current:
                baseline_seen = True
                continue
            if release.get("draft") or release.get("prerelease"):
                continue
            if not self_update._release_has_asset(release, self_update.MANIFEST_ASSET):
                continue

            item = dict(release)
            item["_gateway_version"] = version
            candidates.append((parsed, item))

        # Keep scanning until we cross the installed version. This is different
        # from newest-only selection and is what makes bridge releases reliable
        # for machines that have been offline through several versions.
        if baseline_seen or len(payload) < self_update.RELEASE_PAGE_SIZE:
            break

    if not candidates:
        return None
    candidates.sort(key=lambda item: item[0])
    return candidates[0][1]


def maybe_auto_update(*args, **kwargs) -> bool:
    """Run the hardened updater with sequential release selection."""
    original = self_update.find_newer_release
    self_update.find_newer_release = find_next_release
    try:
        return self_update.maybe_auto_update(*args, **kwargs)
    finally:
        self_update.find_newer_release = original
