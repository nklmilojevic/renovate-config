#!/usr/bin/env bash
# Rewrites the vendorHash that buildGoModule pins in a Nix package after a
# Go dependency update. Renovate runs it as a postUpgradeTask through the
# go-vendor-hash preset; it also works by hand from a repo root:
#
#   nix run github:nklmilojevic/renovate-config#go-vendor-hash [package-file] [attr]
#
# package-file defaults to package.nix, attr to .#default.
set -euo pipefail

package_file=${1:-package.nix}
attr=${2:-.#default}

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
log="$workdir/build.log"

build() {
  nix --extra-experimental-features 'nix-command flakes' \
    build "${attr}.goModules" --no-link --no-write-lock-file >"$log" 2>&1
}

if build; then
  echo "vendorHash in ${package_file} is current"
  exit 0
fi

got=$(sed -nE 's/^[[:space:]]*got:[[:space:]]*(sha256-[A-Za-z0-9+/=]+).*/\1/p' "$log" | tail -n1)
if [ -z "$got" ]; then
  cat "$log" >&2
  echo "error: nix build failed for a reason other than a vendorHash mismatch" >&2
  exit 1
fi

cp "$package_file" "$workdir/original"
sed -i.bak -E "s|vendorHash = \"sha256-[A-Za-z0-9+/=]+\";|vendorHash = \"${got}\";|" "$package_file"
rm -f "${package_file}.bak"

if cmp -s "$package_file" "$workdir/original"; then
  echo "error: no vendorHash = \"sha256-...\"; line in ${package_file}" >&2
  exit 1
fi

if ! build; then
  cp "$workdir/original" "$package_file"
  cat "$log" >&2
  echo "error: nix build still fails with vendorHash ${got}; ${package_file} restored" >&2
  exit 1
fi

echo "vendorHash in ${package_file} set to ${got}"
