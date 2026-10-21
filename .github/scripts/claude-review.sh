#!/usr/bin/env bash
# Bookkeeping for claude-review.yml, which runs this file as it stands on the PR's base branch.
#   prepare  Works out the round and diff range from earlier summaries, and writes everything the reviewer
#            reads into $RUNNER_TEMP/claude-review: its instructions, the reviewed diff, the commit log and
#            the trusted part of the PR discussion. The reviewer has no shell, so this is all it gets.
#   post     Validates the reviewer's structured output, keeps findings that sit in the reviewed diff and
#            were not posted before, posts them inline, and posts the round's summary.
# The reviewer's output is untrusted: it is validated here and only ever sent to GitHub as JSON bodies.
set -euo pipefail

readonly POSTER='github-actions[bot]'
# Authors whose comments the reviewer reads. Anyone can comment on this public repository.
readonly TRUSTED_AUTHORS='["github-actions[bot]", "LCEnzo"]'
readonly PER_PAGE=100
# Ten pages per comment list. Past that the round count would be a guess, so the run fails instead.
readonly MAX_PAGES=10
# Past this many posted findings the run fails rather than drop some and risk repeats.
readonly MAX_POSTED=200
readonly MAX_DISCUSSION=60
readonly MAX_COMMENT_CHARS=2000
readonly MAX_FINDINGS=15
readonly MAX_BODY_CHARS=1500
readonly MAX_NITS=3
readonly MAX_RISK_PATHS=10
readonly ROUND_CAP=3
readonly SHA_LINE='^Reviewed-SHA: [0-9a-f]{40}$'
readonly INSTRUCTIONS=(.github/review-rules.md AGENTS.md)
# Paths that are high risk by location alone; review-rules.md names the rest of the tier.
readonly HIGH_RISK_PATHS='^(backend/accounts/|\.github/workflows/|deploy/|deploy\.sh$|compose\.yaml$|Caddyfile$)|(^|/)migrations/'
# The reviewed diff, which the reviewer reads and the poster anchors findings to: one context size, and none
# of the generated, locked or captured files review-rules.md says not to review.
readonly DIFF_CONTEXT=3
readonly SKIP_PATHSPEC=(
  ':(exclude,glob)frontend/lib/generated/**' ':(exclude,glob)**/*.lock' ':(exclude)backend/openapi.json'
  ':(exclude).secrets.baseline' ':(exclude,glob)backend/monitoring/tests/*.xml'
  ':(exclude,glob)backend/monitoring/tests/*.html'
)
# Past these sizes the run fails rather than hand the reviewer a truncated view.
readonly MAX_DIFF_BYTES=1000000
readonly MAX_LIST_BYTES=200000

: "${GH_TOKEN:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_OUTPUT:?}" "${GITHUB_STEP_SUMMARY:?}" "${RUNNER_TEMP:?}"
: "${PR_NUMBER:?}" "${HEAD_SHA:?}" "${BASE_REF:?}"

# Read by the reviewer through --add-dir. Raw API pages stay in WORK_DIR.
readonly OUT_DIR=$RUNNER_TEMP/claude-review
readonly WORK_DIR=$RUNNER_TEMP/claude-review-work

fail() {
  echo "::error::$*"
  exit 1
}

emit() { printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"; }

summary() { printf '%s\n' "$@" >>"$GITHUB_STEP_SUMMARY"; }

# Fails when file $1 is larger than $2 bytes; $3 names it in the error.
require_size_at_most() {
  local bytes
  bytes=$(wc -c <"$1")
  ((bytes <= $2)) || fail "$3 is $bytes bytes, over the cap of $2"
}

# Prints the diff under review: the round's range, without the paths in SKIP_PATHSPEC.
reviewed_diff() {
  git diff --no-color --no-ext-diff --unified="$DIFF_CONTEXT" "$RANGE" -- . "${SKIP_PATHSPEC[@]}"
}

# Writes every element of a paginated list endpoint to stdout, one JSON object per line.
fetch_all() {
  local endpoint=$1 page body
  for ((page = 1; page <= MAX_PAGES; page++)); do
    body=$(gh api "$endpoint?per_page=$PER_PAGE&page=$page")
    jq -c '.[]' <<<"$body"
    if (($(jq 'length' <<<"$body") < PER_PAGE)); then return 0; fi
  done
  fail "$endpoint lists more than $((PER_PAGE * MAX_PAGES)) entries"
}

# Sets ROUND, LAST_SHA, RANGE and SCOPE. Each completed round left one summary ending in a Reviewed-SHA line.
compute_state() {
  local shas
  local -a reviewed=()
  fetch_all "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" >"$WORK_DIR/issue-comments.jsonl"
  fetch_all "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER/comments" >"$WORK_DIR/review-comments.jsonl"
  shas=$(jq -r --arg who "$POSTER" --arg re "$SHA_LINE" '
    select(.user.login == $who) | .body | split("\n") | map(rtrimstr("\r") | select(test($re))) | last // empty
    | ltrimstr("Reviewed-SHA: ")' "$WORK_DIR/issue-comments.jsonl")
  if [[ -n $shas ]]; then mapfile -t reviewed <<<"$shas"; fi
  ROUND=$((${#reviewed[@]} + 1))
  LAST_SHA=
  if ((${#reviewed[@]} > 0)); then LAST_SHA=${reviewed[${#reviewed[@]} - 1]}; fi
  if [[ -n $LAST_SHA ]] && git merge-base --is-ancestor "$LAST_SHA" "$HEAD_SHA" 2>/dev/null; then
    RANGE="$LAST_SHA..$HEAD_SHA"
    SCOPE=incremental
  elif [[ -n $LAST_SHA ]]; then
    # A force push or rebase dropped the last reviewed commit from the branch.
    RANGE="origin/$BASE_REF...$HEAD_SHA"
    SCOPE=full-after-rewrite
  else
    RANGE="origin/$BASE_REF...$HEAD_SHA"
    SCOPE=full
  fi
}

prepare() {
  local path posted
  mkdir -p "$OUT_DIR"
  for path in "${INSTRUCTIONS[@]}"; do
    git cat-file -e "origin/$BASE_REF:$path" 2>/dev/null ||
      fail "$path is missing on origin/$BASE_REF; the reviewer takes instructions only from the base branch"
    git show "origin/$BASE_REF:$path" >"$OUT_DIR/$(basename "$path")"
  done

  compute_state
  if [[ $LAST_SHA == "$HEAD_SHA" ]]; then
    emit skip true
    summary "### Claude review" "" "Skipped: round $((ROUND - 1)) already reviewed \`$HEAD_SHA\`."
    return 0
  fi

  reviewed_diff >"$OUT_DIR/diff.patch"
  require_size_at_most "$OUT_DIR/diff.patch" "$MAX_DIFF_BYTES" "the reviewed diff"
  git diff --name-status "$RANGE" >"$OUT_DIR/files.txt"
  require_size_at_most "$OUT_DIR/files.txt" "$MAX_LIST_BYTES" "the changed-file list"
  # git log reads a...b as the commits on either side; the PR's own commits are a..b.
  git log --no-color --format='commit %H%nAuthor: %an%n%n%B' "${RANGE/.../..}" >"$OUT_DIR/log.txt"
  require_size_at_most "$OUT_DIR/log.txt" "$MAX_LIST_BYTES" "the commit log"

  jq -r --arg who "$POSTER" '
    select(.user.login == $who)
    | "\(.path):\(.line // .original_line // "?") \(.body | gsub("\\s+"; " ") | .[0:400])"' \
    "$WORK_DIR/review-comments.jsonl" >"$OUT_DIR/posted-findings.txt"
  posted=$(wc -l <"$OUT_DIR/posted-findings.txt")
  ((posted <= MAX_POSTED)) || fail "$posted findings are already posted on this PR, over the cap of $MAX_POSTED"

  jq -rs --argjson trusted "$TRUSTED_AUTHORS" --argjson max "$MAX_DISCUSSION" --argjson chars "$MAX_COMMENT_CHARS" '
    map(select(.user.login as $u | any($trusted[]; . == $u))) | sort_by(.created_at) | .[-$max:][]
    | "--- \(.user.login), \(.created_at)\(if .path then ", on \(.path):\(.line // .original_line // "?")" else "" end)"
      + "\n\((.body // "")[0:$chars])\n"' \
    "$WORK_DIR/issue-comments.jsonl" "$WORK_DIR/review-comments.jsonl" >"$OUT_DIR/discussion.txt"

  jq -r --argjson trusted "$TRUSTED_AUTHORS" --argjson chars "$MAX_COMMENT_CHARS" '
    .pull_request | if (.user.login as $u | any($trusted[]; . == $u))
    then "\(.title)\n\n\((.body // "")[0:$chars])" else "Written by \(.user.login), who is not a trusted author." end' \
    "${GITHUB_EVENT_PATH:?}" >"$OUT_DIR/pr.txt"

  emit skip false
  emit round "$ROUND"
  emit range "$RANGE"
  emit scope "$SCOPE"
  summary "### Claude review" "" "Round $ROUND, scope \`$SCOPE\`, range \`$RANGE\`; $posted earlier findings."
}

# Prints "path<TAB>line" for every new-side line inside a hunk of the unified diff on stdin.
hunk_lines() {
  awk '
    /^diff --git / { path = ""; next }
    /^\+\+\+ / {
      path = substr($0, 5)
      if (substr(path, 1, 2) == "b/") path = substr(path, 3); else path = ""
      next
    }
    /^@@ / && path != "" {
      if (!match($0, /\+[0-9]+(,[0-9]+)?/)) next
      n = split(substr($0, RSTART + 1, RLENGTH - 1), part, ",")
      count = (n > 1) ? part[2] : 1
      for (i = 0; i < count; i++) printf "%s\t%d\n", path, part[1] + i
    }'
}

# The reviewer's output contract. --json-schema in claude-review.yml asks for the same shape.
# shellcheck disable=SC2016 # A jq program: its $names are jq variables.
readonly VALID_OUTPUT='
  def text($max): type == "string" and length >= 1 and length <= $max;
  def one_line: test("[[:cntrl:]]") | not;
  def count: type == "number" and . == floor and . >= 0 and . <= 1000;
  def finding:
    type == "object" and keys == ["body", "bug_class", "line", "path", "tag"]
    and (.tag | IN("Important", "Nit", "Pre-existing"))
    and (.path | text(300) and one_line)
    and (.line | type == "number" and . == floor and . >= 1 and . <= 1000000)
    and (.bug_class | text(80) and one_line)
    and (.body | text($max_body));
  type == "object" and keys == ["dropped_over_cap", "findings", "refuted", "risk"]
  and (.findings | type == "array" and length <= $max_findings and all(.[]; finding))
  and (.risk | type == "object" and keys == ["paths", "tier"] and (.tier | IN("high", "medium", "low"))
    and (.paths | type == "array" and length <= $max_paths and all(.[]; text(300) and one_line)))
  and (.dropped_over_cap | count) and (.refuted | count)'

# Credential shapes, the one list of them. Any match rejects the reviewer's whole output and nothing is posted.
#   Anywhere in the output: sk-ant- (Anthropic keys and OAuth tokens), gh[pousr]_ (GitHub tokens), github_pat_.
#   In finding text: a run of 40+ characters of [A-Za-z0-9+/=_-] that mixes upper case, lower case and digits
#   (base64-ish), or that is 65+ hex digits (longer than a SHA-256).
# shellcheck disable=SC2016 # A jq program: its $names are jq variables.
readonly NO_CREDENTIALS='
  def prefixed: test("sk-ant-|(^|[^A-Za-z0-9])gh[pousr]_|github_pat_");
  def encoded: (test("[A-Z]") and test("[a-z]") and test("[0-9]")) or test("^[0-9a-fA-F]{65,}$");
  ([.. | strings | select(prefixed)] | length) == 0
  and ([.findings[] | (.body, .bug_class) | scan("[A-Za-z0-9+/=_-]{40,}") | select(encoded)] | length) == 0'

# Breaks @mentions with a zero-width space (code point 8203) so posted text notifies nobody.
# shellcheck disable=SC2016 # A jq program: its $names are jq variables.
readonly QUIET='def quiet: ([8203] | implode) as $zwsp | gsub("@(?<u>[A-Za-z0-9])"; "@\($zwsp)\(.u)");'

post() {
  local finding request inline
  : "${FINDINGS:?the review job returned no structured output}"
  mkdir -p "$WORK_DIR"
  printf '%s' "$FINDINGS" >"$WORK_DIR/findings.json"
  jq -e --argjson max_findings "$MAX_FINDINGS" --argjson max_body "$MAX_BODY_CHARS" \
    --argjson max_paths "$MAX_RISK_PATHS" "$VALID_OUTPUT" "$WORK_DIR/findings.json" >/dev/null ||
    fail "the reviewer's output does not match the contract; nothing was posted"
  # The error names no match: run logs are public.
  jq -e "$NO_CREDENTIALS" "$WORK_DIR/findings.json" >/dev/null ||
    fail "the reviewer's output contains a credential-shaped string; nothing was posted"

  compute_state
  [[ $LAST_SHA != "$HEAD_SHA" ]] || fail "round $((ROUND - 1)) already summarized $HEAD_SHA"

  reviewed_diff | hunk_lines >"$WORK_DIR/diff-lines.tsv"
  git diff --name-only "origin/$BASE_REF...$HEAD_SHA" >"$WORK_DIR/changed-files.txt"
  jq -r --arg who "$POSTER" '
    select(.user.login == $who)
    | (.body | split("\n")[0] | capture("^\\*\\*\\[(Important|Nit|Pre-existing)\\] (?<class>.+)\\*\\*$")) as $h
    | "\(.path)\t\(.line // .original_line)\t\($h.class | ascii_downcase)"' \
    "$WORK_DIR/review-comments.jsonl" >"$WORK_DIR/posted-keys.txt"

  # Keeps findings on a reviewed line that were not posted before, up to MAX_NITS nits, in the reviewer's order.
  jq -n "$QUIET"'
    def set: split("\n") | map(select(length > 0)) | reduce .[] as $k ({}; .[$k] = true);
    ($lines | set) as $in_diff | ($posted | set) as $seen
    | reduce $out[0].findings[] as $f ({kept: [], outside: 0, repeats: 0, nits_over: 0, keys: {}, nits: 0};
        ($f.line | floor) as $line | "\($f.path)\t\($line)\t\($f.bug_class | quiet | ascii_downcase)" as $key
        | if $in_diff["\($f.path)\t\($line)"] | not then .outside += 1
          elif $seen[$key] or .keys[$key] then .repeats += 1
          elif $f.tag == "Nit" and .nits >= $max_nits then .nits_over += 1
          else .kept += [$f + {line: $line}] | .keys[$key] = true | .nits += (if $f.tag == "Nit" then 1 else 0 end)
          end)
    | del(.keys, .nits)' \
    --slurpfile out "$WORK_DIR/findings.json" --rawfile lines "$WORK_DIR/diff-lines.tsv" \
    --rawfile posted "$WORK_DIR/posted-keys.txt" --argjson max_nits "$MAX_NITS" >"$WORK_DIR/selection.json"

  : >"$WORK_DIR/results.jsonl"
  while IFS= read -r finding; do
    request=$WORK_DIR/request.json
    jq "$QUIET"'
      {body: "**[\(.tag)] \(.bug_class | quiet)**\n\n\(.body | quiet)\n\n<sub>Claude review, round \($round)</sub>",
       commit_id: $head, path, line, side: "RIGHT"}' \
      --argjson round "$ROUND" --arg head "$HEAD_SHA" <<<"$finding" >"$request"
    inline=true
    if ! gh api --method POST "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER/comments" --input "$request" --silent; then
      inline=false
      echo "::warning::could not post an inline comment; the finding goes into the summary"
    fi
    jq -c --argjson inline "$inline" '. + {inline: $inline}' <<<"$finding" >>"$WORK_DIR/results.jsonl"
    # GitHub asks for a pause between content-creating requests.
    sleep 1
  done < <(jq -c '.kept[]' "$WORK_DIR/selection.json")

  jq -rn "$QUIET"'
    def n($k; $word): "\($k) \($word)\(if $k == 1 then "" else "s" end)";
    def tagged($t): map(select(.tag == $t)) | length;
    ($out[0]) as $o | $sel[0] as $s | [$results[]] as $r | ($r | length) as $m
    | ($changed | split("\n") | map(select(length > 0))) as $files
    | ($files | map(select(test($high_re)))) as $high
    | (if ($high | length) > 0 then {tier: "high", paths: $high}
       else {tier: $o.risk.tier, paths: ($o.risk.paths | map(select(. as $p | any($files[]; . == $p))))} end
       | .paths |= .[0:$max_paths]) as $risk
    | [ (if $m == 0 then "Round \($round): nothing to fix"
         else "Round \($round): \(n($m; "finding")) (\($r | tagged("Important")) important, \(n($r | tagged("Nit"); "nit")), \($r | tagged("Pre-existing")) pre-existing)" end),
        "Risk: \($risk.tier) (\(if ($risk.paths | length) == 0 then "no paths named" else $risk.paths | map("`\(.)`") | join(", ") end))",
        (if $round >= $cap then "Round cap reached: step back and reconsider the approach before another fix round." else empty end),
        "",
        ($r[] | "[\(.tag)] `\(.path):\(.line)` \(.bug_class | quiet)"
          + (if .inline then "" else ". Not postable inline:\n\n\(.body | quiet)\n" end)),
        "",
        "Scope \($scope), `\($range)`. Verifiers refuted \($o.refuted); the reviewer left out \($o.dropped_over_cap) over its cap; the poster dropped \($s.outside) outside the reviewed diff, \(n($s.repeats; "repeat")) and \(n($s.nits_over; "nit")) over the cap of \($max_nits).",
        "",
        "Reviewed-SHA: \($head)"
      ] | join("\n")' \
    --slurpfile out "$WORK_DIR/findings.json" --slurpfile sel "$WORK_DIR/selection.json" \
    --slurpfile results "$WORK_DIR/results.jsonl" --rawfile changed "$WORK_DIR/changed-files.txt" \
    --arg high_re "$HIGH_RISK_PATHS" --argjson max_paths "$MAX_RISK_PATHS" --argjson max_nits "$MAX_NITS" \
    --argjson round "$ROUND" --argjson cap "$ROUND_CAP" --arg scope "$SCOPE" --arg range "$RANGE" \
    --arg head "$HEAD_SHA" >"$WORK_DIR/summary.md"

  jq -n --rawfile body "$WORK_DIR/summary.md" '{body: $body}' >"$WORK_DIR/summary.json"
  gh api --method POST "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" --input "$WORK_DIR/summary.json" --silent
  summary "### Claude review" "" '```' "$(cat "$WORK_DIR/summary.md")" '```'
}

[[ $PR_NUMBER =~ ^[0-9]+$ ]] || fail "PR_NUMBER must be a number, got '$PR_NUMBER'"
[[ $HEAD_SHA =~ ^[0-9a-f]{40}$ ]] || fail "HEAD_SHA must be a full commit SHA, got '$HEAD_SHA'"
git cat-file -e "$HEAD_SHA^{commit}" || fail "head commit $HEAD_SHA is not in the checkout"
mkdir -p "$WORK_DIR"

case ${1:-} in
  prepare) prepare ;;
  post) post ;;
  *) fail "usage: $0 prepare|post" ;;
esac
