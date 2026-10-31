// NODE_PATH must point to an installed Playwright package directory.
// Run from the repository root: node mobile/tool/export_store_panels.cjs
const {chromium} = require('playwright');
const path = require('node:path');
const fs = require('node:fs/promises');
const {pathToFileURL} = require('node:url');

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
  });
  try {
    const root = path.resolve('assets/release');
    for (const profile of ['android', 'iOS', 'iOS-medium']) {
      const ios = profile !== 'android';
      const medium = profile === 'iOS-medium';
      const platform = ios ? 'iOS' : 'android';
      const viewport = {width: medium ? 1608 : ios ? 1720 : 1440, height: medium ? 874 : ios ? 932 : 640};
      const page = await browser.newPage({
        viewport,
        deviceScaleFactor: 3,
      });
      const url = pathToFileURL(path.join(root, 'store-panels.html'));
      url.searchParams.set('platform', platform);
      if (medium) url.searchParams.set('size', 'medium');
      await page.goto(url.href);
      await page.evaluate(async () => {
        await document.fonts.ready;
        await Promise.all([...document.images].map(img => img.decode()));
      });
      const out = path.join(root, 'store-screenshots', profile);
      await fs.mkdir(out, {recursive: true});
      for (const screen of ['touchpad', 'remote', 'keyboard', 'settings']) {
        await page.locator(`[data-screen="${screen}"]`).screenshot({path: path.join(out, `${screen}.png`)});
      }
      await page.close();
      const preview = await browser.newPage({viewport, deviceScaleFactor: 1});
      await preview.goto(url.href);
      await preview.evaluate(async () => {await Promise.all([...document.images].map(img => img.decode()));});
      await preview.screenshot({path: path.join(out, 'overview.png')});
      await preview.close();
    }
    const header = await browser.newPage({viewport: {width: 3840, height: 1646}, deviceScaleFactor: 1});
    await header.goto(pathToFileURL(path.join(root, 'app-store-header.html')).href);
    await header.evaluate(async () => {
      await document.fonts.ready;
      await Promise.all([...document.images].map(img => img.decode()));
    });
    await header.screenshot({path: path.join(root, 'app-store-header-3840x1646.png')});
    await header.close();
    const search = await browser.newPage({viewport: {width: 1920, height: 1280}, deviceScaleFactor: 1});
    const searchUrl = pathToFileURL(path.join(root, 'app-store-header.html'));
    searchUrl.searchParams.set('variant', 'search');
    await search.goto(searchUrl.href);
    await search.evaluate(async () => {
      await document.fonts.ready;
      await Promise.all([...document.images].map(img => img.decode()));
    });
    await search.screenshot({path: path.join(root, 'app-store-search-1920x1280.png')});
    await search.close();
  } finally {
    await browser.close();
  }
})().catch(error => {console.error(error);process.exitCode = 1;});
