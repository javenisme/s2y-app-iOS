#!/usr/bin/env python3
#
# This source file is part of the S2Y application project
#
# SPDX-FileCopyrightText: 2026 S2Y Health
#
# SPDX-License-Identifier: MIT

"""Validate the reviewed iOS privacy manifest without platform-specific tools."""

from __future__ import annotations

import plistlib
import sys
from pathlib import Path
from typing import Any


EXPECTED_DATA_TYPES = sorted(
    [
        "NSPrivacyCollectedDataTypeEmailAddress",
        "NSPrivacyCollectedDataTypeHealth",
        "NSPrivacyCollectedDataTypeName",
        "NSPrivacyCollectedDataTypeOtherUserContent",
        "NSPrivacyCollectedDataTypeUserID",
    ]
)

EXPECTED_API_REASONS = {
    "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
    "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"],
}


class PrivacyManifestError(ValueError):
    """Raised when the privacy manifest does not match the reviewed declaration."""


def _require_list(value: Any, field: str) -> list[Any]:
    if not isinstance(value, list):
        raise PrivacyManifestError(f"{field} must be an array.")
    return value


def validate_manifest(manifest_path: Path) -> None:
    """Validate the manifest or raise a redacted, actionable error."""

    try:
        with manifest_path.open("rb") as manifest_file:
            manifest = plistlib.load(manifest_file)
    except (OSError, plistlib.InvalidFileException) as error:
        raise PrivacyManifestError("Privacy manifest is missing or invalid.") from error

    if not isinstance(manifest, dict):
        raise PrivacyManifestError("Privacy manifest root must be a dictionary.")
    if manifest.get("NSPrivacyTracking") is not False:
        raise PrivacyManifestError("Privacy tracking must remain disabled.")
    if manifest.get("NSPrivacyTrackingDomains") != []:
        raise PrivacyManifestError("Privacy tracking domains must remain empty.")

    collected_data = _require_list(
        manifest.get("NSPrivacyCollectedDataTypes"),
        "NSPrivacyCollectedDataTypes",
    )
    if not all(isinstance(item, dict) for item in collected_data):
        raise PrivacyManifestError("Collected data declarations must be dictionaries.")
    data_types = [item.get("NSPrivacyCollectedDataType") for item in collected_data]
    if not all(isinstance(data_type, str) for data_type in data_types):
        raise PrivacyManifestError("Collected data types must be strings.")
    data_types.sort()
    if data_types != EXPECTED_DATA_TYPES:
        raise PrivacyManifestError("Collected data declarations do not match review.")
    if not all(
        item.get("NSPrivacyCollectedDataTypeTracking") is False
        and item.get("NSPrivacyCollectedDataTypeLinked") is True
        for item in collected_data
    ):
        raise PrivacyManifestError("Collected data linkage declarations do not match review.")

    accessed_apis = _require_list(
        manifest.get("NSPrivacyAccessedAPITypes"),
        "NSPrivacyAccessedAPITypes",
    )
    if not all(isinstance(item, dict) for item in accessed_apis):
        raise PrivacyManifestError("Accessed API declarations must be dictionaries.")
    api_types = [item.get("NSPrivacyAccessedAPIType") for item in accessed_apis]
    if not all(isinstance(api_type, str) for api_type in api_types):
        raise PrivacyManifestError("Accessed API types must be strings.")
    api_reasons = {
        api_type: item.get("NSPrivacyAccessedAPITypeReasons")
        for api_type, item in zip(api_types, accessed_apis)
    }
    for api_type, expected_reasons in EXPECTED_API_REASONS.items():
        if api_reasons.get(api_type) != expected_reasons:
            raise PrivacyManifestError(
                "Required-reason API declarations do not match review."
            )


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("Usage: validate_privacy_manifest.py <PrivacyInfo.xcprivacy>", file=sys.stderr)
        return 2

    try:
        validate_manifest(Path(argv[1]))
    except PrivacyManifestError as error:
        print(f"Privacy manifest validation failed: {error}", file=sys.stderr)
        return 1

    print("Privacy manifest: validated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
