#!/usr/bin/env bash
# Exports godot/ to ios/game.pck with a Godot 4.7.2 editor (pack only: no export templates needed).
# Usage: GODOT=/path/to/Godot ./make-pck.sh
set -euo pipefail
cd "$(dirname "$0")"
godot=${GODOT:-godot}
"$godot" --headless --path godot --import
"$godot" --headless --path godot --export-pack iOS "$PWD/ios/game.pck"
ls -l ios/game.pck
