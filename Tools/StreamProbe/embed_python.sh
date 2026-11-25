#!/bin/sh
# Bước build của target Oto. Không làm gì nếu không có cờ OTO_STREAM_PROBE trong bản Debug,
# nên bản build bình thường không đổi. Khi có cờ: nhúng Python.framework, thư viện chuẩn,
# yt-dlp và plugin JavaScriptCore của Oto vào app rồi ký.
set -eu
case " ${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-} " in
    *" OTO_STREAM_PROBE "*) ;;
    *) exit 0 ;;
esac
if [ "${CONFIGURATION:-}" != "Debug" ]; then
    echo "OTO_STREAM_PROBE chỉ dành cho bản Debug" >&2
    exit 1
fi
XCF="Vendor/Python.xcframework"
if [ ! -d "$PROJECT_DIR/$XCF" ] || [ ! -d "$PROJECT_DIR/Vendor/app_packages" ]; then
    echo "error: thiếu Vendor/. Chạy Tools/StreamProbe/fetch_vendor.sh trước." >&2
    exit 1
fi
case "$EFFECTIVE_PLATFORM_NAME" in
    -iphonesimulator) SLICE="ios-arm64_x86_64-simulator" ;;
    -iphoneos) SLICE="ios-arm64" ;;
    *) echo "error: nền tảng không hỗ trợ $EFFECTIVE_PLATFORM_NAME" >&2; exit 1 ;;
esac

# Python.framework: chép vào Frameworks và ký, vì app chỉ nạp nó bằng dlopen lúc chạy.
FRAMEWORKS="$CODESIGNING_FOLDER_PATH/Frameworks"
mkdir -p "$FRAMEWORKS"
rsync -a --delete "$PROJECT_DIR/$XCF/$SLICE/Python.framework/" "$FRAMEWORKS/Python.framework/"
/usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" ${OTHER_CODE_SIGN_FLAGS:-} \
    -o runtime --timestamp=none --preserve-metadata=identifier,entitlements,flags \
    --generate-entitlement-der "$FRAMEWORKS/Python.framework"

# Gói Python: yt-dlp, yt-dlp-ejs, certifi và mã của Oto.
rsync -a --delete "$PROJECT_DIR/Vendor/app_packages/" "$CODESIGNING_FOLDER_PATH/app_packages/"
rsync -a "$PROJECT_DIR/Tools/StreamProbe/python/" "$CODESIGNING_FOLDER_PATH/app_packages/"

# Thư viện chuẩn và module nhị phân của Python (đổi .so thành framework theo PEP 730).
. "$PROJECT_DIR/$XCF/build/utils.sh"
install_python "$XCF" app_packages
