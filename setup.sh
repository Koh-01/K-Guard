#!/usr/bin/env bash
# 生成 Android / iOS 工程，并加入 NFC 与网络权限。只需运行一次。
set -e
cd "$(dirname "$0")"

flutter create --org com.nfcguard --project-name nfc_guard --platforms android,ios .
rm -f test/widget_test.dart

# ---------- Android ----------
M=android/app/src/main/AndroidManifest.xml
if ! grep -q 'android.permission.NFC' "$M"; then
  perl -0pi -e 's#(<manifest[^>]*>)#$1\n    <uses-permission android:name="android.permission.NFC" />\n    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-feature android:name="android.hardware.nfc" android:required="false" />#' "$M"
  echo "✔ 已加入 Android NFC / INTERNET 权限"
fi

# ---------- iOS ----------
P=ios/Runner/Info.plist
if ! grep -q 'NFCReaderUsageDescription' "$P"; then
  perl -0pi -e 's#</dict>\s*</plist>\s*$#\t<key>NFCReaderUsageDescription</key>\n\t<string>用于扫描巡逻点 NFC 标签打卡</string>\n\t<key>com.apple.developer.nfc.readersession.iso7816.select-identifiers</key>\n\t<array>\n\t\t<string>D2760000850101</string>\n\t</array>\n</dict>\n</plist>\n#' "$P"
  echo "✔ 已加入 iOS NFC 说明"
fi

flutter pub get
echo
echo "完成！Android 手机插上电脑后运行：flutter run"
echo "iOS 还需在 Xcode 打开 ios/Runner.xcworkspace → Signing & Capabilities → + Near Field Communication Tag Reading"
