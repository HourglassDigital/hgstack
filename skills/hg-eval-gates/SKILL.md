---
name: hg-eval-gates
harnesses: [claude, codex]
portability: cli-now
portability-evidence: "Node runner, GitHub Actions template and gh script; nothing harness-specific."
description: >
  Set up the Hourglass merge gate in any GitHub repo: golden evals, a deliberately
  broken twin for every check, one required gate-verdict check and auto-merge, so a
  change lands only when the evals pass and no human has to review it. Use when a
  repo is moving from "someone eyeballs the PR" to machine-checked merges, or when
  AI agents are writing most of the code. Trigger phrases include "set up eval gates",
  "golden evals", "merge without code review", "must-fail twin", "make the evals block merges".
argument-hint: "[owner/repo]"
---

# Eval gates

Wire a repo so every pull request is marked against checks that can block the merge, each check proves it can fail, and a green verdict auto-merges with zero human approvals. Done means: `evals.config.json` declares at least one gate with a working `must_fail` twin, `node .hg-gates/run-gates.mjs` passes locally, the `gates` workflow reports `gate-verdict` on a PR, branch protection requires it, and a deliberately broken PR has been shown to go red and stay unmergeable.

## Invariants

- **Only deterministic checks block a merge.** Model-in-the-loop evals vary run to run, so a blocking one either flakes the team into ignoring red or gets its threshold loosened until it catches nothing. Run those nightly and report them; never make them required.
- **Every gate has a twin that must fail.** A check that cannot fail proves nothing, and silent rot (skipped tests, a stubbed model, a wrong path) looks exactly like green. `run-gates.mjs` refuses a gate without `must_fail`, and treats a twin that crashes (missing command, usage error) as broken rather than red.
- **Skipped is not passed.** The single required check, `gate-verdict`, fails unless planning succeeded and every gate job actually ran and passed. An empty gate list exits non-zero for the same reason.
- **Zero approvals, zero bypass.** No human approval is required, and no person can bypass the ruleset either. The removal of review is only safe because nobody, including admins, can merge past red.
- **Known failures are tracked, not hidden.** Mark a golden `known_failing` with a reason instead of deleting it. When it starts passing, the gate fails until the marker is removed, so a fix is guarded from the moment it lands.
- **Every incident becomes a golden.** The golden set grows from real misses, which is how the same bug is stopped from shipping twice.

## Workflow

1. **Survey the repo.** Find the language, the test runner, how CI runs today, and the behaviour that would hurt most if it broke (for an LLM product: the answers users rely on; for a pipeline: the outputs clients see). Reuse the existing test framework as a gate before inventing anything.
2. **Vendor the runner.** Copy `scripts/run-gates.mjs` and `scripts/golden.mjs` into `.hg-gates/` in the target repo, so CI never depends on this skill being installed.
3. **Write the goldens.** Known-answer cases in `evals/goldens.jsonl`, shaped like `templates/goldens.example.jsonl`, drawn from real usage and past incidents. Each needs an input your system can answer through a command (stdin in, stdout out) and an `expect` that is objectively checkable. Where the path calls a model, make the gated run deterministic (recorded responses, a pinned fixture, retrieval-only) and keep live-model runs for the nightly report. Read `reference.md` for how to write goldens that catch real regressions.
4. **Write each twin.** For goldens, `evals/must-fail.jsonl` is one case whose `expect` is deliberately wrong, so the gate must breach. For a test suite, a tiny test that asserts something false, kept out of the normal run.
5. **Declare the gates** in `evals.config.json` (template in `templates/evals.config.json`) and run `node .hg-gates/run-gates.mjs` until it says `GATES PASS`.
6. **Add CI.** Copy `templates/gates.yml` to `.github/workflows/gates.yml` and add the setup steps your gate commands need. Ship it through a PR and confirm `gate-verdict` reports.
7. **Make it binding.** Run `scripts/protect.sh <owner/repo>` (try `--dry-run` first). This changes repository settings, so show the user the dry-run output and get a yes before applying.
8. **Prove the red.** Open a throwaway PR that breaks the behaviour a golden covers, enable auto-merge on it, and confirm the golden gate fails, `gate-verdict` fails and the merge stays blocked. Close it unmerged. Until this has been seen, the setup is unproven, however green it looks.

## Autonomy

Proceed without asking on steps 1 to 6 and 8, all of which live in branches and PRs. Stop for the user before step 7, and before loosening any floor or marking a failing golden `known_failing`: both lower the bar, which is the user's call, not the agent's.

## Companions

- `reference.md`: writing goldens that catch regressions, must-fail patterns per stack, the nightly model-eval lane, and gotchas.
- `templates/`: workflow, config and example goldens.
- `scripts/`: the gate runner, the golden checker and the protection script.
