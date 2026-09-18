#!/usr/bin/env bash
# Install (or update) Super Player into the Omarchy shell and reload it.
#
#   ./install.sh            copy the plugin files and rescan
#   ./install.sh --restart  copy the files and restart the shell
#   ./install.sh --remove   uninstall the plugin from the shell
#
# The shell reads plugins from ~/.config/omarchy/plugins/<plugin-id>/, so the
# sources here are copied over instead of being symlinked (Qt's QML cache gets
# confused by symlinked plugin directories). QML changes only take effect after
# a shell restart, so use --restart while developing.
set -euo pipefail

plugin_id="io.github.enrell.super-player"
source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target_dir="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$plugin_id"

files=(manifest.json Bar.qml LyricsView.qml PlayerService.qml LrcParser.js romanize.py)

if [[ "${1:-}" == "--remove" ]]; then
  omarchy plugin disable "$plugin_id" 2>/dev/null || true
  rm -rf "$target_dir"
  omarchy-shell shell rescanPlugins 2>/dev/null || true
  echo "removed $plugin_id (restart the shell if the bar still shows it)"
  exit 0
fi

mkdir -p "$target_dir"
for file in "${files[@]}"; do
  install -m 644 "$source_dir/$file" "$target_dir/$file"
done

# Drop files that are no longer part of the plugin.
while IFS= read -r existing; do
  name="$(basename "$existing")"
  if [[ ! " ${files[*]} " == *" $name "* ]]; then
    rm -f "$existing"
    echo "removed stale $name"
  fi
done < <(find "$target_dir" -maxdepth 1 -type f)

echo "installed $plugin_id -> $target_dir"

if [[ "${1:-}" == "--restart" ]]; then
  omarchy restart shell
  echo "omarchy shell restarted"
else
  omarchy-shell shell rescanPlugins 2>/dev/null || true
  echo "plugins rescanned (use --restart when a QML file changed)"
fi
