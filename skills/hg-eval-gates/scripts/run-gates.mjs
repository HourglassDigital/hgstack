#!/usr/bin/env node
// Runs the gates declared in evals.config.json. For every gate, `run` must pass
// AND its `must_fail` twin must fail, with the exit code the gate declares.
// A twin that stops failing means the gate can no longer catch anything.
//
//   node run-gates.mjs                 run every gate
//   node run-gates.mjs --gate <name>   run one gate (what CI does per matrix entry)
//   node run-gates.mjs --list          print gate names as JSON (CI plan step)
//   node run-gates.mjs --config <path> use another config file
//
// Exit codes: 0 every gate passed, 1 a gate broke, 2 config or usage error.
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";

const args = process.argv.slice(2);
const opt = (flag, fallback) => {
  const i = args.indexOf(flag);
  return i >= 0 ? args[i + 1] : fallback;
};
const die = (msg) => {
  console.error(msg);
  process.exit(2);
};

let config;
try {
  config = JSON.parse(readFileSync(opt("--config", "evals.config.json"), "utf8"));
} catch (e) {
  die(`cannot read the gates config: ${e.message}`);
}
let gates = config.gates ?? [];
if (!gates.length) die("no gates declared: a repo with zero gates must not report green");

if (args.includes("--list")) {
  console.log(JSON.stringify(gates.map((g) => g.name)));
  process.exit(0);
}
const only = opt("--gate");
if (only) gates = gates.filter((g) => g.name === only);
if (!gates.length) die(`no gate named ${only}`);

// pipefail so `cmd | tee log` cannot turn a failure into a pass.
const sh = (cmd) => spawnSync("bash", ["-o", "pipefail", "-c", cmd], { stdio: "inherit" }).status;

let broke = 0;
for (const g of gates) {
  if (!g.run || !g.must_fail) {
    console.error(`BROKE ${g.name}: every gate needs both "run" and "must_fail"`);
    broke++;
    continue;
  }
  const wanted = g.must_fail_exit ?? 1;
  console.log(`\n== ${g.name}: run`);
  const run = sh(g.run);
  console.log(`\n== ${g.name}: must_fail (supposed to go red with exit ${wanted})`);
  const twin = sh(g.must_fail);

  let verdict = "PASS";
  if (run !== 0) verdict = `BROKE: run exited ${run}`;
  else if (twin === 0) verdict = "BROKE: must_fail passed, so this gate is not biting";
  // 126/127 is a missing command, and any other code is a crash or usage error:
  // neither proves the gate can catch a real defect.
  else if (twin !== wanted) verdict = `BROKE: must_fail exited ${twin}, expected ${wanted} (a crash is not a red)`;
  if (verdict !== "PASS") broke++;
  console.log(`\n${g.name}: ${verdict}`);
}
console.log(broke ? `\nGATES FAIL (${broke} broke)` : "\nGATES PASS");
process.exit(broke ? 1 : 0);
