#!/bin/zsh
set -eu
cd "${0:A:h:h}"
source scripts/terminal-ui.sh

if (( $# > 1 )) || { (( $# == 1 )) && [[ "$1" != "--build-only" ]]; }; then
    print -u2 "Usage: $0 [--build-only]"
    exit 2
fi

bailong_header "Development build · No .app bundle" "arm64"
source scripts/swift-sources.sh
binary=".build/dev/BailongPetDev"
mkdir -p .build/dev .build/module-cache
rebuild=0
[[ -x "$binary" ]] || rebuild=1
source_manifest="${(F)swift_sources}"
[[ -f .build/dev/sources.txt && "$(<.build/dev/sources.txt)" == "$source_manifest" ]] || rebuild=1
for source in $swift_sources VERSION scripts/swift-sources.sh "${0:A}"; do
    if [[ "$source" -nt "$binary" ]]; then rebuild=1; break; fi
done

if (( rebuild )); then
    bailong_phase_begin "1/1" "Compile development build"
    {
    version="$(<VERSION)"
    # 将应用身份与系统语言设置嵌入可执行文件，直接运行也使用原生框架本地化。
    cat > .build/dev/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.bailongpet.appkit</string>
<key>CFBundleName</key><string>Bailong Desktop Pet (Development)</string>
<key>CFBundleVersion</key><string>${version%%-*}</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleAllowMixedLocalizations</key><true/>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Reveal local files and restore their Finder windows when you open a file link.</string>
</dict></plist>
PLIST
    xcrun swiftc -O -whole-module-optimization -swift-version 5 \
        -target arm64-apple-macosx14.0 -module-cache-path .build/module-cache \
        $swift_sources -framework AppKit -framework AVFoundation -framework CoreImage -framework Metal -lsqlite3 \
        -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker .build/dev/Info.plist \
        -o "$binary.next"
    mv "$binary.next" "$binary"
    print -r -- "$source_manifest" > .build/dev/sources.txt
    } > "$bailong_phase_log" 2>&1
    bailong_phase_end
else
    print "Source unchanged; reusing previous build."
fi

bailong_artifact "Development binary" "$binary"
if [[ "${1:-}" == "--build-only" ]]; then
    print "Compilation complete · Total time $((SECONDS-bailong_started)) s"
    exit 0
fi
[[ -f "local-assets/native-hevc/catalog/素材清单.json" ]] || { print -u2 "Prepare local-assets/native-hevc/catalog as described in README first."; exit 1; }
print "Starting development build. Press Ctrl+C to stop."
export BAILONG_DEV_RUN=1
exec "$binary"
