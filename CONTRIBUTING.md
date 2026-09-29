# Contributing to CursorStack

CursorStack is a native macOS app. It lines real Cursor windows up under one tab strip. It does not embed Cursor, and it is not sandboxed, because a sandboxed app cannot move another app’s windows.

Issues and pull requests are welcome. There is no CI. A change is ready when it builds with your own signing team and the unit tests pass.

## What you need

- macOS 14 or newer
- An Apple silicon Mac
- Xcode 26 or newer
- An Apple ID that can sign a local Mac app (a free Personal Team is enough for Debug)

Cursor itself is only needed when you want to try the tab strip against real windows. The unit tests do not launch Cursor.

## Build locally

The committed Xcode project is the one to open. Do not run `xcodegen` or `./scripts/release.sh` for a normal change. Both rewrite the project with the maintainer’s signing certificate, which you will not have.

```bash
git clone https://github.com/JewhurstEngineering/cursor-stack.git
cd cursor-stack
open CursorStack.xcodeproj
```

In Xcode, select the CursorStack target, open Signing & Capabilities, and set the team to yours. Leave that change uncommitted. `project.yml` and `project.pbxproj` pin a specific Developer ID, and a pull request should not replace it with someone else’s team.

Then build and run the `CursorStack` scheme.

On first launch, grant Accessibility when macOS asks. Without it, CursorStack cannot discover or move windows. Screen Recording is optional and only used by the experimental attention check.

## Tests

From Xcode, run the `CursorStack` scheme’s tests. From the command line, after your team is selected in the project:

```bash
xcodebuild test -project CursorStack.xcodeproj -scheme CursorStack -destination 'platform=macOS'
```

Logic that does not need a live Cursor window belongs in `CursorStackTests/CursorStackLogicTests.swift`. If a test only passes because a window title or bundle id was edited to match your machine, it is not a useful test.

## Where things live

| Path | What it is |
| --- | --- |
| `CursorStack/App` | Launch, menus, settings storage |
| `CursorStack/Discovery` | Finding Cursor windows |
| `CursorStack/Accessibility` | Moving, resizing, and reading those windows |
| `CursorStack/WindowManagement` | Stacks, focus, and frames |
| `CursorStack/Attention` | Running, finished, and waiting marks |
| `CursorStack/UI` | Tab strip, settings, onboarding |
| `CursorStack/Persistence` | Saved groups |
| `docs/` | The cursorstack.app site (static HTML) |
| `project.yml` | XcodeGen spec. Maintainers regenerate the project from this. |

`CursorStack-PRD.md` is the original design notes. It is not the current behavior spec.

## Pull requests

Branch from `master` and open a pull request against `master`.

In the description, say what changed and how you checked it. A screenshot or a short screen recording helps for tab-strip, menu, or settings changes.

Please leave these alone unless the change cannot work without them:

- The bundle id `dev.jewhurst.CursorStack`. Renaming it again would drop the Accessibility grant and make Sparkle treat the app as a different install.
- Signing identities, the notary profile, and the Sparkle private key. Those stay on the maintainer’s machine. They are not in git.
- Version numbers and `appcast.xml`. Releases are cut with `./scripts/release.sh Release`.

Do not commit `build/` or `artifacts/`.

## Site changes

The marketing site is the `docs/` folder. Edit `docs/index.html` and check it in a browser, including the 404 page if you touched shared wording. Publishing notes for the domain owner are in `docs/HOSTING.md`.

## Maintainer releases

Signing, notarizing, and the update feed are documented in the README under “Build from source.” That path is for the person with the Developer ID certificate and the Sparkle key. Contributors do not need it to propose a change.
