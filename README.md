# CursorStack

Native macOS utility that groups Cursor windows into a logical tabbed stack. It does **not** embed Cursor; it aligns real Cursor windows and overlays a small tab strip.

This app is **not App Sandboxed**. Window control uses Accessibility APIs that cannot control another app from inside Apple's App Sandbox. Distribution is intended as a signed, notarized direct download later — not the Mac App Store.

## Requirements

- macOS 14+
- Xcode 26+ (or current Xcode with macOS 14 SDK)
- Accessibility permission for CursorStack
- Optional: Screen Recording permission for experimental visual attention detection
- Optional: Notifications permission for inactive-project alerts

## Generate and build

```bash
cd /path/to/cursor-stack
xcodegen generate
xcodebuild -scheme CursorStack -configuration Debug -derivedDataPath build
open build/Build/Products/Debug/CursorStack.app
```

Or open `CursorStack.xcodeproj` in Xcode and run.

## First launch

1. Launch CursorStack.
2. Grant Accessibility when prompted (Privacy & Security → Accessibility).
3. Open a few Cursor project windows.
4. Use **Manage Windows…** from the menu bar `CS` item to create a group.

The Window Lab (menu bar → Window Lab, or Settings → Advanced) is the original proof-of-concept: list windows, Stack All, Focus 1/2/3.

## Permissions

| Permission | Why |
|---|---|
| Accessibility | Discover, move, resize, and raise Cursor windows |
| Notifications | Optional alerts when a background tab needs attention |
| Screen Recording | Only if you enable experimental visual badge detection |

Nothing is uploaded. There is no account or network requirement.

## Shortcuts

- `⌃⌥ ]` next tab
- `⌃⌥ [` previous tab
- `⌃⌥ 1`–`9` jump to tab

## Notes

- Groups persist in `~/Library/Application Support/CursorStack/`
- Native full-screen Spaces are not synchronized; use **Maximize Group** instead
- Attention detection is best-effort: Accessibility first, window title metadata second, visual capture last and experimental
