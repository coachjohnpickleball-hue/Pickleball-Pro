import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(process.cwd(), '..');
const workerDir = process.cwd();
const failures = [];
const pass = [];

function assert(condition, message) {
  if (condition) pass.push(message);
  else failures.push(message);
}

const wranglerPath = path.join(workerDir, 'wrangler.toml');
const indexPath = path.join(workerDir, 'src', 'index.js');
const appPath = path.join(workerDir, 'src', 'app.html');
const standingsPath = path.join(workerDir, 'src', 'standings.js');

const wrangler = fs.existsSync(wranglerPath) ? fs.readFileSync(wranglerPath, 'utf8') : '';
const index = fs.existsSync(indexPath) ? fs.readFileSync(indexPath, 'utf8') : '';
const app = fs.existsSync(appPath) ? fs.readFileSync(appPath, 'utf8') : '';

assert(fs.existsSync(wranglerPath), 'wrangler.toml exists');
assert(fs.existsSync(indexPath), 'src/index.js exists');
assert(fs.existsSync(appPath), 'src/app.html exists');
assert(fs.existsSync(standingsPath), 'src/standings.js exists');
assert(/\[env\.rally\]/.test(wrangler), 'wrangler.toml includes [env.rally]');
assert(/name\s*=\s*"rally"/.test(wrangler), 'rally environment deploys to Worker name rally');
assert(/\[env\.staging\]/.test(wrangler), 'wrangler.toml includes [env.staging]');
assert(/name\s*=\s*"rally-staging"/.test(wrangler), 'staging environment deploys to Worker name rally-staging');
assert(/path === '\/health'/.test(index), 'Worker exposes /health');
assert(/path === '\/admin\/tos-status'/.test(index), 'Worker exposes /admin/tos-status');
assert(/\/admin\/access-log/.test(index), 'Worker exposes /admin/access-log');
assert(/ENFORCE_TOS_ACCEPTANCE\s*=\s*true/.test(index), 'Terms acceptance enforcement is enabled');
assert(/Accept & Continue/.test(index), 'Terms gate has Accept & Continue flow');
assert(/Access Log/.test(app), 'App includes Access Log shortcut');

const onclicks = [...app.matchAll(/onclick="([^"]+)"/g)].map(m => m[1]);
const functionNames = new Set([...app.matchAll(/function\s+([A-Za-z_$][\w$]*)\s*\(/g)].map(m => m[1]));
const assignedWindowFns = new Set([...app.matchAll(/window\.([A-Za-z_$][\w$]*)\s*=\s*/g)].map(m => m[1]));
const missing = [];
for (const handler of onclicks) {
  const m = handler.trim().match(/^([A-Za-z_$][\w$]*)\s*\(/);
  if (!m) continue;
  const name = m[1];
  if (['alert','confirm','prompt'].includes(name)) continue;
  if (!functionNames.has(name) && !assignedWindowFns.has(name)) missing.push(`${name} from onclick="${handler}"`);
}
assert(missing.length === 0, missing.length ? `Missing onclick handlers: ${missing.slice(0, 12).join('; ')}` : 'All direct onclick handlers are defined');

console.log('\nPickleball Pro smoke test');
for (const item of pass) console.log(`✓ ${item}`);
if (failures.length) {
  console.error('\nFailures:');
  for (const item of failures) console.error(`✘ ${item}`);
  process.exit(1);
}
console.log('\nAll smoke checks passed.');
