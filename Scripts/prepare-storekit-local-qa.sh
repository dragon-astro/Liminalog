#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

strict_clean=false
storekit_path="${LIMINALOG_STOREKIT_CONFIG:-liminalog.storekit}"
swift_module_cache_path="${LIMINALOG_SWIFT_MODULE_CACHE_PATH:-/private/tmp/liminalog-swift-module-cache}"

for argument in "$@"; do
  case "$argument" in
    --strict-clean)
      strict_clean=true
      ;;
    --storekit=*)
      storekit_path="${argument#--storekit=}"
      ;;
    --help|-h)
      cat <<'USAGE'
usage:
  Scripts/prepare-storekit-local-qa.sh [--strict-clean] [--storekit=path/to/liminalog.storekit]

Runs the local checks that should pass before Xcode normal Run StoreKit QA.
Use --strict-clean to fail when the working tree has uncommitted changes.
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

echo "Local StoreKit QA preflight"
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

run_step "Validate Release purchase gate state: closed" \
  run_swift_validator --validate-release-gate-state closed

run_step "Check whitespace in git diffs" \
  git diff --check

cat <<REPORT

Local StoreKit QA preflight completed.

Copy into AppStore/StoreKitLocalTesting.md after Xcode normal Run succeeds:

| Git SHA | $git_sha$(if [[ -n "$git_status" ]]; then printf ' + dirty'; fi) |
| Build | DEBUG |
| Device / OS | fill manually |
| Run Path | Xcode normal Run |
| Xcode | $xcode_version |
| StoreKit Configuration | \`$storekit_path\` |
| StoreKit Config Validation | pass |
| DEBUG Product Diagnostics | fill manually after confirming requested 8 / loaded 8 / valid 8 |
| Tester | fill manually |
| Date | $date_value |

Next:
1. Open Liminalog.xcodeproj in Xcode.
2. Confirm Run > Options > StoreKit Configuration is $storekit_path.
3. Run the app from Xcode, then open Settings > Proと応援.
4. Confirm DEBUG StoreKit商品取得診断 shows requested 8, loaded 8, valid 8.
REPORT
