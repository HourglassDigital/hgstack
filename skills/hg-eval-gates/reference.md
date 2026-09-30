# Eval gates reference

Read the section you need; none of it is required reading for a first setup.

## Writing goldens that catch regressions

- **Source them from reality.** Real user questions, support tickets, sales-call questions and every past incident. Invented cases test what the author already believed works.
- **Phrase variants, one expectation.** The same question asked formally, casually and with typos (`refund-window`, `refund-window.casual`). Regressions usually break the awkward phrasing first.
- **Traps.** Questions where a plausible wrong answer exists: an outdated draft that outranks the approved policy, a claim you are not allowed to make. Use `not_contains` for the thing that must never appear.
- **Families with floors.** Group cases (`policy`, `pricing`, `retrieval`) and set a floor per family in the header line. Keep a floor of 1.0 for anything where one miss is a client-visible error; a lower floor only where partial credit is honest.
- **Averages hide regressions.** A change can raise the overall score while breaking the specific questions users rely on. Floors per family, not one global number, are what catch that.
- **Assert the behaviour, not the wording.** `contains` a fact or `regex` a format beats `equals` a paragraph that any harmless rewording breaks.
- **When a golden fails for a reason you accept for now,** mark it `known_failing` with the reason. It stops counting against the floor, stays visible in every run, and the gate fails the day it starts passing until the marker is removed.

## Must-fail patterns

| Gate | Twin |
|---|---|
| Golden evals | A one-case file whose `expect` is deliberately wrong. It must breach with exit 1. |
| pytest / jest / vitest | A test that asserts something false, in a path the normal run excludes (`tests/must_fail/`, or a tag). |
| Lint or type check | A fixture file with a deliberate violation, checked only by the twin command. |
| A size or complexity ratchet | Run the checker against a fixture that exceeds the limit. |

Set `must_fail_exit` when your tool's failure code is not 1. pytest exits 1 for failed tests and 2, 4 or 5 for interruptions, usage errors or no tests collected; only 1 proves the gate can catch a defect.

## Model-in-the-loop evals (nightly, never blocking)

Run the same goldens against the live model on a schedule (a `schedule:` trigger in a separate workflow), several runs per case, and report the pass count with its spread. Post the result somewhere the team reads, naming the repo, the commit, the run link and each failing case. Promote a nightly miss into the deterministic golden set once a human has confirmed it is a real regression.

## Gotchas

- **A new required check is invisible until it has reported once.** Merge the workflow PR (or run it on a PR) before `protect.sh` can require `gate-verdict`.
- **Private repos need a plan with rulesets.** On GitHub Free, `protect.sh` gets a 403 from the rulesets endpoint for private repos.
- **Strict status checks.** The ruleset requires branches to be up to date with main, so the gates always ran against what will actually merge. A PR behind main needs an update before auto-merge fires.
- **Pipes swallow failures** unless the shell uses pipefail. Both scripts run commands with `bash -o pipefail`; keep that if you adapt them.
- **Secrets in CI.** If a gate needs a key (a private fixture repo, a recorded-embeddings bucket), add it as a repository secret; a missing secret must make the gate fail, never skip.
