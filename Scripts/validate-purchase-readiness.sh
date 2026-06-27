#!/usr/bin/env bash

set -euo pipefail

run_release_build=false
run_gate1_ready=false
run_gate2_ready=false
storekit_path="${LIMINALOG_STOREKIT_CONFIG:-liminalog.storekit}"

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
    --storekit=*)
      storekit_path="${argument#--storekit=}"
      ;;
    --help|-h)
      cat <<'USAGE'
usage:
  Scripts/validate-purchase-readiness.sh [--release-build] [--gate1-ready] [--gate2-ready] [--storekit=path/to/liminalog.storekit]

Runs the purchase-release checks that do not require App Store Connect access.
The StoreKit configuration check is skipped with a note when the file is absent.
Use --gate1-ready only after App Store Connect products are created and the confirmation sheet is filled.
Use --gate2-ready only after Local StoreKit purchase QA evidence is complete.
USAGE
      exit 0
      ;;
    *)
      echo "error: unknown argument: $argument" >&2
      exit 64
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

run_step "Validate purchase product document" \
  swift Scripts/validate-storekit-config.swift --validate-products-doc

run_step "Validate App Store Connect confirmation template" \
  swift Scripts/validate-storekit-config.swift --validate-app-store-connect-confirmation-template

run_step "Validate purchase product source" \
  swift Scripts/validate-storekit-config.swift --validate-product-source

run_step "Validate premium decoration product document" \
  swift Scripts/validate-storekit-config.swift --validate-premium-decoration-products-doc

run_step "Validate Release purchase safety switches" \
  swift Scripts/validate-storekit-config.swift --validate-release-safety

run_step "Validate Xcode scheme StoreKit link" \
  swift Scripts/validate-storekit-config.swift --validate-xcode-scheme-storekit

run_step "Print App Store Connect product TSV" \
  swift Scripts/validate-storekit-config.swift --app-store-connect-tsv

run_step "Print App Store Connect confirmation sheet" \
  swift Scripts/validate-storekit-config.swift --app-store-connect-confirmation-md

run_step "Validate legal URLs" \
  Scripts/validate-purchase-legal-urls.sh

if [[ -f "$storekit_path" ]]; then
  run_step "Validate StoreKit configuration: $storekit_path" \
    swift Scripts/validate-storekit-config.swift "$storekit_path"

  run_step "Validate premium decoration products are inactive" \
    swift Scripts/validate-storekit-config.swift --validate-premium-decoration-inactive "$storekit_path"
else
  echo
  echo "note: StoreKit configuration not found at $storekit_path"
  echo "note: local StoreKit purchase testing remains blocked until it is created in Xcode."
fi

if [[ "$run_gate1_ready" == true ]]; then
  run_step "Validate App Store Connect confirmation is complete" \
    swift Scripts/validate-storekit-config.swift --validate-app-store-connect-confirmation-complete
fi

if [[ "$run_gate2_ready" == true ]]; then
  run_step "Validate Local StoreKit QA evidence is complete" \
    swift Scripts/validate-storekit-config.swift --validate-storekit-local-qa-complete
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
