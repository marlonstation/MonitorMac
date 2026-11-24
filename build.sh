#!/bin/zsh
set -eu
cd "${0:A:h}"
source_dir="$PWD"
mode="${1:---standard}"
case "$mode" in
  --standard|--experimental-sensors) ;;
  *) print -u2 "Usage: zsh build.sh [--standard|--experimental-sensors]"; exit 2 ;;
esac
if (( $# > 1 )); then
  print -u2 "Usage: zsh build.sh [--standard|--experimental-sensors]"
  exit 2
fi
build_root="${MONITORMAC_BUILD_ROOT:-${TMPDIR:-/tmp}/monitormac-build}"
deployment_target=arm64-apple-macosx27.0
mkdir -p "$build_root"
cd "$build_root"
mkdir -p build/MonitorMac.app/Contents/MacOS
typeset -a sensor_flags sensor_objects
sensor_flags=()
sensor_objects=()
if [[ "$mode" == --experimental-sensors ]]; then
  clang -target "$deployment_target" -O2 -c "$source_dir/Sources/Sensors.c" -o build/Sensors.o
  clang -target "$deployment_target" -O2 -c "$source_dir/Sources/SMC.c" -o build/SMC.o
  sensor_flags=(-D EXPERIMENTAL_SENSORS -import-objc-header "$source_dir/Sources/Sensors.h" -framework IOKit -framework CoreFoundation)
  sensor_objects=(build/Sensors.o build/SMC.o)
fi
typeset -a compiler metrics_sources
compiler=(swiftc -target "$deployment_target" -module-cache-path "$build_root/module-cache" -swift-version 5 -O -parse-as-library)
metrics_sources=("$source_dir/Sources/TemperatureSelection.swift" "$source_dir/Sources/ReadingState.swift" "$source_dir/Sources/OverlayGeometry.swift" "$source_dir/Sources/Metrics.swift")
"${compiler[@]}" "${sensor_flags[@]}" "${metrics_sources[@]}" \
  "$source_dir/Sources/GlobalShortcut.swift" "$source_dir/Sources/MetricsDetails.swift" "$source_dir/Sources/App.swift" \
  "${sensor_objects[@]}" -framework AppKit -framework SwiftUI -framework Carbon -framework ServiceManagement \
  -o build/MonitorMac.app/Contents/MacOS/MonitorMac
cat > build/MonitorMac.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>MonitorMac</string>
<key>CFBundleDisplayName</key><string>MonitorMac</string>
<key>CFBundleIdentifier</key><string>local.monitormac.app</string>
<key>CFBundleExecutable</key><string>MonitorMac</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.6.3</string>
<key>CFBundleVersion</key><string>9</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string></array>
<key>LSMinimumSystemVersion</key><string>27.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
if [[ -n "${MONITORMAC_SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$MONITORMAC_SIGN_IDENTITY" build/MonitorMac.app
else
  codesign --force --sign - build/MonitorMac.app
fi
codesign --verify --deep --strict build/MonitorMac.app
"${compiler[@]}" -D METRICS_TEST "${sensor_flags[@]}" "${metrics_sources[@]}" "${sensor_objects[@]}" -o build/metrics-tests
if [[ "$mode" == --experimental-sensors ]]; then
  clang -target "$deployment_target" -O2 "$source_dir/Tests/smc-codec.c" build/SMC.o -framework IOKit -framework CoreFoundation -o build/smc-codec-tests
  ./build/smc-codec-tests
fi
./build/metrics-tests
printf 'App built at %s/build/MonitorMac.app\n' "$PWD"
