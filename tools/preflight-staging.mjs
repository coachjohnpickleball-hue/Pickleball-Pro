import { execFileSync } from "node:child_process";

function run(label, cmd, args) {
  console.log("");
  console.log("▶ " + label);
  execFileSync(cmd, args, { stdio: "inherit" });
}

run("Build safety guard", "npm", ["run", "safety:build-source"]);
run("Unit tests", "npm", ["test"]);
run("Worker smoke check", "npm", ["run", "worker:check"]);

console.log("");
console.log("✅ Preflight passed. Safe to deploy staging.");
