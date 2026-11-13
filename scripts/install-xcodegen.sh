#!/bin/bash
# CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
#
# Installs XcodeGen from its official GitHub release (no Homebrew, no sudo) into
# ~/.local, then generates CasaPlay.xcodeproj. Touches nothing outside ~/.local
# and this project: no macOS, Xcode, PATH or signing changes.
#
# Usage:  ./scripts/install-xcodegen.sh            (installs 2.46.0)
#         XCODEGEN_VERSION=2.45.4 ./scripts/install-xcodegen.sh

set -euo pipefail

VERSION="${XCODEGEN_VERSION:-2.46.0}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="$HOME/.local/share/xcodegen-$VERSION"
BIN_LINK="$HOME/.local/bin/xcodegen"
URL="https://github.com/yonaskolb/XcodeGen/releases/download/$VERSION/xcodegen.zip"

echo "== Your system =="
MACOS="$(sw_vers -productVersion)"
ARCH="$(uname -m)"
echo "macOS:        $MACOS ($(sw_vers -buildVersion))"
echo "Processor:    $ARCH ($(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown))"
echo "Xcode:        $(xcodebuild -version 2>/dev/null | tr '\n' ' ' || echo 'not found')"
echo "Active dir:   $(xcode-select -p 2>/dev/null || echo 'not set')"
echo "Swift:        $(swift --version 2>/dev/null | head -1 || echo 'not found')"
echo

MAJOR="${MACOS%%.*}"
if [ "$MAJOR" -lt 11 ]; then
    echo "XcodeGen $VERSION needs macOS 11 or newer; this Mac has $MACOS."
    echo "CasaPlay itself needs Xcode 15 (macOS 13.5+), so this Mac can't build it."
    echo "Next option: generate the project on a newer Mac or in CI."
    exit 1
fi

run_generate() {
    echo
    echo "== Generating CasaPlay.xcodeproj =="
    cd "$PROJECT_DIR"
    "$1" generate
    echo
    echo "Done. Open it with:  open \"$PROJECT_DIR/CasaPlay.xcodeproj\""
}

echo "== Installing official XcodeGen $VERSION release =="
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if curl -fL --retry 3 -o "$TMP/xcodegen.zip" "$URL"; then
    echo "SHA-256: $(shasum -a 256 "$TMP/xcodegen.zip" | cut -d' ' -f1)"
    unzip -q "$TMP/xcodegen.zip" -d "$TMP"
    BIN="$TMP/xcodegen/bin/xcodegen"

    if ! lipo -archs "$BIN" 2>/dev/null | grep -qw "$ARCH"; then
        echo "The release binary doesn't include $ARCH (it has: $(lipo -archs "$BIN" 2>/dev/null))."
    else
        rm -rf "$INSTALL_DIR"
        mkdir -p "$(dirname "$INSTALL_DIR")" "$(dirname "$BIN_LINK")"
        # Keep bin/ and share/ together: xcodegen finds its setting presets via ../share.
        mv "$TMP/xcodegen" "$INSTALL_DIR"
        xattr -dr com.apple.quarantine "$INSTALL_DIR" 2>/dev/null || true
        ln -sf "$INSTALL_DIR/bin/xcodegen" "$BIN_LINK"

        if "$BIN_LINK" --version; then
            echo "Installed to $INSTALL_DIR (linked at $BIN_LINK)"
            run_generate "$BIN_LINK"
            exit 0
        fi
        echo "The release binary failed to run on this Mac."
    fi
else
    echo "Download failed: $URL"
fi

echo
echo "== Fallback: building XcodeGen $VERSION from source with your own Xcode =="
if ! command -v swift >/dev/null; then
    echo "No Swift toolchain found. Install Xcode's command line tools: xcode-select --install"
    exit 1
fi
SRC="$HOME/.local/src/XcodeGen-$VERSION"
rm -rf "$SRC"
mkdir -p "$(dirname "$SRC")"
git clone --depth 1 --branch "$VERSION" https://github.com/yonaskolb/XcodeGen.git "$SRC"
cd "$SRC"
swift build -c release --disable-sandbox --product xcodegen
mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/share/xcodegen" "$(dirname "$BIN_LINK")"
cp "$(swift build -c release --show-bin-path)/xcodegen" "$INSTALL_DIR/bin/"
cp -R SettingPresets "$INSTALL_DIR/share/xcodegen/"
ln -sf "$INSTALL_DIR/bin/xcodegen" "$BIN_LINK"
"$BIN_LINK" --version
run_generate "$BIN_LINK"
