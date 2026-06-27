const fs = require("fs");
const path = require("path");

const files = [
  "dist/index.html",
  "worker/src/app.html",
];

function stripOldGlobalTimer(filePath) {
  if (!fs.existsSync(filePath)) {
    console.log(`Missing: ${filePath}`);
    return;
  }

  const before = fs.readFileSync(filePath, "utf8");
  const lines = before.split(/(\n)/);

  const rebuiltLines = [];
  let skipping = false;
  let depth = 0;

  for (let i = 0; i < lines.length; i += 2) {
    const line = lines[i] || "";
    const nl = lines[i + 1] || "";
    const fullLine = line + nl;

    if (!skipping && /<div\s+id=["']global-round-timer["']/i.test(fullLine)) {
      skipping = true;
      depth = (fullLine.match(/<div\b/gi) || []).length - (fullLine.match(/<\/div>/gi) || []).length;

      if (depth <= 0) {
        skipping = false;
      }

      continue;
    }

    if (skipping) {
      depth += (fullLine.match(/<div\b/gi) || []).length - (fullLine.match(/<\/div>/gi) || []).length;

      if (depth <= 0) {
        skipping = false;
      }

      continue;
    }

    if (/#global-round-timer/i.test(fullLine)) continue;
    if (/global-timer-menu-toggle/i.test(fullLine)) continue;

    rebuiltLines.push(fullLine);
  }

  const after = rebuiltLines.join("");

  fs.writeFileSync(filePath, after);

  console.log(`${filePath}: changed=${after !== before}`);
  console.log(`  global-round-timer count: ${(after.match(/global-round-timer/gi) || []).length}`);
  console.log(`  #global-round-timer count: ${(after.match(/#global-round-timer/gi) || []).length}`);
  console.log(`  visible div count: ${(after.match(/<div\s+id=["']global-round-timer["']/gi) || []).length}`);
}

for (const f of files) {
  stripOldGlobalTimer(path.resolve(f));
}
