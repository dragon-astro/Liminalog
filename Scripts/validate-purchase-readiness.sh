#!/usr/bin/env bash

set -euo pipefail

run_release_build=false
run_gate1_ready=false
run_gate2_ready=false
run_gate3_ready=false
run_status=false
release_gate_state="closed"
storekit_path="${LIMINALOG_STOREKIT_CONFIG:-liminalog.storekit}"
swift_module_cache_path="${LIMINALOG_SWIFT_MODULE_CACHE_PATH:-/private/tmp/liminalog-swift-module-cache}"

for argument in "$@"; do
  case "$argument" in
    --release-build)
      run_release_build=true
      ;;
    --gate1-ready)
      run_gate1_ready=true
      run_release_build=true
      ;;
    --gate2-ready)
      run_gate1_ready=true
      run_gate2_ready=true
      run_release_build=true
      ;;
    --gate3-ready)
      run_gate1_ready=true
      run_gate2_ready=true
      run_gate3_ready=true
      run_release_build=true
      ;;
    --status)
      run_status=true
      ;;
    --storekit=*)
      storekit_path="${argument#--storekit=}"
      ;;
    --help|-h)
      cat <<'USAGE'
usage:
  Scripts/validate-purchase-readiness.sh [--release-build] [--gate1-ready] [--gate2-ready] [--gate3-ready] [--status] [--storekit=path/to/liminalog.storekit]

Runs the purchase-release checks that do not require App Store Connect access.
The StoreKit configuration check is skipped with a note when the file is absent.
Use --gate1-ready only after App Store Connect products are created and the confirmation sheet is filled.
Use --gate2-ready only after Local StoreKit purchase QA and Purchase UI QA evidence are complete.
Use --gate3-ready only after Statistics Pro restriction QA evidence is complete.
Gate ready checks validate the matching PurchaseConfiguration.current state instead of the initial closed state.
Use --status to print current gate blockers without failing on incomplete future gates.
USAGE
      exit 0
      ;;
    *)
      echo "error: unknown argument: $argument" >&2
      exit 64
      ;;
  esac
done

if [[ "$run_gate3_ready" == true ]]; then
  release_gate_state="gate3"
elif [[ "$run_gate2_ready" == true ]]; then
  release_gate_state="gate2"
elif [[ "$run_gate1_ready" == true ]]; then
  release_gate_state="gate1"
fi

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

run_status_check() {
  local title="$1"
  shift
  local output

  if output=$("$@" 2>&1); then
    echo "PASS: $title"
  else
    echo "BLOCKED: $title"
  fi

  if [[ -n "$output" ]]; then
    echo "$output" | sed 's/^/  /'
  fi
}

print_purchase_status() {
  echo "Purchase readiness status"
  echo

  run_status_check "Current Release gate is closed" \
    run_swift_validator --validate-release-gate-state closed

  run_status_check "Legal URLs are reachable" \
    Scripts/validate-purchase-legal-urls.sh

  if [[ -f "$storekit_path" ]]; then
    run_status_check "StoreKit configuration is present and valid: $storekit_path" \
      run_swift_validator "$storekit_path"

    run_status_check "Premium decoration single products remain inactive" \
      run_swift_validator --validate-premium-decoration-inactive "$storekit_path"
  else
    echo "BLOCKED: StoreKit configuration is present and valid: $storekit_path"
    echo "  StoreKit configuration not found."
  fi

  run_status_check "Gate 1 App Store Connect confirmation is complete" \
    run_swift_validator --validate-app-store-connect-confirmation-complete

  run_status_check "Gate 1 code state is applied" \
    run_swift_validator --validate-release-gate-state gate1

  run_status_check "Gate 2 Local StoreKit QA evidence is complete" \
    run_swift_validator --validate-storekit-local-qa-complete

  run_status_check "Gate 2 Purchase UI QA evidence is complete" \
    run_swift_validator --validate-purchase-ui-qa-complete

  run_status_check "Gate 2 code state is applied" \
    run_swift_validator --validate-release-gate-state gate2

  run_status_check "Gate 3 Statistics Pro QA evidence is complete" \
    run_swift_validator --validate-statistics-pro-qa-complete

  run_status_check "Gate 3 code state is applied" \
    run_swift_validator --validate-release-gate-state gate3
}

if [[ "$run_status" == true ]]; then
  print_purchase_status
  exit 0
fi

run_step "Validate purchase product document" \
  run_swift_validator --validate-products-doc

run_step "Validate App Store Connect confirmation template" \
  run_swift_validator --validate-app-store-connect-confirmation-template

run_step "Validate App Store Connect product setup sheet" \
  run_swift_validator --validate-products-doc AppStore/AppStoreConnectProductSetup.md

run_step "Validate monetization policy document" \
  run_swift_validator --validate-monetization-doc

run_step "Validate App Review notes" \
  run_swift_validator --validate-review-notes

run_step "Validate purchase product source" \
  run_swift_validator --validate-product-source

run_step "Validate premium decoration product document" \
  run_swift_validator --validate-premium-decoration-products-doc

run_step "Validate premium decoration UI remains disconnected" \
  run_swift_validator --validate-premium-decoration-ui-disconnected

run_step "Validate Release purchase gate state: $release_gate_state" \
  run_swift_validator --validate-release-gate-state "$release_gate_state"

run_step "Validate Xcode scheme StoreKit link" \
  run_swift_validator --validate-xcode-scheme-storekit

run_step "Print App Store Connect product TSV" \
  run_swift_validator --app-store-connect-tsv

run_step "Print App Store Connect confirmation sheet" \
  run_swift_validator --app-store-connect-confirmation-md

run_step "Validate legal URLs" \
  Scripts/validate-purchase-legal-urls.sh

if [[ -f "$storekit_path" ]]; then
  run_step "Validate StoreKit configuration: $storekit_path" \
    run_swift_validator "$storekit_path"

  run_step "Validate premium decoration products are inactive" \
    run_swift_validator --validate-premium-decoration-inactive "$storekit_path"
else
  echo
  echo "note: StoreKit configuration not found at $storekit_path"
  echo "note: local StoreKit purchase testing remains blocked until it is created in Xcode."
fi

if [[ "$run_gate1_ready" == true ]]; then
  run_step "Validate App Store Connect confirmation is complete" \
    run_swift_validator --validate-app-store-connect-confirmation-complete
fi

if [[ "$run_gate2_ready" == true ]]; then
  run_step "Validate Local StoreKit QA evidence is complete" \
    run_swift_validator --validate-storekit-local-qa-complete

  run_step "Validate Purchase UI QA evidence is complete" \
    run_swift_validator --validate-purchase-ui-qa-complete
fi

if [[ "$run_gate3_ready" == true ]]; then
  run_step "Validate Statistics Pro QA evidence is complete" \
    run_swift_validator --validate-statistics-pro-qa-complete
fi

run_step "Check whitespace in git diffs" \
  git diff --check

if [[ "$run_release_build" == true ]]; then
  run_step "Build Release for generic iOS" \
    xcodebuild \
      -project Liminalog.xcodeproj \
      -scheme Liminalog \
      -configuration Release \
      -destination "generic/platform=iOS" \
      -derivedDataPath /private/tmp/LiminalogMonetizationReleaseDerivedData \
      build
fi

echo
echo "Purchase readiness checks completed."
