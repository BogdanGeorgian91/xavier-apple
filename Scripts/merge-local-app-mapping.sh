#!/bin/sh
set -eu

LOCAL_MAPPING="${SRCROOT}/Config/NETestAppMapping.local.plist"
BUILT_PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
PROXY_UUID="${XAVIER_APP_PROXY_UUID:-AA113482-C47E-4326-9633-31C8D2BAE8A1}"

if [ ! -f "$LOCAL_MAPPING" ] || [ ! -f "$BUILT_PLIST" ]; then
    exit 0
fi

/usr/libexec/PlistBuddy -c "Print :NETestAppMapping:${PROXY_UUID}" "$BUILT_PLIST" >/dev/null 2>&1 || exit 0

/usr/libexec/PlistBuddy -c "Print :AdditionalNETestAppBundleIDs" "$LOCAL_MAPPING" 2>/dev/null | while IFS= read -r line; do
    bundleID=$(printf "%s" "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$bundleID" in
        ""|"Array {"|"}")
            continue
            ;;
    esac

    /usr/libexec/PlistBuddy -c "Add :NETestAppMapping:${PROXY_UUID}: string ${bundleID}" "$BUILT_PLIST" 2>/dev/null || true
done
