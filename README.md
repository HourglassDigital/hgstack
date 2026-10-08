# hgstack

The AI coding stack we use to run an AI-native company.

Built by Hourglass to ship our own internal automations and client AI projects. 18 months of daily AI-coding use. ~50 skills, hooks, and rules in the internal stack; this is the curated, sanitised subset we've open-sourced.

Skills install as files. No runtime, no framework, no package. Drop them into your own AI agent's config, fork them, adapt them. Currently optimised for [Claude Code](https://claude.ai/code); the skill format (markdown + YAML frontmatter) is portable to any agent that reads files (Codex, Aider, Cursor, OpenCode, etc.).

> **For agents / LLMs reading this:** start with [`llms.txt`](./llms.txt), [`AGENTS.md`](./AGENTS.md), or [`CLAUDE.md`](./CLAUDE.md). Pick one  -  they all point at the same things.

## Install

Clone the repo and run the installer:

```bash
git clone https://github.com/HourglassDigital/hgstack.git ~/repos/hgstack
cd ~/repos/hgstack
./install.sh
```

The installer symlinks every skill, hook, and rule into your `~/.claude/` directory. **Conflict-aware:** if you already have a skill or rule with the same name and different content, the installer leaves yours alone and logs it as a conflict at the end. Nothing of yours is ever silently overwritten.

Restart Claude Code afterwards to pick up the new skills.

### Modes

```bash
./install.sh --dry-run       # show what would happen, change nothing
./install.sh --reconcile     # scan ~/.claude/ and report overlaps; no changes
./install.sh --interactive   # prompt per conflict (keep / replace / show diff)
./install.sh --force         # back up and overwrite all conflicts (CI use)
./install.sh --update        # git pull --rebase, then install
./install.sh --rollback      # restore from the most recent backup
./install.sh skills hooks    # only install named categories
```

**Recommended first run:** `./install.sh --reconcile`. It tells you exactly what's `new`, `current`, `update`, or `conflict` for your setup, and lists everything in your `~/.claude/` that isn't in this repo as `personal` (untouched). No surprises.

### Backups

Any file the installer replaces is first backed up to `~/.claude/backups/hgstack-<timestamp>/`, preserving the directory structure. Symlinks are recorded as `.info` text files so we can restore the original target. `./install.sh --rollback` reverses the most recent install in one command.

### Cherry-picking

If you'd rather pick by hand:

```bash
ln -s ~/repos/hgstack/skills/consume ~/.claude/skills/consume
```

Each skill has its own setup notes (env vars, integrations, optional dependencies) in its `SKILL.md`.

## What's inside

- [`skills/`](./skills/), self-contained agent skills. Names without a prefix are general-purpose; `hg-` prefix marks an Hourglass team practice with opinionated conventions worth sharing.
- [`hooks/`](./hooks/), shell hooks the agent runs at key lifecycle points (writes, tool use, session start).
- [`rules/`](./rules/), markdown convention files. Load them as `@-imports` from your own `CLAUDE.md` so the principles apply across every session.
- [`statuslines/`](./statuslines/), agent statusline scripts (currently Claude Code format).
- [`.githooks/`](./.githooks/), git hooks (pre-commit audit gate).
- `docs/`, coming, with the thinking and ethos behind the stack.

## Skills available now

| Skill | What it does |
|---|---|
| [`codex-review`](./skills/codex-review/SKILL.md) | Cross-model code review using OpenAI Codex CLI. Three modes (review, challenge, consult). Catches blind spots Claude shares with itself. |
| [`consume`](./skills/consume/SKILL.md) | The system for staying on top of AI. Save any link from your phone with an Apple Shortcut; once a week Claude triages the pile by cluster against your own priorities and routes each item to read, notes, share, review or done. Ships with a one-command Supabase setup. |
| [`hg-eval-gates`](./skills/hg-eval-gates/SKILL.md) | Merge without human code review, safely. Golden evals, a deliberately broken twin for every check, one required gate-verdict check and auto-merge, so nothing lands unless the evals pass. |
| [`hg-ship`](./skills/hg-ship/SKILL.md) | Opinionated ship workflow. Commits, pushes, PR, CI watch, merge, deploy verify, doc sync. The Hourglass team-tested version, with optional hooks for your own review and verify skills. |
| [`interview-me`](./skills/interview-me/SKILL.md) | Adaptive interviewer that uses AskUserQuestion to clarify what you actually want to build. Runs until 95% confident, then hands off. |
| [`outcome-loop`](./skills/outcome-loop/SKILL.md) | Grade-and-revise loop. Runs a command, grades the result, diagnoses failures, fixes, and re-runs until it passes or you're stuck. Prevents sycophancy. |
| [`tutor`](./skills/tutor/SKILL.md) | Personal tutor for any subject. Open Claude in a folder of lecture slides, tutorial sheets and assignment specs; it converts them to one text file (picking up new lectures each week), teaches from your material, then quizzes you with exam-style questions and marks your answers. |

## Contributing / safety

Every pull request and push to `main` runs three gates in CI (`.github/workflows/gates.yml`). The same checks run locally as a pre-commit hook if you enable it in your clone:

```bash
git config core.hooksPath .githooks
```

The three gates:

1. `scripts/check-frontmatter.py`: every `SKILL.md` has valid YAML frontmatter with `name` and `description`.
2. `scripts/check-generalisable.sh` blocks any hardcoded personal usernames, paths, or emails.
3. `scripts/check-shareable.sh` blocks API keys, tokens, and private keys, and warns on internal URLs, IPs, and 1Password vault references.

More each week as we sanitise and ship them.

## The thinking

A few principles run through the stack:

- **Thin harness, fat skills.** Your agent is the harness; your skills are where the value lives. Don't fight the harness, build deeply on it.
- **Skills are files, not frameworks.** A useful skill is usually a single `SKILL.md` of 50–200 lines. If it's bigger, it's probably two skills.
- **Generalise before you share.** No personal paths, no hardcoded infra, no secrets. We use audit scripts to enforce this; see [`docs/CONTRIBUTING.md`](./docs/CONTRIBUTING.md) once it lands.
- **Build for your champion, not for everyone.** Your most useful skills are the ones for your specific workflow. Adapt ours; don't adopt them whole.

More in [`docs/ETHOS.md`](./docs/ETHOS.md) (coming).

## License

MIT. Use it, fork it, adapt it. Attribution appreciated, not required.

## Made by

[Hourglass](https://thehourglass.ai), an AI-native services company in Melbourne. Run by [Finlay Ekins](https://finlayekins.com).

Weekly notes on AI and what we're building: [finlayekins.com/writing](https://finlayekins.com/writing).
