#!/usr/bin/env bash
# Download a published release; no compiler or source checkout required.
set -euo pipefail
main() {
  local repo=Grrck-Git/steam-frame-dictation tag=${1:-} url archive checksum root asset
  if (( $# > 1 )) || { (( $# == 1 )) && [[ ! "$tag" =~ ^v[0-9][a-zA-Z0-9._-]*$ ]]; }; then
    echo 'Usage: bash install.sh [release-tag]' >&2
    return 1
  fi
  # Global so the EXIT trap can clean up after main returns.
  work=''
  [[ $(id -u) != 0 ]] || { echo 'Run as your normal user, not sudo/root.' >&2; return 1; }
  [[ $(uname -m) == aarch64 ]] || { echo 'Requires an ARM64 Steam Frame.' >&2; return 1; }
  for cmd in curl tar sha256sum mktemp systemctl pw-record pw-play wpctl; do
    command -v "$cmd" >/dev/null || { echo "Missing command: $cmd" >&2; return 1; }
  done
  [[ -w /dev/uinput && -r /dev/input/by-path/platform-gpio-keys-event ]] || {
    echo 'Missing access to /dev/uinput or the aux input device.' >&2; return 1;
  }
  systemctl --user show-environment >/dev/null
  # Resolve latest once, then fetch immutable versioned assets (avoids release races).
  if [[ ${SFD_PRIVATE:-0} == 1 ]]; then
    command -v gh >/dev/null || { echo 'Private downloads require authenticated GitHub CLI.' >&2; return 1; }
    if [[ -z "$tag" ]]; then
      tag=$(gh release view --repo "$repo" --json tagName --jq .tagName)
    fi
  elif [[ -z "$tag" ]]; then
    url=$(curl --fail --silent --show-error --location --retry 3 --connect-timeout 20 \
      --output /dev/null --write-out '%{url_effective}' "https://github.com/$repo/releases/latest") || {
      echo "Could not find a published release in $repo." >&2; return 1;
    }
    [[ "$url" == "https://github.com/$repo/releases/tag/"* ]] || { echo 'Unexpected release URL.' >&2; return 1; }
    tag=${url##*/}
  fi
  [[ "$tag" =~ ^v[0-9][a-zA-Z0-9._-]*$ ]] || { echo 'Invalid release tag.' >&2; return 1; }
  archive="steam-frame-dictation-aarch64-steamos-$tag.tar.gz"
  checksum="$archive.sha256"
  work=$(mktemp -d)
  trap 'rm -rf -- "$work"' EXIT
  echo "Downloading Steam Frame Dictation $tag..."
  if [[ ${SFD_PRIVATE:-0} == 1 ]]; then
    gh release download "$tag" --repo "$repo" --dir "$work" --pattern "$archive" --pattern "$checksum"
  else
    for asset in "$archive" "$checksum"; do
      curl --fail --show-error --location --retry 3 --connect-timeout 20 \
        "https://github.com/$repo/releases/download/$tag/$asset" --output "$work/$asset"
    done
  fi
  # Only verify the versioned archive; the manifest also lists the latest alias.
  (cd "$work"; awk -v name="$archive" '$2 == name {print; found=1} END {if (!found) exit 1}' "$checksum" > selected.sha256
    sha256sum --check selected.sha256)
  tar -xzf "$work/$archive" -C "$work" --no-same-owner
  root="$work/${archive%.tar.gz}"
  [[ -f "$root/install.sh" ]] || { echo 'Release installer missing.' >&2; return 1; }
  bash "$root/install.sh" </dev/null
  sleep 3
  systemctl --user is-active --quiet frame-dictation.service
  echo 'Ready. Press aux, wait for the chime, then speak.'
  echo 'Uninstall: ~/.local/share/steam-frame-dictation/bin/steam-frame-dictation --uninstall'
}
# Keep the whole entry point parsed before executing when piped into bash.
main "$@"
