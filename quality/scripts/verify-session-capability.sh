#!/bin/zsh

# Verifies the checked-in Supabase Swift SDK contract used by SESSION-001.
# This is a source/API probe only: it neither opens a network connection nor
# reads credentials, JWTs, refresh tokens, or project configuration.

set -euo pipefail

repo_root=${0:A:h:h:h}
resolved="$repo_root/CoupleSpace.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
derived_data_root=${COUPLESPACE_DERIVED_DATA_ROOT:-/Users/titus/Library/Developer/Xcode/DerivedData}

fail() {
    print -u2 "SESSION-001 FAIL: $1"
    exit 1
}

require_match() {
    local pattern=$1
    local path=$2
    /usr/bin/grep -Eq -- "$pattern" "$path" || fail "Expected '$pattern' in ${path#$repo_root/}"
}

cd "$repo_root"

[[ -f "$resolved" ]] || fail "Package.resolved is missing"
require_match '"identity" : "supabase-swift"' "$resolved"
require_match '"version" : "2\.54\.1"' "$resolved"

sdk_root=$(/usr/bin/find "$derived_data_root" -type d -path '*/SourcePackages/checkouts/supabase-swift' -print -quit 2>/dev/null || true)
[[ -n "$sdk_root" ]] || fail "No resolved supabase-swift checkout. Build the iPhone scheme once, then rerun."

auth_sources="$sdk_root/Sources/Auth"
[[ -d "$auth_sources" ]] || fail "Supabase Auth sources are missing from the resolved checkout"

require_match 'public enum SignOutScope' "$auth_sources/Types.swift"
require_match 'case global' "$auth_sources/Types.swift"
require_match 'case local' "$auth_sources/Types.swift"
require_match 'case others' "$auth_sources/Types.swift"
require_match 'public func signOut\(scope: SignOutScope = \.global\)' "$auth_sources/AuthClient.swift"
require_match 'case sessionId = "session_id"' "$auth_sources/Types.swift"
require_match 'UIApplication\.didBecomeActiveNotification' "$auth_sources/AuthClient.swift"
require_match 'UIApplication\.willResignActiveNotification' "$auth_sources/AuthClient.swift"
require_match 'public static let defaultAutoRefreshToken: Bool = true' "$auth_sources/Defaults.swift"

if /usr/bin/grep -REq 'func[[:space:]].*[Ll]ist.*[Ss]ession|func[[:space:]].*[Ss]ession.*[Ll]ist' "$auth_sources"; then
    fail "The SDK now exposes a session-list API; update the capability record before implementation."
fi

print "SESSION-001 PASS: supabase-swift 2.54.1 exposes current-session claims and global/local/others sign-out only; no session-list API was found."
