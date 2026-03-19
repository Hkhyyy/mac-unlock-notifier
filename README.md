# UnlockNotifier

A macOS menu bar app that detects screen unlock events, captures a photo using the built-in camera, and sends a push notification with the photo to your iPhone via [ntfy.sh](https://ntfy.sh).

## Features

- Detects Mac screen unlock events in real-time
- Captures a photo with the built-in camera (AVFoundation)
- Sends push notifications with photo attachment via ntfy.sh
- macOS menu bar app with status indicator (SF Symbols)
- GUI settings: ntfy topic, alert title/message (supports `{hostname}`, `{timestamp}` variables)
- Camera permission management from menu bar
- Test notification button
- Auto-starts on login via LaunchAgent (installed automatically on first launch)
- No external dependencies (no Homebrew packages required)

## Requirements

- macOS 13.0 or later
- Xcode Command Line Tools (`xcode-select --install`)
- [ntfy](https://ntfy.sh) app on iPhone (free)

## Install

### Option 1: Download DMG (Recommended)

1. Download `UnlockNotifier.dmg` from [Releases](../../releases)
2. Open the DMG and drag `UnlockNotifier.app` to `Applications`
3. Launch `UnlockNotifier` from Applications
4. Grant camera permission when prompted
5. Click the lock icon in the menu bar and set your ntfy topic
6. Subscribe to the same topic in the ntfy app on your iPhone

### Option 2: Build from source

```bash
git clone https://github.com/user/mac-unlock-notifier.git
cd mac-unlock-notifier
./build.sh
cp -R build/UnlockNotifier.app /Applications/
open /Applications/UnlockNotifier.app
```

## Menu Bar

| Icon | State |
|------|-------|
| 🛡️ (lock.shield) | Monitoring — all set |
| ⚠️ (lock.trianglebadge) | Setup required — camera or topic missing |
| 🔓 (lock.open) | Processing — capturing & sending |

Click the icon for:
- Status and last event time
- Camera permission management
- ntfy topic configuration
- Alert message customization
- Test notification
- Web dashboard link

## How It Works

1. `DistributedNotificationCenter` listens for `com.apple.screenIsUnlocked`
2. `AVFoundation` captures a photo from the built-in camera
3. Photo is uploaded to ntfy.sh, then a JSON notification is sent with the photo URL
4. Your iPhone receives a push notification with the photo attached

## Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.user.unlock-notifier.plist
rm ~/Library/LaunchAgents/com.user.unlock-notifier.plist
rm -rf /Applications/UnlockNotifier.app
```

## License

[MIT](LICENSE)
