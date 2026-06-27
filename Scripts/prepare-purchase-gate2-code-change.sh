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
  Scripts/prepare-purchase-gate2-code-change.sh [--strict-clean] [--allow-incomplete]

Runs checks that should pass immediately before changing PurchaseConfiguration.current to Gate 2.
Use --allow-incomplete only to validate the script before Gate 1 and StoreKit QA evidence are complete.
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

echo "Purchase Gate 2 code-change preflight"
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
  echo "note: skipping complete App Store Connect confirmation and Local StoreKit QA evidence checks because --allow-incomplete was passed."
else
  run_step "Validate App Store Connect confirmation is complete" \
    run_swift_validator --validate-app-store-connect-confirmation-complete

  run_step "Validate Local StoreKit QA evidence is complete" \
    run_swift_validator --validate-storekit-local-qa-complete
fi

if [[ "$allow_incomplete" == true ]]; then
  echo "note: skipping Gate 1 code-state check because --allow-incomplete was passed."
else
  run_step "Validate current Release gate is Gate 1" \
    run_swift_validator --validate-release-gate-state gate1
fi

run_step "Check whitespace in git diffs" \
  git diff --check

cat <<'REPORT'

Gate 2 code-change preflight completed.

Apply only this PurchaseConfiguration.current change for Gate 2:

  purchaseEntryPointIsEnabled: true
  featureRestrictionsAreEnabled: false
  backgroundEntitlementRefreshIsEnabled: true

Do not enable feature restrictions in Gate 2.

After editing and completing Purchase UI QA:

  Scripts/validate-purchase-readiness.sh --gate2-ready

Gate 2 exposes the purchase entry point, but existing free features must remain unlocked.
REPORT
