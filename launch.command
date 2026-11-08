#!/bin/zsh
set -eu
cd "${0:A:h}"
source scripts/terminal-ui.sh
version="$(<VERSION)"
target_arch="$(uname -m)"
app="$PWD/dist/native-hevc/$version/$target_arch/Bailong Desktop Pet.app"
bailong_header "Open application" "$target_arch"
print -r -- "Application: $app"
if [[ ! -d "$app" ]]; then
    print -u2 "Application not found. First run: ./build.command $target_arch"
    exit 1
fi
open "$app"
