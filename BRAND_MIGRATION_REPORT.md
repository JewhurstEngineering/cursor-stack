# Brand migration report

CursorStack stays CursorStack. The maker identity is Jewhurst Engineering. The bundle id is `dev.jewhurst.CursorStack`.

## References found

### Active public branding

- The README title used to prefix the product with the retired maker name. It is now `# CursorStack`.
- About credits, Settings, the site footer, the 404 page, and structured data had no maker line. Copyright read `Copyright © 2026 James Jewhurst`.

### Historical content

- `CursorStack-PRD.md` example windows and groups now use Workbench and `jewhurst.dev`.

### Identifiers

- Bundle ids are `dev.jewhurst.CursorStack` and `dev.jewhurst.CursorStackTests`.
- The logger subsystem and composer queue label use that same bundle id.
- Apple signing identities still name James Jewhurst, because that is the certificate subject.
- Parser fixtures use ordinary project names such as `ai-meter`.

### URLs

- Product site, canonicals, and Open Graph stay on `https://cursorstack.app/`.
- Downloads and the Sparkle feed stay on `https://github.com/JewhurstEngineering/cursor-stack`.

### Assets

- Logos, app icon, favicon, and screenshots say CursorStack.

### Generated or vendor content

- None.

## Changed

- `README.md` title is `# CursorStack`, with `Built by Jewhurst Engineering` linking to the GitHub organization.
- `NSHumanReadableCopyright` in `project.yml` and `CursorStack/Info.plist` is `Copyright © 2026 Jewhurst Engineering`.
- About credits keep “Groups Cursor windows into a tabbed stack.” and add “Built by Jewhurst Engineering.”
- Settings → Updates shows the same maker line under the version row.
- `docs/index.html` footer and `docs/404.html` use the same line, linked to `https://github.com/JewhurstEngineering`.
- JSON-LD `author` is an Organization named Jewhurst Engineering, with that same URL.
- The bundle id, log subsystem, queue label, and tests moved to `dev.jewhurst.CursorStack`.

## Intentionally unchanged

- Product name, signing identities, Sparkle feed, and repository slug.
- `cursorstack.app` as the live product site. Downloads, canonicals, and the update feed were not moved.
- Saved groups and settings, which live in `~/Library/Application Support/CursorStack/` rather than under the bundle id.

## Redirect dependencies

`https://jewhurst.dev/cursor-stack` is the intended workshop page and is not the live product URL yet. Maker links point at `https://github.com/JewhurstEngineering` until that page exists.

## Assets still needed

None for this repo.

## Verification performed

`xcodebuild test -scheme CursorStack -destination 'platform=macOS'` completed with exit code 0 on September 28, 2026. The 404 page and the home-page footer were rendered in headless Chrome. The footer reads “Built by Jewhurst Engineering,” and the three download links still target `CursorStack-1.0.11.zip` on GitHub Releases.

## Manual QA

Confirmed in the rendered site: the home footer and the 404 page show “Built by Jewhurst Engineering,” and the download buttons still point at the 1.0.11 zip.

Not opened in the running app: About CursorStack should show the existing description plus “Built by Jewhurst Engineering,” and the copyright line should read Jewhurst Engineering. Settings → Updates should show that same caption under the version row.
