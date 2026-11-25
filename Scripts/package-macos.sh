#!/bin/bash
set -euo pipefail

if [[ $# != 2 || ( "$1" != --local && "$1" != --release ) ]]; then
    printf 'Usage: %s {--local|--release} output-directory\n' "$0" >&2
    exit 2
fi

mode=$1
mkdir -p "$2"
output=$(cd "$2" && pwd -P)
root=$(cd "$(dirname "$0")/.." && pwd -P)

if [[ "$mode" == --release ]]; then
    : "${MODEL_STUDIO_SIGNING_IDENTITY:?Set a Developer ID Application signing identity.}"
    : "${MODEL_STUDIO_NOTARY_PROFILE:?Set the notarytool Keychain profile name.}"
fi

work=$(mktemp -d "$output/.modelstudio.XXXXXXXX")
trap 'rm -rf "$work"' EXIT

xcodebuild -project "$root/ModelStudio.xcodeproj" -scheme ModelStudio -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$work/build" \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build

app="$work/build/Build/Products/Release/ModelStudio.app"
archive="$work/ModelStudio.zip"
architectures=$(lipo -archs "$app/Contents/MacOS/ModelStudio")
case "$architectures" in
    'arm64 x86_64'|'x86_64 arm64') ;;
    *) printf 'Expected arm64 and x86_64. Found %s\n' "$architectures" >&2; exit 1 ;;
esac

if [[ "$mode" == --release ]]; then
    codesign --force --sign "$MODEL_STUDIO_SIGNING_IDENTITY" --options runtime --timestamp "$app"
    ditto -c -k --keepParent "$app" "$archive"
    xcrun notarytool submit "$archive" --keychain-profile "$MODEL_STUDIO_NOTARY_PROFILE" --wait --output-format plist > "$work/notary.plist"
    status=$(/usr/libexec/PlistBuddy -c 'Print :status' "$work/notary.plist")
    if [[ "$status" != Accepted ]]; then
        submission=$(/usr/libexec/PlistBuddy -c 'Print :id' "$work/notary.plist")
        printf 'Notarization %s for %s. Use notarytool log to inspect the submission.\n' "$status" "$submission" >&2
        exit 1
    fi
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    syspolicy_check distribution "$app"
    rm "$archive"
    name=ModelStudio.zip
else
    codesign --force --sign - --options runtime "$app"
    name=ModelStudio-local.zip
fi

codesign --verify --deep --strict --verbose=2 "$app"
ditto -c -k --keepParent "$app" "$archive"
mv -f "$archive" "$output/$name"
printf 'Package: %s\n' "$output/$name"
