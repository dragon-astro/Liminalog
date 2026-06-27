#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

allow_incomplete=false
strict_clean=false
storekit_path="${LIMINALOG_STOREKIT_CONFIG:-liminalog.storekit}"
swift_module_cache_path="${LIMINALOG_SWIFT_MODULE_CACHE_PATH:-/private/tmp/liminalog-swift-module-cache}"

for argument in "$@"; do
  case "$argument" in
    --allow-incomplete)
      allow_incomplete=true
      ;;
    --strict-clean)
      strict_clean=true
      ;;
    --storekit=*)
      storekit_path="${argument#--storekit=}"
      ;;
    --help|-h)
      cat <<'USAGE'
usage:
  Scripts/prepare-purchase-ui-qa.sh [--strict-clean] [--allow-incomplete] [--storekit=path/to/liminalog.storekit]

Runs checks that should pass before Gate 2 Purchase UI / real-device QA.
Use --allow-incomplete only to validate the script before Gate 2 code state and QA evidence are ready.
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
xcode_version="$(xcodebuild -version 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
if [[ -z "$xcode_version" ]]; then
  xcode_version="fill manually"
fi

echo "Purchase UI QA preflight"
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
echo "StoreKit Configuration: $storekit_path"
echo "Date: $date_value"

run_step "Validate purchase product document" \
  run_swift_validator --validate-products-doc

run_step "Validate premium decoration product document" \
  run_swift_validator --validate-premium-decoration-products-doc

run_step "Validate StoreKit configuration: $storekit_path" \
  run_swift_validator "$storekit_path"

run_step "Validate Xcode scheme StoreKit link" \
  run_swift_validator --validate-xcode-scheme-storekit

run_step "Validate premium decoration products are inactive" \
  run_swift_validator --validate-premium-decoration-inactive "$storekit_path"

run_step "Validate legal URLs" \
  Scripts/validate-purchase-legal-urls.sh

if [[ "$allow_incomplete" == true ]]; then
  echo
  echo "note: skipping complete App Store Connect, Local StoreKit QA, and Gate 2 code-state checks because --allow-incomplete was passed."
else
  run_step "Validate App Store Connect confirmation is complete" \
    run_swift_validator --validate-app-store-connect-confirmation-complete

  run_step "Validate Local StoreKit QA evidence is complete" \
    run_swift_validator --validate-storekit-local-qa-complete

  run_step "Validate current Release gate is Gate 2" \
    run_swift_validator --validate-release-gate-state gate2
fi

run_step "Check whitespace in git diffs" \
  git diff --check

cat <<REPORT

Purchase UI QA preflight completed.

Copy into AppStore/PurchaseUIQA.md after Gate 2 Purchase UI QA succeeds:

| Git SHA | $git_sha$(if [[ -n "$git_status" ]]; then printf ' + dirty'; fi) |
| Build | Release |
| Device / OS | fill manually |
| StoreKit Source | local \`.storekit\` / Sandbox |
| Purchase Entry | visible |
| Feature Restrictions | off |
| Tester | fill manually |
| Date | $date_value |

Recommended evidence notes:
- Xcode: $xcode_version
- Product diagnostics: paste StoreKit商品取得診断 > 証跡 when using DEBUG/local StoreKit.
- Existing tab smoke: home, calendar month/day/week timelines, statistics, friends, profile, and settings.
- Real-device safety: note whether the device contains released user data and whether approval was given.

Next:
1. Confirm Gate 2 code state keeps featureRestrictionsAreEnabled false.
2. Run the app via Xcode normal Run or Sandbox so StoreKit products load.
3. Complete the Gate 2 Purchase UI QA Evidence Sheet.
4. Run swift Scripts/validate-storekit-config.swift --validate-purchase-ui-qa-complete.
5. Run Scripts/validate-purchase-readiness.sh --gate2-ready.
REPORT
