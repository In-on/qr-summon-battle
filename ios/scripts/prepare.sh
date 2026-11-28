#!/usr/bin/env bash
# Codemagic（macOS）で実行：ゲームファイルを ios/www にコピーし、アイコンを用意して Xcode プロジェクトを生成する。
# リポジトリ直下（＝GitHub Pages で公開している Web 版）のファイルは一切書き換えない。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IOS="$ROOT/ios"
WWW="$IOS/www"

# ---- 既定値（Codemagic の環境変数で上書き）----
export BUNDLE_ID="${BUNDLE_ID:-com.qrsummon.battle}"
export APP_VERSION="${APP_VERSION:-1.0.0}"
# 未設定のときは Google 公式のテスト用ID（本番では必ず自分のIDを設定する）
export ADMOB_APP_ID="${ADMOB_APP_ID:-ca-app-pub-3940256099942544~1458002511}"
export ADMOB_REWARDED_ID="${ADMOB_REWARDED_ID:-ca-app-pub-3940256099942544/1712485313}"
# 携帯品BOX 用（未設定なら スタミナ用と同じID）
export ADMOB_REWARDED_BOX_ID="${ADMOB_REWARDED_BOX_ID:-$ADMOB_REWARDED_ID}"

echo "BUNDLE_ID=$BUNDLE_ID  APP_VERSION=$APP_VERSION"
case "$ADMOB_APP_ID" in ca-app-pub-3940256099942544*) echo "⚠️  AdMob はテスト用IDでビルドしています（審査用には本番IDを設定してください）";; esac

# ---- ゲーム本体をコピー ----
rm -rf "$WWW"
mkdir -p "$WWW"
cd "$ROOT"
cp index.html privacy.html terms.html tokusho.html shikin.html "$WWW/"
cp ./*.js "$WWW/"
cp ./*.png "$WWW/" 2>/dev/null || true
cp -R lib "$WWW/lib"
echo "www: $(du -sh "$WWW" | cut -f1)"

# ---- アプリアイコン（1024x1024・透明なし）----
ICON_DIR="$IOS/QRSummon/Assets.xcassets/AppIcon.appiconset"
ICON_OUT="$ICON_DIR/icon-1024.png"
if [ -f "$IOS/icon-1024.png" ]; then
  SRC="$IOS/icon-1024.png"
elif [ -f "$ROOT/icon-1024.png" ]; then
  SRC="$ROOT/icon-1024.png"
else
  echo "⚠️  ios/icon-1024.png が無いので apple-touch-icon.png を拡大して仮アイコンにします（画質が粗くなります）"
  SRC="$ROOT/apple-touch-icon.png"
fi
TMP="$(mktemp -d)"
sips -z 1024 1024 "$SRC" --out "$TMP/a.png" >/dev/null
# JPEG を経由して透明（アルファ）を取り除く（App Store のアイコンは透明不可）
sips -s format jpeg -s formatOptions 100 "$TMP/a.png" --out "$TMP/a.jpg" >/dev/null
sips -s format png "$TMP/a.jpg" --out "$ICON_OUT" >/dev/null
rm -rf "$TMP"

# ---- Xcode プロジェクトを生成 ----
cd "$IOS"
xcodegen generate
echo "✅ ios/QRSummon.xcodeproj を生成しました"
