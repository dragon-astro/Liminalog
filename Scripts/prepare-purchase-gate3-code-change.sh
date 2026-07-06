#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

allow_incomplete=false
strict_clean=false
swift_module_cache_path="${LIMINALOG_SWIFT_MODULE_CACHE_PATH:-/private/tmp/liminalog-swift-module-cache}"

for argument in "$@"; do
  case "$argument" in
    --allow-incomplete)
      allow_incomplete=true
      ;;
    --strict-clean)
      strict_clean=true
      ;;
    --help|-h)
      cat <<'USAGE'
usage:
  Scripts/prepare-purchase-gate3-code-change.sh [--strict-clean] [--allow-incomplete]

Runs checks that should pass immediately before finalizing PurchaseConfiguration.current as Gate 3.
Use --allow-incomplete only to validate the script before Gate 2 and Statistics Pro QA evidence are complete.
USAGE
      exit 0
      ;;
    *)
      echo "error: unknown argument: $argument" >&2
      exit 2
      ;;
  esac
done

run_step() {
  local title="$1"
  shift
  echo
  echo "==> $title"
  "$@"
}

run_swift_validator() {
  swift -module-cache-path "$swift_module_cache_path" Scripts/validate-storekit-config.swift "$@"
}

git_sha="$(git rev-parse --short HEAD)"
git_status="$(git status --short)"
date_value="$(date +%F)"

echo "Purchase Gate 3 code-change preflight"
echo
echo "Git SHA: $git_sha"
if [[ -n "$git_status" ]]; then
  echo "Working tree: dirty"
  echo "$git_status" | sed 's/^/  /'
  if [[ "$strict_clean" == true ]]; then
    echo "error: working tree is dirty. Commit, stash, or rerun without --strict-clean if this is intentional." >&2
    exit 1
  fi
else
  echo "Working tree: clean"
fi
echo "Date: $date_value"

if [[ "$allow_incomplete" == true ]]; then
  echo
  echo "note: skipping complete Gate 2 and Statistics Pro QA evidence checks because --allow-incomplete was passed."
else
  run_step "Validate App Store Connect confirmation is complete" \
    run_swift_validator --validate-app-store-connect-confirmation-complete

  run_step "Validate Local StoreKit QA evidence is complete" \
    run_swift_validator --validate-storekit-local-qa-complete

  run_step "Validate Purchase UI QA evidence is complete" \
    run_swift_validator --validate-purchase-ui-qa-complete

  run_step "Validate Statistics Pro QA evidence is complete" \
    run_swift_validator --validate-statistics-pro-qa-complete

  run_step "Validate current Release gate is Gate 2" \
    run_swift_validator --validate-release-gate-state gate2
fi

run_step "Check whitespace in git diffs" \
  git diff --check

cat <<'REPORT'

Gate 3 code-change preflight completed.

Generate the exact PurchaseConfiguration.current snippet:

  swift Scripts/validate-storekit-config.swift --purchase-configuration-snippet gate3

Apply only this PurchaseConfiguration.current change for Gate 3:

  featureRestrictionsAreEnabled: true

Keep these Gate 2 settings enabled:

  purchaseEntryPointIsEnabled: true
  backgroundEntitlementRefreshIsEnabled: true

After editing:

  Scripts/validate-purchase-readiness.sh --gate3-ready

Gate 3 is the first gate that can lock Pro features. Free users must still keep logging, calendar, daily card, friends, sharing, and past-data browsing.
REPORT
