#!/bin/bash
# check-generalisable.sh - audit repo for hardcoded personal references
# Run before every merge. Exit 1 if issues found.
#
# Checks for:
#   - Hardcoded usernames in paths (e.g. /Users/<name>, -Users-<name>)
#   - Personal email addresses
#   - User-specific path assumptions
#
# Acceptable (not flagged):
#   - Shared infrastructure (hourglass-brain, Supabase project IDs, team names)
#   - Generic ~ or $HOME references
#   - Documentation mentioning team members by name (CLAUDE.md.template, README)

set -euo pipefail

REPO_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
ISSUES=0

red()    { printf '\033[31m%s\033[0m\n' "$1"; }
yellow() { printf '\033[33m%s\033[0m\n' "$1"; }
green()  { printf '\033[32m%s\033[0m\n' "$1"; }
dim()    { printf '\033[90m%s\033[0m\n' "$1"; }

echo ""
echo "Generalisation audit: $REPO_DIR"
echo ""

# Pattern definitions
# Each pattern: regex|description|exclude_glob (optional)
PATTERNS=(
  '/Users/[a-z][a-z0-9_-]*|Hardcoded macOS user path|'
  '-Users-[a-z][a-z0-9_]*-[^-]|Hardcoded Claude project path (username-specific)|scripts/check-generalisable.sh'
  '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}|Email address|'
)

# Scan only git-tracked files. Gitignored or local-only files (per-user config,
# generated output, local logs) never get shared when the repo is published, so
# they cannot leak: scanning them only produces false failures on contributors'
# machines. git ls-files also makes local runs match CI exactly (a fresh
# checkout contains only tracked files). Fall back to find when not in a repo.
if git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  FILES=$(git -C "$REPO_DIR" ls-files | sed "s|^|$REPO_DIR/|" | sort)
else
  FILES=$(find "$REPO_DIR" -type f \
    -not -path '*/.git/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/__pycache__/*' \
    -not -name '*.pyc' \
    -not -name '.DS_Store' \
    | sort)
fi

for pattern_spec in "${PATTERNS[@]}"; do
  IFS='|' read -r pattern desc exclude <<< "$pattern_spec"

  while IFS= read -r file; do
    rel="${file#$REPO_DIR/}"

    # Skip excluded files
    if [[ -n "$exclude" && "$rel" == "$exclude" ]]; then
      continue
    fi

    # Allow: team profiles are intentionally per-person (emails, names, paths)
    if [[ "$rel" == team/profiles/* || "$rel" == team/reconciliation/* ]]; then
      continue
    fi

    # Search for matches. `--` is required: pattern #2 begins with `-`, so
    # without it grep parses the pattern as bundled options (-U -s -e ...),
    # where -e swallows the rest as a different regex that spuriously matches
    # innocuous text like CSS `prefers-reduced-motion`. `--` forces grep to
    # treat $pattern as the pattern, not flags.
    matches=$(grep -n -E -- "$pattern" "$file" 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
      # Filter out acceptable patterns
      filtered=""
      while IFS= read -r match; do
        line="$match"

        # Allow: regex patterns that match usernames generically (e.g. [a-z], [^-]+)
        if echo "$line" | grep -qE '\[a-z\]|\[\^-\]|\[a-z0-9\]'; then
          continue
        fi

        # Allow: this script's own pattern definitions
        if echo "$line" | grep -qE "^[0-9]+:.*PATTERNS|^[0-9]+:.*pattern_spec|^[0-9]+:.*# "; then
          continue
        fi

        # Allow: comments explaining what the check does
        if echo "$line" | grep -qE "^[0-9]+:\s*#"; then
          continue
        fi

        # Allow: git SSH URLs (git@github.com is not a personal email)
        if echo "$line" | grep -qE 'git@github\.com'; then
          continue
        fi

        # Allow: placeholder/example emails - you@, billing@client, noreply@,
        # and RFC 2606 reserved domains (example.com/.org/.net and the
        # .example/.test/.invalid TLDs) used in docs and SQL samples.
        if echo "$line" | grep -qE 'you@|billing@client|noreply@|@example\.(com|org|net)|@[a-z0-9.-]+\.(example|test|invalid)([^a-z]|$)'; then
          continue
        fi

        # Allow: emails in .example config files (they're templates, not real addresses)
        if [[ "$rel" == *.example ]]; then
          continue
        fi

        # Allow: example/illustrative paths in documentation (e.g. "-Users-michaelbatko-batko-ai")
        if echo "$line" | grep -qE 'e\.g\.|for example|Example'; then
          continue
        fi

        filtered="$filtered$line"$'\n'
      done <<< "$matches"

      if [[ -n "${filtered%$'\n'}" ]]; then
        red "FAIL: $desc"
        echo "  File: $rel"
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          echo "    $line"
        done <<< "$filtered"
        echo ""
        ISSUES=$((ISSUES + 1))
      fi
    fi
  done <<< "$FILES"
done

# Summary
echo "---"
if [[ $ISSUES -eq 0 ]]; then
  green "PASS: No hardcoded personal references found."
else
  red "FAIL: $ISSUES issue(s) found. Fix before merging."
fi
echo ""

[[ $ISSUES -eq 0 ]] || exit 1
