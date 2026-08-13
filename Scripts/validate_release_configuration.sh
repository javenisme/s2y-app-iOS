#!/bin/bash
#
# This source file is part of the S2Y application project
#
# SPDX-FileCopyrightText: 2026 S2Y Health
#
# SPDX-License-Identifier: MIT

set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"
EXPECTED_BUNDLE_ID="us.s2y.s2y-ios"
EXPECTED_FIREBASE_PROJECT="s2y-mobile-app"
EXPECTED_OMER_URL="https://chat.s2y.us"

fail() {
    echo "Release configuration invalid: $1" >&2
    exit 1
}

project_bundle_id="$({
    sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER = \([^;]*\);/\1/p' \
        "${REPOSITORY_ROOT}/S2Y.xcodeproj/project.pbxproj"
} | head -n 1 | tr -d '"')"
fastlane_bundle_id="$(
    sed -n 's/.*default_app_identifier: "\([^"]*\)".*/\1/p' \
        "${REPOSITORY_ROOT}/fastlane/Fastfile"
)"
firebase_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :BUNDLE_ID' \
    "${REPOSITORY_ROOT}/S2Y/Supporting Files/GoogleService-Info.plist")"
firebase_project_id="$(/usr/libexec/PlistBuddy -c 'Print :PROJECT_ID' \
    "${REPOSITORY_ROOT}/S2Y/Supporting Files/GoogleService-Info.plist")"
firebase_deploy_project="$(
    sed -n 's/.*"default": "\([^"]*\)".*/\1/p' \
        "${REPOSITORY_ROOT}/firebase/.firebaserc"
)"
plist_omer_url="$(/usr/libexec/PlistBuddy -c 'Print :OmerChat.BaseURL' \
    "${REPOSITORY_ROOT}/S2Y/Supporting Files/Info.plist")"
source_omer_url="$(
    sed -n 's/.*defaultBaseURL = "\([^"]*\)".*/\1/p' \
        "${REPOSITORY_ROOT}/S2Y/LLM/Omer/OmerChatService.swift"
)"

[[ "${project_bundle_id}" == "${EXPECTED_BUNDLE_ID}" ]] \
    || fail "Xcode application bundle ID does not match the approved identifier."
[[ "${fastlane_bundle_id}" == "${EXPECTED_BUNDLE_ID}" ]] \
    || fail "Fastlane bundle ID does not match the Xcode application target."
[[ "${firebase_bundle_id}" == "${EXPECTED_BUNDLE_ID}" ]] \
    || fail "Firebase iOS configuration belongs to a different bundle ID."
[[ "${firebase_project_id}" == "${EXPECTED_FIREBASE_PROJECT}" ]] \
    || fail "Firebase iOS configuration belongs to an unexpected project."
[[ "${firebase_deploy_project}" == "${EXPECTED_FIREBASE_PROJECT}" ]] \
    || fail "Firebase CLI default points to an unexpected project."
[[ "${plist_omer_url}" == "${EXPECTED_OMER_URL}" ]] \
    || fail "Info.plist Omer URL is not the approved production endpoint."
[[ "${source_omer_url}" == "${EXPECTED_OMER_URL}" ]] \
    || fail "Omer service fallback is not the approved production endpoint."

if grep -R -n -E --exclude-dir=BrandAssets \
    'chat-bak\.s2y\.us|StanfordRocks|setupTestAccount' \
    "${REPOSITORY_ROOT}/S2Y" \
    "${REPOSITORY_ROOT}/fastlane" \
    "${REPOSITORY_ROOT}/firebase" \
    "${REPOSITORY_ROOT}/.github" >/dev/null; then
    fail "retired endpoint or embedded test-account material remains in the repository."
fi

echo "Release configuration validated without printing credentials."
echo "Bundle: ${EXPECTED_BUNDLE_ID}"
echo "Firebase project: ${EXPECTED_FIREBASE_PROJECT}"
echo "Omer endpoint: ${EXPECTED_OMER_URL}"
