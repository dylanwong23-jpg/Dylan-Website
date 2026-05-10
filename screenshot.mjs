// Puppeteer screenshot script with scroll + wait support
// Usage: node screenshot.mjs <url> [label] [scrollPx]
import puppeteer from 'puppeteer';
import { mkdir, readdir } from 'fs/promises';
import { existsSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const CHROME_CANDIDATES = [
  'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
  'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
];
const executablePath = CHROME_CANDIDATES.find(p => existsSync(p));

const __dirname = dirname(fileURLToPath(import.meta.url));
const url = process.argv[2] || 'http://localhost:3000';
const label = process.argv[3] || '';
const scrollPx = parseInt(process.argv[4] || '0', 10);

const OUT_DIR = join(__dirname, 'temporary screenshots');
await mkdir(OUT_DIR, { recursive: true });

const existing = await readdir(OUT_DIR).catch(() => []);
let n = 1;
for (const f of existing) {
  const m = f.match(/^screenshot-(\d+)/);
  if (m) n = Math.max(n, parseInt(m[1], 10) + 1);
}

const finalName = `screenshot-${n}${label ? '-' + label : ''}.png`;
const finalPath = join(OUT_DIR, finalName);

const browser = await puppeteer.launch({
  headless: 'new',
  executablePath,
  args: ['--no-sandbox', '--disable-dev-shm-usage'],
  defaultViewport: { width: 1440, height: 900, deviceScaleFactor: 1 },
});

try {
  const page = await browser.newPage();
  console.log('Capturing:', url, scrollPx ? `(scroll ${scrollPx}px)` : '');
  await page.goto(url, { waitUntil: 'networkidle2', timeout: 60000 });

  // Wait for the loader to disappear (if present)
  await page.waitForFunction(
    () => {
      const el = document.getElementById('loader');
      return !el || el.classList.contains('gone');
    },
    { timeout: 60000 }
  ).catch(() => console.log('loader wait timed out — continuing'));

  if (scrollPx > 0) {
    await page.evaluate((y) => window.scrollTo(0, y), scrollPx);
    // wait for reveals & frame draw
    await new Promise(r => setTimeout(r, 800));
  }

  await page.screenshot({ path: finalPath, fullPage: false });
  console.log('Saved:', finalPath);
} finally {
  await browser.close();
}
