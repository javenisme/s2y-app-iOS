#
# This source file is part of the S2Y application project
#
# SPDX-FileCopyrightText: 2026 S2Y Health
#
# SPDX-License-Identifier: MIT

from __future__ import annotations

import copy
import plistlib
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS_DIRECTORY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS_DIRECTORY))

from validate_privacy_manifest import PrivacyManifestError, validate_manifest  # noqa: E402


class PrivacyManifestValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repository_root = Path(__file__).resolve().parents[2]
        cls.reviewed_manifest_path = (
            cls.repository_root
            / "S2Y"
            / "Supporting Files"
            / "PrivacyInfo.xcprivacy"
        )
        with cls.reviewed_manifest_path.open("rb") as manifest_file:
            cls.reviewed_manifest = plistlib.load(manifest_file)

    def assert_manifest_rejected(self, manifest: dict) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            manifest_path = Path(temporary_directory) / "PrivacyInfo.xcprivacy"
            with manifest_path.open("wb") as manifest_file:
                plistlib.dump(manifest, manifest_file)
            with self.assertRaises(PrivacyManifestError):
                validate_manifest(manifest_path)

    def test_accepts_reviewed_manifest(self) -> None:
        validate_manifest(self.reviewed_manifest_path)

    def test_rejects_tracking(self) -> None:
        manifest = copy.deepcopy(self.reviewed_manifest)
        manifest["NSPrivacyTracking"] = True
        self.assert_manifest_rejected(manifest)

    def test_rejects_unreviewed_data_type(self) -> None:
        manifest = copy.deepcopy(self.reviewed_manifest)
        manifest["NSPrivacyCollectedDataTypes"][0][
            "NSPrivacyCollectedDataType"
        ] = "NSPrivacyCollectedDataTypeLocation"
        self.assert_manifest_rejected(manifest)

    def test_rejects_missing_data_type(self) -> None:
        manifest = copy.deepcopy(self.reviewed_manifest)
        del manifest["NSPrivacyCollectedDataTypes"][0][
            "NSPrivacyCollectedDataType"
        ]
        self.assert_manifest_rejected(manifest)

    def test_rejects_incorrect_required_reason(self) -> None:
        manifest = copy.deepcopy(self.reviewed_manifest)
        manifest["NSPrivacyAccessedAPITypes"][0][
            "NSPrivacyAccessedAPITypeReasons"
        ] = ["invalid"]
        self.assert_manifest_rejected(manifest)

    def test_rejects_missing_accessed_api_type(self) -> None:
        manifest = copy.deepcopy(self.reviewed_manifest)
        del manifest["NSPrivacyAccessedAPITypes"][0][
            "NSPrivacyAccessedAPIType"
        ]
        self.assert_manifest_rejected(manifest)

    def test_rejects_malformed_plist(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            manifest_path = Path(temporary_directory) / "PrivacyInfo.xcprivacy"
            manifest_path.write_bytes(b"not a plist")
            with self.assertRaises(PrivacyManifestError):
                validate_manifest(manifest_path)


if __name__ == "__main__":
    unittest.main()
