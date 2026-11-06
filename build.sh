#!/bin/bash
# Збирає Claude Limits.app і ставить в ~/Applications
set -e
cd "$(dirname "$0")"
APP="build/Claude Limits.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS"
swiftc -O src/main.swift -o "$APP/Contents/MacOS/ClaudeLimits"
cp resources/Info.plist "$APP/Contents/Info.plist"
# Підпис без сертифіката, але зі стабільною вимогою: дозвіл «Універсальний доступ» не злітає після перезбірки.
codesign --force --sign - --identifier local.claude.limits -r='designated => identifier "local.claude.limits"' "$APP"
mkdir -p ~/Applications && rm -rf ~/Applications/"Claude Limits.app" && cp -R "$APP" ~/Applications/
echo "Готово: ~/Applications/Claude Limits.app"
