#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
checkRoot="${1:-$PWD/build/validation}"
mkdir -p "$checkRoot"
checkRoot="$(cd "$checkRoot" && pwd)"
xcodegen generate
for scheme in LunarCalendarCheck ChatHistoryCheck BackupProtocolCheck SixFeaturesCheck UpgradeCheck LegacyStoreProducer MigrationCheck Baseline28StoreProducer Migration28Check; do
  xcodebuild build -project ReminderApp.xcodeproj -scheme "$scheme" \
    -destination 'platform=macOS' -derivedDataPath "$checkRoot/DerivedData" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' > "$checkRoot/$scheme-build.log" 2>&1
 done
for scheme in LunarCalendarCheck ChatHistoryCheck BackupProtocolCheck SixFeaturesCheck UpgradeCheck; do
  "$checkRoot/DerivedData/Build/Products/Debug/$scheme" | tee "$checkRoot/$scheme-run.log"
done
storeRoot="$(mktemp -d "$checkRoot/stores.XXXXXX")"
"$checkRoot/DerivedData/Build/Products/Debug/LegacyStoreProducer" "$storeRoot/legacy.store"
"$checkRoot/DerivedData/Build/Products/Debug/MigrationCheck" "$storeRoot/legacy.store"
"$checkRoot/DerivedData/Build/Products/Debug/Baseline28StoreProducer" "$storeRoot/build70.store"
"$checkRoot/DerivedData/Build/Products/Debug/Migration28Check" "$storeRoot/build70.store"
for artifact in ios-export-v3.json ios-sync-edit-v3.json android-ios-roundtrip-v3.json; do
  if [ -f "$artifact" ]; then mv "$artifact" "$checkRoot/"; fi
done
