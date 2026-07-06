#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

strict_clean=false
allow_other_branch=false
expected_branch="${LIMINALOG_PURCHASE_BRANCH:-codex/monetization-foundation}"
swift_module_cache_path="${LIMINALOG_SWIFT_MODULE_CACHE_PATH:-/private/tmp/liminalog-swift-module-cache}"

for argument in "$@"; do
  case "$argument" in
    --strict-clean)
      strict_clean=true
      ;;
    --allow-other-branch)
      allow_other_branch=true
      ;;
    --help|-h)
      cat <<'USAGE'
usage:
  Scripts/prepare-app-store-connect-products.sh [--strict-clean] [--allow-other-branch]

Runs the local checks that should pass before creating App Store Connect products.
Use --strict-clean to fail when the working tree has uncommitted changes.
By default, this expects the codex/monetization-foundation branch. Set LIMINALOG_PURCHASE_BRANCH or pass --allow-other-branch to override.
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
current_branch="$(git branch --show-current)"
git_status="$(git status --short)"
date_value="$(date +%F)"

echo "App Store Connect product setup preflight"
echo
echo "Git SHA: $git_sha"
echo "Branch: ${current_branch:-detached HEAD}"
if [[ "$allow_other_branch" != true && "$current_branch" != "$expected_branch" ]]; then
  echo "error: expected branch $expected_branch before creating App Store Connect products." >&2
  echo "       Current branch is ${current_branch:-detached HEAD}." >&2
  echo "       Set LIMINALOG_PURCHASE_BRANCH or pass --allow-other-branch if this is intentional." >&2
  exit 1
fi
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

run_step "Validate purchase product document" \
  run_swift_validator --validate-products-doc

run_step "Validate App Store Connect product setup sheet" \
  run_swift_validator --validate-products-doc AppStore/AppStoreConnectProductSetup.md

run_step "Validate App Store Connect confirmation template" \
  run_swift_validator --validate-app-store-connect-confirmation-template

run_step "Validate App Store Connect metadata entry sheet" \
  run_swift_validator --validate-app-store-connect-metadata-entry

run_step "Validate monetization policy document" \
  run_swift_validator --validate-monetization-doc

run_step "Validate App Review notes" \
  run_swift_validator --validate-review-notes

run_step "Validate Review Information screenshot assets" \
  run_swift_validator --validate-review-information-assets

run_step "Validate purchase product source" \
  run_swift_validator --validate-product-source

run_step "Validate premium decoration product document" \
  run_swift_validator --validate-premium-decoration-products-doc

run_step "Validate Release purchase gate state: closed" \
  run_swift_validator --validate-release-gate-state closed

run_step "Validate legal URLs" \
  Scripts/validate-purchase-legal-urls.sh

run_step "Check whitespace in git diffs" \
  git diff --check

cat <<REPORT

App Store Connect product setup preflight completed.

Transfer source:
- AppStore/AppStoreConnectProductSetup.md
- AppStore/AppStoreConnectProductRunbook.md
- AppStore/ReviewNotes.md

Generate TSV for App Store Connect:

  swift Scripts/validate-storekit-config.swift --app-store-connect-tsv

Generate Missing Metadata TSV for App Store Connect:

  swift Scripts/validate-storekit-config.swift --app-store-connect-metadata-tsv

Generate Missing Metadata Markdown handoff:

  swift Scripts/validate-storekit-config.swift --app-store-connect-missing-metadata-md

Generate the confirmation sheet template:

  swift Scripts/validate-storekit-config.swift --app-store-connect-confirmation-md

Next:
1. Create the Liminalog Pro subscription group.
2. Create the 8 current products from AppStore/AppStoreConnectProductSetup.md.
3. Set liminalog.pro.yearly Introductory Offer to Free Trial / 1 Week.
4. Fill AppStore/AppStoreConnectProductConfirmation.md, including Creation Metadata.
5. Run Scripts/validate-purchase-readiness.sh --gate1-ready before changing PurchaseConfiguration.current.
REPORT
