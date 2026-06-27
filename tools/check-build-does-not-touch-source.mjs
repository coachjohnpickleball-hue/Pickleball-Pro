import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";

const protectedFiles = [
  "public/index.html",
  "build.js",
  "package.json"
];

function sha(file) {
  if (!existsSync(file)) return "MISSING";
  return createHash("sha256").update(readFileSync(file)).digest("hex");
}

const before = Object.fromEntries(protectedFiles.map(file => [file, sha(file)]));

execFileSync("npm", ["run", "build"], { stdio: "inherit" });

const after = Object.fromEntries(protectedFiles.map(file => [file, sha(file)]));

const changed = protectedFiles.filter(file => before[file] !== after[file]);

if (changed.length) {
  console.error("");
  console.error("❌ Build modified protected source files:");
  for (const file of changed) console.error(" - " + file);
  console.error("");
  console.error("This is blocked because source mutation broke buttons before.");
  process.exit(1);
}

console.log("");
console.log("✅ Build completed without modifying protected source files.");
