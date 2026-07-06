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
  Scripts/prepare-purchase-gate1-code-change.sh [--strict-clean] [--allow-incomplete]

Runs checks that should pass immediately before changing PurchaseConfiguration.current to Gate 1.
Use --allow-incomplete only to validate the script before App Store Connect confirmation is filled.
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

echo "Purchase Gate 1 code-change preflight"
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

run_step "Validate App Store Connect product setup preflight" \
  Scripts/prepare-app-store-connect-products.sh --allow-other-branch

if [[ "$allow_incomplete" == true ]]; then
  echo
  echo "note: skipping complete confirmation check because --allow-incomplete was passed."
else
  run_step "Validate App Store Connect confirmation is complete" \
    run_swift_validator --validate-app-store-connect-confirmation-complete
fi

run_step "Validate current Release gate is still closed" \
  run_swift_validator --validate-release-gate-state closed

run_step "Check whitespace in git diffs" \
  git diff --check

cat <<'REPORT'

Gate 1 code-change preflight completed.

Generate the exact PurchaseConfiguration.current snippet:

  swift Scripts/validate-storekit-config.swift --purchase-configuration-snippet gate1

Apply only this PurchaseConfiguration.current change for Gate 1:

  productIDsAreConfirmedForAppStoreConnect: true
  subscriptionGroupName: "Liminalog Pro"
  purchaseEntryPointIsEnabled: false
  featureRestrictionsAreEnabled: false
  backgroundEntitlementRefreshIsEnabled: false

Keep the legal URLs as:

  termsOfUseURL: https://liminalog-lp.vercel.app/terms
  privacyPolicyURL: https://liminalog-lp.vercel.app/privacy

After editing:

  Scripts/validate-purchase-readiness.sh --gate1-ready

Gate 1 must not expose the purchase entry point or lock existing features.
REPORT
