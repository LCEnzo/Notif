#!/usr/bin/env bash
# Decides which sweeps a deep-sweeps.yml run starts. The rules and their reasons: docs/testing.md, "Deep sweeps workflow".
set -euo pipefail

readonly WORKFLOW_FILE=deep-sweeps.yml
readonly BRANCH=master
readonly RUN_LOOKBACK=50
readonly ALL_SWEEPS=(fuzz mutation)
# Job ids in deep-sweeps.yml; the jobs API names a job without `name:` by its id.
declare -rA JOB_OF=([fuzz]=fuzz-deep [mutation]=mutation)
# Churn counts non-test backend source: tests and migrations are left out.
readonly SOURCE_PATHS=(backend/accounts backend/commons backend/monitoring backend/notif backend/ops)
readonly NOT_SOURCE='(/migrations/|/tests/|/tests[.]py$|/test_[^/]*[.]py$|_test[.]py$)'

declare -A LAST_RUN=() LAST_SHA=() LAST_AGE=()

: "${GITHUB_EVENT_NAME:?}" "${GITHUB_OUTPUT:?}" "${GITHUB_STEP_SUMMARY:?}"

fail() {
  echo "::error::$*"
  exit 1
}

emit() { printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"; }

summary() { printf '%s\n' "$@" >>"$GITHUB_STEP_SUMMARY"; }

require_integer() {
  [[ ${!1:-} =~ ^[0-9]+$ ]] || fail "$1 must be a non-negative integer, got '${!1:-}'"
}

churn_since() {
  git diff --numstat "$1" HEAD -- "${SOURCE_PATHS[@]}" |
    awk -v skip="$NOT_SOURCE" '$0 !~ skip { lines += $1 + $2 } END { print lines + 0 }'
}

manual() {
  local requested=${SWEEPS_INPUT:-both} sweep run
  case $requested in
    both | fuzz | mutation) ;;
    *) fail "unknown sweeps input '$requested'" ;;
  esac
  summary "### Deep sweeps gate" "" "Manual run, \`sweeps: $requested\`. The change gate applies to scheduled runs only." ""
  for sweep in "${ALL_SWEEPS[@]}"; do
    run=false
    if [[ $requested == both || $requested == "$sweep" ]]; then run=true; fi
    emit "${sweep}_should_run" "$run"
    emit "${sweep}_churn" n/a
    echo "$sweep: run=$run (manual run, sweeps=$requested)"
  done
}

# Fills LAST_RUN, LAST_SHA and LAST_AGE (seconds) per sweep from the newest completed run on BRANCH
# in which that sweep's job succeeded, whatever triggered the run.
find_last_successful_runs() {
  local runs id sha age succeeded sweep
  runs=$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows/$WORKFLOW_FILE/runs?branch=$BRANCH&status=completed&per_page=$RUN_LOOKBACK" \
    --jq "[.workflow_runs[] | select(.id != $GITHUB_RUN_ID)] | sort_by(.created_at) | reverse | .[]
      | [.id, .head_sha, (now - (.created_at | fromdateiso8601) | floor)] | @tsv")
  while IFS=$'\t' read -r id sha age; do
    [[ -n $id ]] || continue
    succeeded=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$id/jobs?per_page=100" \
      --jq '.jobs[] | select(.conclusion == "success") | .name')
    for sweep in "${ALL_SWEEPS[@]}"; do
      if [[ -z ${LAST_RUN[$sweep]:-} ]] && grep -qxF "${JOB_OF[$sweep]}" <<<"$succeeded"; then
        LAST_RUN[$sweep]=$id
        LAST_SHA[$sweep]=$sha
        LAST_AGE[$sweep]=$age
      fi
    done
    ((${#LAST_RUN[@]} < ${#ALL_SWEEPS[@]})) || break
  done <<<"$runs"
}

decide() {
  local sweep=$1 run=false decision=skipped churn=n/a days=n/a last=none reason id sha age
  id=${LAST_RUN[$sweep]:-}
  if [[ -z $id ]]; then
    run=true
    reason="no successful run among the last $RUN_LOOKBACK completed runs on $BRANCH"
  else
    sha=${LAST_SHA[$sweep]}
    age=${LAST_AGE[$sweep]}
    [[ $age =~ ^-?[0-9]+$ ]] || fail "run $id has a malformed age '$age'"
    days=$((age / 86400))
    last="[$id](${GITHUB_SERVER_URL:-https://github.com}/$GITHUB_REPOSITORY/actions/runs/$id) at \`${sha:0:7}\`"
    if [[ $sha =~ ^[0-9a-f]{40}$ ]] && git cat-file -e "$sha^{commit}" 2>/dev/null; then
      churn=$(churn_since "$sha")
    else
      churn=unknown
    fi
    if ((age < MIN_DAYS_SINCE_LAST_SWEEP * 86400)); then
      reason="last successful run $days days ago, fewer than $MIN_DAYS_SINCE_LAST_SWEEP"
    elif [[ $churn == unknown ]]; then
      run=true
      reason="commit $sha of the last successful run is not in this clone's history (force-push?), so churn is unknown"
      echo "::warning::$sweep: $reason; running rather than skipping"
    elif ((churn >= CHANGE_THRESHOLD)); then
      run=true
      reason="$churn changed lines since the last successful run, at least $CHANGE_THRESHOLD"
    else
      reason="$churn changed lines since the last successful run, fewer than $CHANGE_THRESHOLD"
    fi
  fi
  if [[ $run == true ]]; then decision=runs; fi
  emit "${sweep}_should_run" "$run"
  emit "${sweep}_churn" "$churn"
  echo "$sweep: run=$run: $reason"
  summary "| $sweep | $decision | $last | $days | $churn | $reason |"
}

scheduled() {
  : "${GITHUB_REPOSITORY:?}"
  require_integer GITHUB_RUN_ID
  require_integer CHANGE_THRESHOLD
  require_integer MIN_DAYS_SINCE_LAST_SWEEP
  find_last_successful_runs
  summary "### Deep sweeps gate" "" \
    "Scheduled run. A sweep runs when its last successful run is at least $MIN_DAYS_SINCE_LAST_SWEEP days old and backend source churn since that run's commit reaches $CHANGE_THRESHOLD lines." "" \
    "| Sweep | Decision | Last successful run | Days since | Churn | Why |" \
    "|---|---|---|---:|---:|---|"
  local sweep
  for sweep in "${ALL_SWEEPS[@]}"; do
    decide "$sweep"
  done
}

case $GITHUB_EVENT_NAME in
  schedule) scheduled ;;
  workflow_dispatch) manual ;;
  *) fail "no gate rule for the $GITHUB_EVENT_NAME event" ;;
esac
