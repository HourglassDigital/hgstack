---
name: consume
description: Weekly triage of everything you saved during the week (articles, tweets, AI tools, GitHub repos). Pulls the links captured by the Consume Apple Shortcut from your Supabase inbox, groups them into clusters, judges each against your own PRIORITIES.md, and routes it to an action - read, save notes to a markdown folder, share to Slack, review a tool or repo, or mark done. Use when the user says "consume", "review my consume list", "go through my saved links", "what did I save this week", "triage my reading", or invokes /consume.
argument-hint: "[optional: filter, e.g. 'repos only' or 'just 10']"
---

# Consume: weekly triage

One pipe for everything you save. During the week you tap **Share, Consume**
on your phone or Mac and the link lands in a Supabase table. Once a week you
run `/consume` and Claude walks the pile with you, cluster by cluster, and
decides what each item deserves. Capture takes a second; judgement happens
here.

First time? Follow **Setup** at the bottom. It takes about ten minutes.

## Config

All config lives in one env file, `~/.env.consume` by default (override the
path with `CONSUME_ENV_FILE`). `setup/setup.sh` writes the required lines.

| Var | Purpose | Required |
|---|---|---|
| `CONSUME_SUPABASE_URL` | `https://<project-ref>.supabase.co` | yes |
| `CONSUME_SUPABASE_KEY` | service-role key (RLS locks everyone else out) | yes |
| `CONSUME_PRIORITIES` | path to your priorities file, default `~/.consume/PRIORITIES.md` | no |
| `CONSUME_NOTES_DIR` | where "save notes" writes markdown, default `~/consume-notes` | no |
| `CONSUME_SLACK_CHANNEL` | Slack channel for "share", needs a Slack MCP or skill | no |

## Step 1: load config and fetch the pile

```bash
set -a; . "${CONSUME_ENV_FILE:-$HOME/.env.consume}"; set +a
curl -sS "$CONSUME_SUPABASE_URL/rest/v1/consume_items?status=eq.pending&order=created_at.asc" \
  -H "apikey: $CONSUME_SUPABASE_KEY" -H "Authorization: Bearer $CONSUME_SUPABASE_KEY"
```

If the env file or either required var is missing, point the user at Setup
and stop. If nothing is pending, say so and stop; never invent items. Apply
any argument filter ("repos only", "just 10") after fetching. Say how many
are pending before you start.

Then read the priorities file (`${CONSUME_PRIORITIES:-$HOME/.consume/PRIORITIES.md}`).
It is the user's own and changes over time, so read it every pass and never
hardcode it. If it doesn't exist, run the pass without it and offer once to
create one from `PRIORITIES.template.md` in this skill's folder.

## Step 2: label each item

The table only holds raw URLs. Resolve what each one is:

- **GitHub repo:** fetch the README (`gh api repos/<owner>/<repo>/readme` or
  WebFetch). Note stars, last push and licence.
- **X / Twitter:** use an X-reading tool if you have one. WebFetch on x.com
  often fails; if it does, say so.
- **Everything else:** WebFetch for the title and gist.

If a fetch fails (paywall, login wall, JS-only page), say so plainly. Never
guess at content you couldn't read. Cache the resolved title on the row so
history stays readable:

```bash
curl -sS -X PATCH "$CONSUME_SUPABASE_URL/rest/v1/consume_items?id=eq.<ID>" \
  -H "apikey: $CONSUME_SUPABASE_KEY" -H "Authorization: Bearer $CONSUME_SUPABASE_KEY" \
  -H "Content-Type: application/json" -d '{"title":"<resolved title>"}'
```

## Step 3: walk it by cluster

**Group before you walk.** Cluster the pile by theme (agent tooling, memory,
a framework you're evaluating, essays, books, business) and take one cluster
at a time. Reviewing all the agent harnesses together gives better judgement
than oldest-first, because overlap only shows up side by side. Don't chop a
cluster into fives: context switching is the cost to minimise.

Present each cluster as one message of short entries. For every item:

- **What it is:** title and type (article, tweet, tool, repo).
- **What it actually says:** the mechanism, not the marketing, with the
  numbers that matter. Enough to judge without opening it.
- **The priority it touches:** number, handle and one-line meaning from
  PRIORITIES.md, e.g. "2, ship faster: client automations in days". Or "no
  priority" with a reason. Skip this line for books and essays.
- **Your read:** honest, including "skip this, it's abandoned".

**Never present a bare verdict table.** Every row carries its own description;
the reader must be able to judge from the row alone.

Then, for items that could become real work, ask one question per item with
`AskUserQuestion`, carrying the whole case: how it works, the priority it
touches, **the catch** (licence, bus factor, migration cost, a README claim the
code doesn't back up), and **your recommendation, named as such**, with real
alternatives. The user is buying judgement, not summaries. If they ask a
clarifying question, answer it inside the next question and re-ask. Loose
items (books, essays, a good thread) don't need a question: summarise, pull
the insight, move on.

## Step 4: route each item

Every item ends in one action. These are the defaults; add or rename your own
(the `action_taken` column is free text).

| Action | What happens | `action_taken` |
|---|---|---|
| **Read** | Fuller summary and an honest "worth your time?" verdict | `read` |
| **Save notes** | Write a markdown note to `$CONSUME_NOTES_DIR` (below) | `notes` |
| **Share** | Post the link plus one or two lines on why to `$CONSUME_SLACK_CHANNEL` via your Slack tool. Only offer this when the channel is set | `shared` |
| **Review** | Proper tool or repo review (below) | `reviewed` |
| **Done** | Nothing more to do; it's dealt with | `done` |
| **Skip** | Leave it for next week. Stays `pending` | (unchanged) |

**Save notes:** one file per item, `$CONSUME_NOTES_DIR/YYYY-MM-DD-<slug>.md`
(create the folder if needed), with the title, URL, the summary, why it
matters and which priority it touches. If the user keeps notes somewhere else
(Obsidian vault, a notes skill, a knowledge base), point `CONSUME_NOTES_DIR`
there or route through that tool instead.

**Review:** research properly, then judge. Read the README and structure,
extract the mechanism (data model, pipeline, runtime dependencies), map it to
the "My stack" section of PRIORITIES.md, and give a verdict: **add**,
**experiment** or **skip**, naming what it would replace or duplicate and what
it would cost to try.

**Don't build mid-pass.** This session is for judgement. When an item turns
into real work (port a pattern, trial a tool), add it to
`$CONSUME_NOTES_DIR/backlog.md` (item, priority, what to do, where) and keep
going. Doing the work inline blocks the whole queue behind one item. Hand the
backlog over at the end.

## Step 5: mark triaged

After any action except Skip:

```bash
curl -sS -X PATCH "$CONSUME_SUPABASE_URL/rest/v1/consume_items?id=eq.<ID>" \
  -H "apikey: $CONSUME_SUPABASE_KEY" -H "Authorization: Bearer $CONSUME_SUPABASE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"status":"triaged","action_taken":"<action>","triaged_at":"now()","notes":"<short verdict>"}'
```

Nothing is deleted; triaged items just stop showing up. Use `status: archived`
for things you want gone from the pile without an action.

## Step 6: wrap up

Give a tally (read, notes, shared, reviewed, done, skipped), list anything
left pending, and show the backlog entries added this pass.

## Setup

You need a Supabase project (the free tier is plenty; a dedicated project
keeps it tidy), an iPhone or Mac with Shortcuts, and the Supabase CLI, `jq`,
`openssl` and `curl`.

1. **Backend:** `supabase login`, then run
   `<this skill's folder>/setup/setup.sh --project-ref <your-ref>`. It creates
   the `consume_items` table, deploys the `consume-capture` function with
   `--no-verify-jwt` (the Shortcut sends its own token, not a Supabase JWT, so
   JWT checking would 401 every save), generates a capture token, writes
   `~/.env.consume` and sends a test link through. Safe to re-run.
2. **Shortcut:** build the share-sheet button with `SHORTCUT.md` (three
   minutes).
3. **Priorities (optional, recommended):**
   `mkdir -p ~/.consume && cp PRIORITIES.template.md ~/.consume/PRIORITIES.md`,
   then fill it in. Without it, triage still works but can't tell you what
   matters to you.
4. Save a few links, then run `/consume`.

Prefer to do it by hand? `setup/schema.sql` pastes into the Supabase SQL
editor, and the function lives in `setup/supabase/functions/consume-capture/`.
Set the `CONSUME_CAPTURE_TOKEN` secret, deploy with `--no-verify-jwt`, and
write the env file yourself.
