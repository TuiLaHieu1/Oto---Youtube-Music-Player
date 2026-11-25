#!/bin/sh
# Tải Python cho iOS (BeeWare Python-Apple-support) và các gói Python thuần cần cho khảo sát
# vào Vendor/ (được gitignore). Chỉ dùng cho nhánh khảo sát, cờ OTO_STREAM_PROBE.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VENDOR="$ROOT/Vendor"
PY_TAG="3.14-b14"
PY_URL="https://github.com/beeware/Python-Apple-support/releases/download/$PY_TAG/Python-3.14-iOS-support.b14.tar.gz"
PY_SHA256="703ff822529f46edcbcd8b88096b2544f6990f3109ad38b4b4b61bb489a7c1ee"
YTDLP_VERSION="2026.11.23"
EJS_VERSION="0.8.0"
CERTIFI_VERSION="2026.11.20"
REQUESTS_VERSION="2.34.2"
URLLIB3_VERSION="2.8.0"
IDNA_VERSION="3.20"
CHARSET_VERSION="3.5.3"

mkdir -p "$VENDOR"
if [ ! -d "$VENDOR/Python.xcframework" ]; then
    echo "Tải Python $PY_TAG cho iOS..."
    curl -fsSL -o "$VENDOR/python-ios.tar.gz" "$PY_URL"
    echo "$PY_SHA256  $VENDOR/python-ios.tar.gz" | shasum -a 256 -c -
    tar -xzf "$VENDOR/python-ios.tar.gz" -C "$VENDOR" Python.xcframework
    rm "$VENDOR/python-ios.tar.gz"
fi

# Chỉ nhận wheel thuần Python (py3-none-any) để không phải đóng gói thư viện C riêng cho iOS.
# requests giữ kết nối giữa các request của yt-dlp; urllib mở kết nối mới cho mỗi request,
# đo trên iPhone mỗi lần bắt tay TCP+TLS mất 3–5 giây khi mạng chậm.
rm -rf "$VENDOR/app_packages"
python3 -m pip install --quiet --no-deps --only-binary=:all: --platform any --implementation py \
    --python-version 3.14 --target "$VENDOR/app_packages" \
    "yt-dlp==$YTDLP_VERSION" "yt-dlp-ejs==$EJS_VERSION" "certifi==$CERTIFI_VERSION" \
    "requests==$REQUESTS_VERSION" "urllib3==$URLLIB3_VERSION" "idna==$IDNA_VERSION" \
    "charset-normalizer==$CHARSET_VERSION"
find "$VENDOR/app_packages" -name "*.so" -o -name "*.dylib" | while read -r binary; do
    echo "Gói có file nhị phân không mong muốn: $binary" >&2
    exit 1
done
rm -rf "$VENDOR/app_packages/bin" "$VENDOR/app_packages/share" "$VENDOR/app_packages"/*.dist-info/RECORD
echo "Xong: $(du -sh "$VENDOR/Python.xcframework" | cut -f1) Python, $(du -sh "$VENDOR/app_packages" | cut -f1) gói."
