#!/bin/zsh

set -euo pipefail

repo_root=${0:A:h:h:h}
script_name=${0:t}
dry_run=0
reset_local_database=0
include_watch=0

usage() {
    print "Usage: $script_name [--dry-run] [--reset-local-database] [--include-watch]"
    print ""
    print "  --dry-run               Print every gate without executing it."
    print "  --reset-local-database  Rebuild the local Supabase test database before pgTAP."
    print "  --include-watch         Run the Watch suite when shared or Watch behavior changed."
}

while (( $# > 0 )); do
    case "$1" in
        --dry-run)
            dry_run=1
            ;;
        --reset-local-database)
            reset_local_database=1
            ;;
        --include-watch)
            include_watch=1
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            print -u2 "Unknown option: $1"
            usage >&2
            exit 2
            ;;
    esac
    shift
done

run_step() {
    local label=$1
    shift

    print "\n[$label]"
    print -n -- "+"
    printf " %q" "$@"
    print ""

    if (( dry_run == 0 )); then
        "$@"
    fi
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        print -u2 "Missing required command: $1"
        exit 127
    fi
}

cd "$repo_root"

if (( dry_run == 0 )); then
    require_command rtk
    require_command supabase
    require_command deno
    require_command xcodebuild
fi

if (( dry_run == 1 )); then
    evidence_root="/tmp/CoupleSpace-release-evidence-<timestamp>"
else
    evidence_root=$(mktemp -d /tmp/CoupleSpace-release-evidence.XXXXXX)
fi

if (( reset_local_database == 1 )); then
    run_step "Reset local Supabase test database" rtk supabase db reset --local
else
    print "\n[Local database reset]"
    print "Skipped. Use --reset-local-database for a TestFlight or release-candidate gate."
fi

run_step "Supabase pgTAP" rtk supabase test db
run_step "Supabase local schema lint" rtk supabase db lint --local
run_step "Push payload unit tests" deno test supabase/functions/send-w1-push/apns.test.ts
run_step "Storage GC worker unit tests" deno test supabase/functions/process-storage-gc/index.test.ts

run_step "Full iPhone scheme" \
    rtk xcodebuild test \
    -project CoupleSpace.xcodeproj \
    -scheme CoupleSpace \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" \
    -derivedDataPath "$evidence_root/DerivedData" \
    -resultBundlePath "$evidence_root/CoupleSpace.xcresult" \
    -parallel-testing-enabled NO

run_step "Auth SDK and local logout capability" \
    env COUPLESPACE_DERIVED_DATA_ROOT="$evidence_root/DerivedData" \
    "$repo_root/quality/scripts/verify-session-capability.sh"

if (( include_watch == 1 )); then
    run_step "Watch scheme" \
        rtk xcodebuild test \
        -project CoupleSpace.xcodeproj \
        -scheme "CoupleSpace Watch App Watch App" \
        -destination "platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=latest" \
        -derivedDataPath "$evidence_root/WatchDerivedData" \
        -resultBundlePath "$evidence_root/CoupleSpace-Watch.xcresult" \
        -parallel-testing-enabled NO
fi

run_step "Harness integrity" rtk ../../agent-harness/scripts/project-harness.sh check .
run_step "Diff hygiene" rtk git diff --check

if (( dry_run == 1 )); then
    print "\nDry run completed. No automated gate was executed."
else
    print "\nAll requested automated gates passed."
fi
print "Evidence directory: $evidence_root"
print "Record xcresult executions, failures, skips, commit and build in quality/release-record-template.md."
