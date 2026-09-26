# Publish cursorstack.app

The site is the `docs/` folder in this repo. GitHub Pages serves that folder. The Mac app is unchanged.

## GitHub Pages

1. Push `main`.
2. Open the repo on GitHub → Settings → Pages.
3. Build and deployment: Deploy from a branch.
4. Branch: `main`, folder: `/docs`. Save.
5. After DNS is resolving, turn on Enforce HTTPS.

`docs/CNAME` already contains `cursorstack.app`. `docs/.nojekyll` keeps Pages from running the folder through Jekyll.

## DNS at the registrar

Apex domain `cursorstack.app`:

| Type | Value |
|------|--------|
| A | `185.199.108.153` |
| A | `185.199.109.153` |
| A | `185.199.110.153` |
| A | `185.199.111.153` |
| AAAA | `2606:50c0:8000::153` |
| AAAA | `2606:50c0:8001::153` |
| AAAA | `2606:50c0:8002::153` |
| AAAA | `2606:50c0:8003::153` |

`www` is a CNAME to `jewhurstengineering.github.io`.

The certificate for the custom domain shows up after DNS has propagated. That can take a while.
