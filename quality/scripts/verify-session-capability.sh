#!/bin/zsh

# Verifies the checked-in v1 Auth session boundary. The product only supports
# current-device logout; the opt-in Debug diagnostic probe cannot revoke any
# session and is disabled by default. This check opens no network connection
# and reads no credentials.

set -euo pipefail

repo_root=${0:A:h:h:h}
resolved="$repo_root/CoupleSpace.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
scheme="$repo_root/CoupleSpace.xcodeproj/xcshareddata/xcschemes/CoupleSpace.xcscheme"
derived_data_root=${COUPLESPACE_DERIVED_DATA_ROOT:-/Users/titus/Library/Developer/Xcode/DerivedData}

fail() {
    print -u2 "SESSION capability preflight FAIL: $1"
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
require_match '"revision" : "b118484ae0eb4a6b6ce1b216711d660baf6ec1aa"' "$resolved"

sdk_root=$(/usr/bin/find "$derived_data_root" -type d -path '*/SourcePackages/checkouts/supabase-swift' -print -quit 2>/dev/null || true)
[[ -n "$sdk_root" ]] || fail "No resolved supabase-swift checkout. Build the iPhone scheme once, then rerun."
sdk_revision=$(/usr/bin/git -C "$sdk_root" rev-parse HEAD 2>/dev/null || true)
[[ "$sdk_revision" == "b118484ae0eb4a6b6ce1b216711d660baf6ec1aa" ]] \
    || fail "The discovered SDK checkout does not match Package.resolved. Set COUPLESPACE_DERIVED_DATA_ROOT to the build under test."

auth_sources="$sdk_root/Sources/Auth"
[[ -d "$auth_sources" ]] || fail "Supabase Auth sources are missing from the resolved checkout"
app_sign_out_service="$repo_root/CoupleSpace/Data/SupabaseAuthSessionSignOutService.swift"
[[ -f "$app_sign_out_service" ]] || fail "The app Auth session sign-out service is missing"

require_match 'public enum SignOutScope' "$auth_sources/Types.swift"
require_match 'case local' "$auth_sources/Types.swift"
require_match 'case sessionId = "session_id"' "$auth_sources/Types.swift"
require_match 'UIApplication\.didBecomeActiveNotification' "$auth_sources/AuthClient.swift"
require_match 'UIApplication\.willResignActiveNotification' "$auth_sources/AuthClient.swift"
require_match 'public static let defaultAutoRefreshToken: Bool = true' "$auth_sources/Defaults.swift"
[[ $(/usr/bin/grep -Ec 'signOut\(\.local\)' "$app_sign_out_service") -eq 2 ]] \
    || fail "Current-device logout must perform initial and post-refresh local cleanup."
if /usr/bin/grep -REq --include='*.swift' '\.(global|others)([^[:alnum:]_]|$)' "$repo_root/CoupleSpace"; then
    fail "Product sources must not expose global or all-other-session sign-out."
fi

[[ -f "$scheme" ]] || fail "The shared CoupleSpace scheme is missing"
require_match 'argument = "--session-capability-probe"' "$scheme"
probe_argument=$(/usr/bin/grep -A 1 'argument = "--session-capability-probe"' "$scheme")
[[ "$probe_argument" == *'isEnabled = "NO"'* ]] \
    || fail "The Debug session capability probe must be disabled in the shared scheme."

if /usr/bin/grep -REq 'func[[:space:]].*[Ll]ist.*[Ss]ession|func[[:space:]].*[Ss]ession.*[Ll]ist' "$auth_sources"; then
    fail "The SDK now exposes a session-list API; update the capability record before implementation."
fi

print "SESSION scope guard PASS: v1 exposes no session inventory or remote revoke; current-device logout uses stabilized local cleanup, and the non-revoking Debug diagnostic probe is disabled by default."
