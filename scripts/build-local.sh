#!/bin/bash
# Build a locally signed app for this Mac using the installed Swift compiler.
set -euo pipefail
cd "$(dirname "$0")/.."

staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/DocConverter-build.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT
template_app=DocConverter/DocConverter.app
output_app=build/Release/DocConverter.app
plugin_dir=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr
plugin_args=()
if [ -f "$plugin_dir/lib/swift/host/plugins/libSwiftUIMacros.dylib" ]; then
    plugin_args=(-external-plugin-path "$plugin_dir/lib/swift/host/plugins#$plugin_dir/bin/swift-plugin-server")
fi

xcrun swiftc -O -parse-as-library -module-name DocConverter \
    -module-cache-path "${TMPDIR:-/tmp}/DocConverter-ModuleCache" \
    -target "$(uname -m)-apple-macos26.4" "${plugin_args[@]}" \
    DocConverter/ContentView.swift DocConverter/ConverterEngine.swift \
    DocConverter/DocConverterApp.swift DocConverter/PDFKitView.swift FileOrdering.swift \
    -o "$staging_dir/DocConverter"

ditto "$template_app" "$staging_dir/DocConverter.app"
codesign -d --entitlements :- "$template_app" > "$staging_dir/entitlements.plist" 2>/dev/null
cp "$staging_dir/DocConverter" "$staging_dir/DocConverter.app/Contents/MacOS/DocConverter"
codesign --force --sign - --entitlements "$staging_dir/entitlements.plist" "$staging_dir/DocConverter.app"
codesign --verify --strict "$staging_dir/DocConverter.app"
mkdir -p build/Release
ditto "$staging_dir/DocConverter.app" "$output_app"
echo "Built $PWD/$output_app"
