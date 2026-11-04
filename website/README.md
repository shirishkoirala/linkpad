# Linkpad landing page

The static site is published at https://shirishkoirala.github.io/linkpad/ by `.github/workflows/pages.yml`.

Build and preview from the repository root:

```sh
python3 website/build.py
python3 -m http.server 8080 --directory bin/site
```

Open http://localhost:8080. HTML, CSS and JavaScript require no package installation. Fonts are self-hosted; their OFL licenses are included in `fonts/`.

Deployment runs when site sources change on `master`, when a public release is published, or when manually dispatched. It reads the latest public GitHub release and generates download metadata. Local previews use `website/release.json` as the fallback. Images are copied from the existing release assets during staging.

The mobile installation button currently links to the support page. Replace it with verified public store links when available. Keep platform requirements and signing guidance aligned with published installers.
