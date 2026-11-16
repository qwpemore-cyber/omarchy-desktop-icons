#!/usr/bin/env bash
set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/bog.desktop-icons"

if [[ -e $dest && ! -L $dest ]]; then
  echo "refusing to replace non-symlink: $dest" >&2
  exit 1
fi

mkdir -p "$(dirname "$dest")"
ln -sfn "$src" "$dest"
echo "linked $dest -> $src"
echo "enable it with: omarchy plugin enable bog.desktop-icons"

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell -q shell rescanPlugins || true
fi
