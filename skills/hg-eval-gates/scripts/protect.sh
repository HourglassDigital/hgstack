#!/bin/bash
# Makes the gates binding on GitHub: a ruleset on the default branch that requires
# a pull request with zero approvals, requires the gate-verdict check, blocks force
# pushes and deletion, and has no bypass for people. Also turns on auto-merge,
# squash-only merges and branch auto-delete.
#
#   protect.sh <owner/repo> [--check <context>] [--dry-run]
#
# --check defaults to "gate-verdict", the verdict job in templates/gates.yml.
# Re-running converges: an existing ruleset named eval-gates is updated in place.
# Needs gh authenticated as a repo admin. Private repos need a GitHub plan with rulesets.
set -euo pipefail

REPO="${1:?usage: protect.sh <owner/repo> [--check <context>] [--dry-run]}"
shift
CHECK="gate-verdict"
DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK="$2"; shift ;;
    --dry-run) DRY=1 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

RULESET=$(jq -n --arg check "$CHECK" '{
  name: "eval-gates",
  target: "branch",
  enforcement: "active",
  bypass_actors: [],
  conditions: { ref_name: { include: ["~DEFAULT_BRANCH"], exclude: [] } },
  rules: [
    { type: "deletion" },
    { type: "non_fast_forward" },
    { type: "pull_request", parameters: {
        required_approving_review_count: 0,
        dismiss_stale_reviews_on_push: true,
        require_code_owner_review: false,
        require_last_push_approval: false,
        required_review_thread_resolution: false,
        allowed_merge_methods: ["squash"]
    }},
    { type: "required_status_checks", parameters: {
        strict_required_status_checks_policy: true,
        do_not_enforce_on_create: false,
        required_status_checks: [{ context: $check }]
    }}
  ]
}')
SETTINGS='{"allow_squash_merge":true,"allow_merge_commit":false,"allow_rebase_merge":false,"delete_branch_on_merge":true,"allow_auto_merge":true}'

if [[ $DRY -eq 1 ]]; then
  echo "Would apply to $REPO:"; echo "$RULESET"; echo "$SETTINGS"; exit 0
fi

ID=$(gh api "repos/$REPO/rulesets" --jq '.[] | select(.name == "eval-gates") | .id' 2>/dev/null || true)
if [[ -n "$ID" ]]; then
  gh api -X PUT "repos/$REPO/rulesets/$ID" --input - <<<"$RULESET" >/dev/null
  echo "updated the eval-gates ruleset on $REPO"
else
  gh api -X POST "repos/$REPO/rulesets" --input - <<<"$RULESET" >/dev/null
  echo "created the eval-gates ruleset on $REPO"
fi
gh api -X PATCH "repos/$REPO" --input - <<<"$SETTINGS" >/dev/null
echo "merge settings: squash only, auto-merge on, merged branches auto-deleted"
echo "required check: $CHECK (must match the verdict job name exactly, or every PR blocks)"
