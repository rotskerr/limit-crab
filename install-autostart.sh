#!/bin/bash
# Автозапуск при вході в систему (LaunchAgent)
P=~/Library/LaunchAgents/local.claude.limits.plist
mkdir -p ~/Library/LaunchAgents
cat > "$P" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>local.claude.limits</string>
<key>ProgramArguments</key><array><string>$HOME/Applications/Claude Limits.app/Contents/MacOS/ClaudeLimits</string></array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><false/>
</dict></plist>
PLIST
launchctl bootout gui/$(id -u)/local.claude.limits 2>/dev/null || true
launchctl bootstrap gui/$(id -u) "$P"
echo "Автозапуск увімкнено"
