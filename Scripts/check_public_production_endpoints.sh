#!/bin/bash
#
# This source file is part of the S2Y application project
#
# SPDX-FileCopyrightText: 2026 S2Y Health
#
# SPDX-License-Identifier: MIT

set -euo pipefail

status_code() {
    curl --silent --show-error \
        --retry 2 --retry-all-errors --connect-timeout 10 --max-time 30 \
        --output /dev/null --write-out '%{http_code}' "$1"
}

login_status="$(status_code 'https://www.s2y.us/auth/login')"
omer_unauthenticated_status="$(status_code 'https://chat.s2y.us/api/mobile/v1/chats')"

if [[ "${login_status}" != "200" ]]; then
    echo "Production smoke check failed: login page returned ${login_status}." >&2
    exit 1
fi

if [[ "${omer_unauthenticated_status}" != "401" ]]; then
    echo "Production smoke check failed: Omer mobile API did not enforce authentication." >&2
    exit 1
fi

echo "Public production endpoints passed the unauthenticated smoke check."
echo "Login page: reachable"
echo "Omer mobile API: authentication required"
