#!/usr/bin/env bash

set -euo pipefail

terms_url="${1:-https://liminalog-lp.vercel.app/terms}"
privacy_url="${2:-https://liminalog-lp.vercel.app/privacy}"

check_url() {
  local label="$1"
  local url="$2"
  local status

  status="$(curl -L -sS -o /dev/null -w "%{http_code}" "$url")"
  if [[ "$status" == "200" ]]; then
    echo "$label OK: $url ($status)"
    return 0
  fi

  echo "error: $label is not reachable: $url ($status)" >&2
  return 1
}

check_url "Terms of Use" "$terms_url"
check_url "Privacy Policy" "$privacy_url"
