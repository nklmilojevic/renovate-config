#!/usr/bin/env bash
# Rewrites the vendorHash that buildGoModule pins in a Nix file after a Go
# dependency update. Renovate runs it as a postUpgradeTask through the
# go-vendor-hash preset; it also works by hand from a repo root:
#
#   nix run github:nklmilojevic/renovate-config#go-vendor-hash [-- package-file attr]
#
# package-file defaults to package.nix, attr to .#default. The file must hold
# exactly one vendorHash = "sha256-..."; line.
#
# Nix stores the vendored modules under the hash, so building with the old
# hash can reuse old modules from the store or a binary cache and pass. The
# script builds with a fake hash instead, which nothing can satisfy, so Nix
# always vendors the modules again and reports the real hash.
set -euo pipefail

package_file=${1:-package.nix}
attr=${2:-.#default}

fake_hash="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
hash_line='vendorHash = "sha256-[A-Za-z0-9+/=]+";'

workdir=$(mktemp -d)
log="$workdir/build.log"

restore() {
  cp "$workdir/original" "$package_file"
}

cleanup() {
  status=$?
  if [ "$status" -ne 0 ] && [ -f "$workdir/original" ]; then
    restore
  fi
  rm -rf "$workdir"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

build() {
  nix --extra-experimental-features 'nix-command flakes' \
    build "${attr}.goModules" --no-link --no-write-lock-file >"$log" 2>&1
}

set_hash() {
  sed -i.bak -E "s|${hash_line}|vendorHash = \"$1\";|" "$package_file"
  rm -f "${package_file}.bak"
}

count=$(grep -cE "$hash_line" "$package_file" || true)
if [ "$count" -ne 1 ]; then
  echo "error: expected one vendorHash = \"sha256-...\"; line in ${package_file}, found ${count}" >&2
  exit 1
fi
old=$(sed -nE "s|.*vendorHash = \"(sha256-[A-Za-z0-9+/=]+)\";.*|\1|p" "$package_file")

cp "$package_file" "$workdir/original"
set_hash "$fake_hash"

if build; then
  echo "error: ${attr}.goModules built with a fake vendorHash" >&2
  exit 1
fi

got=$(sed -nE 's/^[[:space:]]*got:[[:space:]]*(sha256-[A-Za-z0-9+/=]+).*/\1/p' "$log" | tail -n1)
if [ -z "$got" ]; then
  cat "$log" >&2
  echo "error: nix build failed for a reason other than a vendorHash mismatch" >&2
  exit 1
fi

if [ "$got" = "$old" ]; then
  restore
  echo "vendorHash in ${package_file} is current"
  exit 0
fi

set_hash "$got"
if ! build; then
  cat "$log" >&2
  echo "error: nix build still fails with vendorHash ${got}" >&2
  exit 1
fi

echo "vendorHash in ${package_file} set to ${got} (was ${old})"
