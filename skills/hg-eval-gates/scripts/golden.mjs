#!/usr/bin/env node
// Golden evals: run your system on questions you already know the answers to.
//
//   node golden.mjs --cases goldens.jsonl --cmd "<command>" [--report out.json]
//
// Each case's `input` is sent to <command> on stdin (objects as JSON); stdout is
// the answer. Lines starting with // are comments. An optional header line
//   {"_kind":"gates","gates":{"<family>":{"floor":0.9}}}
// sets a pass-rate floor per family (default 1.0).
//
// A case:
//   {"id":"refund-window","family":"policy","input":"How long do refunds take?",
//    "expect":{"contains":"14 days"}, "known_failing":"optional reason"}
// expect keys (all given must hold): equals, contains, not_contains, regex.
//
// The gate fails when a family drops below its floor, when any case errors,
// or when a known_failing case starts passing (remove the marker so the fix is
// guarded from now on). Exit codes: 0 pass, 1 gate breach, 2 usage error.
import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";

const args = process.argv.slice(2);
const opt = (flag) => {
  const i = args.indexOf(flag);
  return i >= 0 ? args[i + 1] : undefined;
};
const casesPath = opt("--cases");
const cmd = opt("--cmd");
const timeout = Number(opt("--timeout") ?? 60) * 1000;
if (!casesPath || !cmd) {
  console.error('usage: golden.mjs --cases <file.jsonl> --cmd "<command>" [--report <out.json>] [--timeout <s>]');
  process.exit(2);
}

let floors = {};
const cases = [];
try {
  for (const raw of readFileSync(casesPath, "utf8").split("\n")) {
    const line = raw.trim();
    if (!line || line.startsWith("//")) continue;
    const row = JSON.parse(line);
    if (row._kind === "gates") floors = row.gates ?? {};
    else cases.push(row);
  }
} catch (e) {
  console.error(`cannot read cases: ${e.message}`);
  process.exit(2);
}
if (!cases.length) {
  console.error("no cases: an empty golden set proves nothing");
  process.exit(2);
}

const check = (out, expect = {}) => {
  if ("equals" in expect && out !== String(expect.equals)) return `expected exactly ${JSON.stringify(expect.equals)}`;
  if ("contains" in expect && !out.includes(expect.contains)) return `missing ${JSON.stringify(expect.contains)}`;
  if ("not_contains" in expect && out.includes(expect.not_contains)) return `must not contain ${JSON.stringify(expect.not_contains)}`;
  if ("regex" in expect && !new RegExp(expect.regex).test(out)) return `no match for /${expect.regex}/`;
  return null;
};

const results = cases.map((c) => {
  const input = typeof c.input === "string" ? c.input : JSON.stringify(c.input);
  const p = spawnSync("bash", ["-o", "pipefail", "-c", cmd], { input, encoding: "utf8", timeout });
  const out = (p.stdout ?? "").trim();
  const error = p.error ? p.error.message : p.status !== 0 ? `command exited ${p.status}: ${(p.stderr ?? "").trim().slice(0, 200)}` : null;
  const why = error ?? check(out, c.expect);
  return { id: c.id, family: c.family ?? "default", passed: !why, why, known: c.known_failing ?? null, output: out.slice(0, 500) };
});

const breaches = [];
const families = {};
for (const r of results) {
  const f = (families[r.family] ??= { n: 0, passed: 0, known: 0 });
  f.n++;
  if (r.passed) f.passed++;
  if (r.known) f.known++;
  if (r.why?.startsWith("command exited") || r.why?.includes("ETIMEDOUT")) breaches.push(`ERROR ${r.id}: ${r.why}`);
  if (r.known && r.passed) breaches.push(`FIXED, NOW UNGUARDED ${r.id} is marked known_failing but passed. Remove the marker so the gate holds the new behaviour.`);
}

console.log("family              n   passed  known-fail  floor  verdict");
for (const [name, f] of Object.entries(families)) {
  const floor = floors[name]?.floor ?? 1.0;
  // Known failures are tracked, not counted against the floor: the floor guards what works today.
  const guarded = f.n - f.known;
  const rate = guarded ? results.filter((r) => r.family === name && !r.known && r.passed).length / guarded : 1;
  const ok = rate >= floor;
  if (!ok) breaches.push(`GATE BREACH ${name} = ${rate.toFixed(2)} (floor ${floor.toFixed(2)})`);
  console.log(`${name.padEnd(18)} ${String(f.n).padStart(3)}  ${String(f.passed).padStart(7)}  ${String(f.known).padStart(10)}  ${floor.toFixed(2)}  ${ok ? "pass" : "FAIL"}`);
}
for (const r of results.filter((r) => !r.passed && !r.known)) console.log(`  failed ${r.id}: ${r.why}`);
for (const b of breaches) console.log(b);
console.log(breaches.length ? "GATES FAIL" : "GATES PASS");

const report = opt("--report");
if (report) writeFileSync(report, JSON.stringify({ families, results, breaches }, null, 1));
process.exit(breaches.length ? 1 : 0);
