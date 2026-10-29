// Renders tools/readme-art.html into docs/assets/readme/*.png (2x) for README.md.
// Needs playwright-core and a Chromium:  npm i --no-save playwright-core
//   CHROME=/path/to/chrome-headless-shell node tools/render-readme-images.cjs
// Requests are answered from disk, so no server is started.
const { chromium } = require("playwright-core");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "../..");
const out = path.join(root, "docs/assets/readme");
const origin = "https://cofre.local/";

(async () => {
  const sprite = fs.readFileSync(path.join(root, "docs/index.html"), "utf8").match(/<symbol[\s\S]*<\/symbol>/)[0];
  const html = fs.readFileSync(path.join(__dirname, "readme-art.html"), "utf8").replace("<!--SPRITE-->", sprite);

  const browser = await chromium.launch({ executablePath: process.env.CHROME });
  const page = await browser.newPage({ deviceScaleFactor: 2, viewport: { width: 920, height: 900 } });
  await page.route("**/*", (route) => {
    const url = new URL(route.request().url());
    if (url.origin + "/" !== origin) return route.abort();
    if (url.pathname === "/tools/readme-art.html") return route.fulfill({ body: html, contentType: "text/html" });
    route.fulfill({ path: path.join(root, decodeURIComponent(url.pathname)) });
  });
  await page.goto(origin + "tools/readme-art.html");
  await page.evaluate(() => document.fonts.ready);

  fs.mkdirSync(out, { recursive: true });
  for (const el of await page.$$("[data-shot]")) {
    const name = await el.getAttribute("data-shot");
    await el.screenshot({ path: path.join(out, `${name}.png`), omitBackground: true });
    console.log(name);
  }
  await browser.close();
})();
