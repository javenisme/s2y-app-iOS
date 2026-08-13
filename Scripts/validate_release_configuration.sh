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
PRIVACY_MANIFEST="${REPOSITORY_ROOT}/S2Y/Supporting Files/PrivacyInfo.xcprivacy"

fail() {
    echo "Release configuration invalid: $1" >&2
    exit 1
}

plist_value() {
    ruby -r rexml/document -e '
        document = REXML::Document.new(File.read(ARGV[0]))
        elements = document.elements["plist/dict"].elements.to_a
        index = elements.index { |element| element.name == "key" && element.text == ARGV[1] }
        abort("missing plist key") unless index && elements[index + 1]
        puts(elements[index + 1].text)
    ' "$1" "$2"
}

project_bundle_id="$({
    sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER = \([^;]*\);/\1/p' \
        "${REPOSITORY_ROOT}/S2Y.xcodeproj/project.pbxproj"
} | head -n 1 | tr -d '"')"
fastlane_bundle_id="$(
    sed -n 's/.*default_app_identifier: "\([^"]*\)".*/\1/p' \
        "${REPOSITORY_ROOT}/fastlane/Fastfile"
)"
firebase_bundle_id="$(plist_value \
    "${REPOSITORY_ROOT}/S2Y/Supporting Files/GoogleService-Info.plist" BUNDLE_ID)"
firebase_project_id="$(plist_value \
    "${REPOSITORY_ROOT}/S2Y/Supporting Files/GoogleService-Info.plist" PROJECT_ID)"
firebase_deploy_project="$(
    sed -n 's/.*"default": "\([^"]*\)".*/\1/p' \
        "${REPOSITORY_ROOT}/firebase/.firebaserc"
)"
plist_omer_url="$(plist_value \
    "${REPOSITORY_ROOT}/S2Y/Supporting Files/Info.plist" OmerChat.BaseURL)"
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

if ! plutil -lint "${PRIVACY_MANIFEST}" >/dev/null; then
    fail "application privacy manifest is missing or invalid."
fi

if ! plutil -convert json -o - "${PRIVACY_MANIFEST}" | ruby -r json -e '
    manifest = JSON.parse(STDIN.read)
    abort unless manifest["NSPrivacyTracking"] == false
    abort unless manifest["NSPrivacyTrackingDomains"] == []

    expected_data = %w[
      NSPrivacyCollectedDataTypeEmailAddress
      NSPrivacyCollectedDataTypeHealth
      NSPrivacyCollectedDataTypeName
      NSPrivacyCollectedDataTypeOtherUserContent
      NSPrivacyCollectedDataTypeUserID
    ].sort
    collected = manifest.fetch("NSPrivacyCollectedDataTypes")
    abort unless collected.map { |item| item["NSPrivacyCollectedDataType"] }.sort == expected_data
    abort unless collected.all? { |item| item["NSPrivacyCollectedDataTypeTracking"] == false }
    abort unless collected.all? { |item| item["NSPrivacyCollectedDataTypeLinked"] == true }

    reasons = manifest.fetch("NSPrivacyAccessedAPITypes").to_h do |item|
      [item["NSPrivacyAccessedAPIType"], item["NSPrivacyAccessedAPITypeReasons"]]
    end
    abort unless reasons["NSPrivacyAccessedAPICategoryUserDefaults"] == ["CA92.1"]
    abort unless reasons["NSPrivacyAccessedAPICategorySystemBootTime"] == ["35F9.1"]
'; then
    fail "application privacy manifest does not match the reviewed data and API declarations."
fi

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
echo "Privacy manifest: validated"
