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
  Scripts/prepare-statistics-pro-qa.sh [--strict-clean] [--allow-incomplete]

Runs checks that should pass before Gate 3 Statistics Pro QA.
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

echo "Statistics Pro QA preflight"
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

run_step "Validate purchase product document" \
  run_swift_validator --validate-products-doc

run_step "Validate monetization policy document" \
  run_swift_validator --validate-monetization-doc

run_step "Validate premium decoration product document" \
  run_swift_validator --validate-premium-decoration-products-doc

run_step "Validate premium decoration UI remains disconnected" \
  run_swift_validator --validate-premium-decoration-ui-disconnected

run_step "Validate legal URLs" \
  Scripts/validate-purchase-legal-urls.sh

if [[ "$allow_incomplete" == true ]]; then
  echo
  echo "note: skipping complete Gate 2 evidence and code-state checks because --allow-incomplete was passed."
else
  run_step "Validate App Store Connect confirmation is complete" \
    run_swift_validator --validate-app-store-connect-confirmation-complete

  run_step "Validate Local StoreKit QA evidence is complete" \
    run_swift_validator --validate-storekit-local-qa-complete

  run_step "Validate Purchase UI QA evidence is complete" \
    run_swift_validator --validate-purchase-ui-qa-complete

  run_step "Validate current Release gate is Gate 2" \
    run_swift_validator --validate-release-gate-state gate2
fi

run_step "Check whitespace in git diffs" \
  git diff --check

cat <<REPORT

Statistics Pro QA preflight completed.

Copy into Liminalog/Views/Profile/docs/19-statistics-pro-gate.md after Gate 3 Statistics Pro QA succeeds:

| Git SHA | $git_sha$(if [[ -n "$git_status" ]]; then printf ' + dirty'; fi) |
| Build | Release |
| Device / OS | fill manually |
| Tester | fill manually |
| Date | $date_value |
| Purchase Entry Point | enabled |
| Feature Restrictions | enabled |

Required checks:
- Release未準備 and 購入導線ONのみ still show the existing dashboard.
- 機能制限ON + 無料 and 装飾パスのみ show the lightweight Pro preview.
- Proサブ and ライフタイム show the existing dashboard.
- Calendar, today score, streak, daily card, friends, sharing, and record creation remain free.
- Purchase entry from the Pro preview reuses SupportLiminalogView.

Next:
1. Complete the Gate 3 QA Evidence Sheet.
2. Run swift Scripts/validate-storekit-config.swift --validate-statistics-pro-qa-complete.
3. Run Scripts/prepare-purchase-gate3-code-change.sh before enabling featureRestrictionsAreEnabled.
4. After the code change, run Scripts/validate-purchase-readiness.sh --gate3-ready.
REPORT
