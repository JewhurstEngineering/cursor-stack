# CursorStack

<p align="center">
  <img src="images/cursorstack-logo-full-color.png" alt="CursorStack" width="520">
</p>

Native macOS utility that groups Cursor windows into a logical tabbed stack. It does **not** embed Cursor. It aligns real Cursor windows beneath a dedicated tab strip.

This app is **not App Sandboxed**. Accessibility window control cannot run inside Apple App Sandbox. Ship it as a signed, notarized direct download — not the Mac App Store.

## Requirements

- macOS 14+
- Xcode 26+
- Accessibility permission
- Optional: Notifications
- Optional: Screen Recording for experimental visual attention detection

## Build

```bash
cd /path/to/cursor-stack
xcodegen generate
open CursorStack.xcodeproj
```

Or:

```bash
./scripts/release.sh Debug
open build/Build/Products/Debug/CursorStack.app
```

Release (local, hardened runtime, still unsandboxed):

```bash
chmod +x scripts/release.sh
./scripts/release.sh Release
```

Notarization needs your Developer ID and a `notarytool` keychain profile. The script prints the exact commands.

## First launch

1. Run CursorStack and grant Accessibility.
2. Open several Cursor project windows.
3. Create a group from the menu bar icon or the picker.
4. The tab strip sits above Cursor’s native titlebar (quit / minimize / fill-screen, tabs, Add, and Settings), so Cursor’s search field remains usable. Clicking another app hides it like a normal window. The red close button quits CursorStack; Cursor windows stay open.

**Settings** is under CursorStack → Settings… (`⌘,`), or the menu bar icon → Settings…. General includes installation in Applications, launch at login, the menu bar icon, and the Dock icon. Other tabs cover tab height, shortcuts, and attention.

## Shortcuts

These global shortcuts can be changed under **Settings → Shortcuts**. CursorStack warns about duplicate assignments and common macOS conflicts.

- `⌃⌥ ]` next tab
- `⌃⌥ [` previous tab
- `⌃⌥ 1`–`9` jump to tab

## Notes

- Groups persist in `~/Library/Application Support/CursorStack/`
- Green traffic light fills the current display work area (not a macOS Space)
- Drag a tab onto another group’s tab strip to move it
- Dashed tabs are saved windows that need **Reconnect** after Cursor restarts
- Attention is best-effort (Accessibility, then titles, then optional visual capture)
- Nothing is uploaded. No account.
