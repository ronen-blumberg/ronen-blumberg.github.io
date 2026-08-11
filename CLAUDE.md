# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Ronen Blumberg's personal retro-themed GitHub Pages site ("Ronen Blumberg Retro Games Website World"): DOS games emulated in the browser, Emscripten web games, a Jekyll blog, video archive, chat/forum/guestbook pages. Deployed as a user site at `https://ronen-blumberg.github.io/` (repo `ronen-blumberg/ronen-blumberg.github.io`). It previously lived at `ronblue77/Retro-Dev-Ronen.github.io` under the site name "Retro Dev Ronen" — that account and repo were deleted, and this is the recreation.

There is no build step, package.json, linter, or test suite in this repo. Deploying = `git push` to `main` (remote `origin` is the GitHub repo); GitHub Pages runs its legacy Jekyll build automatically, usually live within a minute. Check build status with `gh api repos/ronen-blumberg/ronen-blumberg.github.io/pages/builds/latest`. To preview the Jekyll parts locally: `jekyll serve` (needs the `jekyll-paginate` plugin); the plain HTML pages can be opened directly or served with any static server.

## Absolute paths assume site root

`_config.yml` sets `baseurl: ""` (user site, served at domain root). The standalone HTML pages use root-absolute paths like `/games/HIKIKO.zip` in links and js-dos `fs.extract()` calls, so local preview must serve the repo at `/` (e.g. `python3 -m http.server` from the repo root), not under a subpath.

## Architecture

Two kinds of pages coexist:

1. **Jekyll-processed** (front matter): `_posts/*.md` (blog posts, `layout: post`), `blog/index.html` (paginated listing via `jekyll-paginate`, 10/page), and the two layouts in `_layouts/`. `default.html` carries the whole site theme — DOS blue (#000084) background, CRT flicker/scanline/text-shadow animations, `C:\>`-style section labels, `.retro-text`/`.retro-content` classes.

2. **Standalone HTML** (everything else at the repo root): each page is fully self-contained with its own copy of the CRT/DOS CSS inlined — there is no shared stylesheet. Consistency across pages is maintained by copy-paste; when changing the theme, remember it lives in both `_layouts/default.html` and every standalone page.

### Game page pattern

Each game has a pair of files at the root:
- `<name>-game-desc.html` — description/landing page with screenshot (from `images/`) and a launch button.
- `<name>-game.html` — the player page. DOS games load js-dos 6.22 from the js-dos.com CDN, `fs.extract()` a zip from `games/` (8.3-style names, e.g. `HIKIKO.zip`), then run the game's `START.BAT` inside DOSBox.

Adding a DOS game means: drop the zip in `games/`, add a screenshot in `images/`, create the desc/player HTML pair (copy an existing pair, e.g. `game1.html`/`game1-desc.html`), and link it from `index.html`.

### Web games (`webgames/`)

Emscripten-compiled artifacts (`*.html`/`*.js`/`*.wasm`/`*.data`) committed directly; the source code is not in this repo — it lives in the surrounding `~/dos` FreeBASIC projects (the `vt` FreeBASIC library in `/usr/local/include/freebasic/vt` is part of that toolchain). Don't hand-edit the generated `.js`/`.wasm`; rebuild and re-copy instead.

### Other directories

- `archive/` — retired pages and old posts, kept but unlinked/superseded.
- `demos/` — downloadable zips (e.g. MATRIX demo).
- Every page includes the same Google Analytics gtag snippet (`G-PQ0YJSFWPZ`); keep it when creating new pages.

## Third-party integrations

- **Forum** (`forum.html`) — giscus, backed by this repo's GitHub Discussions ("General" category). The `data-repo-id`/`data-category-id` values are specific to this repo; if the forum shows an error, first check the giscus app (github.com/apps/giscus) is installed on the repo. Forum posts from the pre-2026 site were lost with the old repo's Discussions.
- **Guestbook** (Bravenet) and **Flag Counter** on `index.html` — tied to their own external accounts, independent of GitHub; leave their embed URLs alone.
- `_posts/2024-11-26-my-first-post.md` intentionally still says "Retro Dev Ronen" — it is historical writing from the old site; don't rename it during retitling sweeps.
