#!/usr/bin/env bash
#
# Report a finished deploy to the deployment log on api.linchpin.com
# (POST /deployments), so every deploy to every environment records what it
# shipped: the commits since that environment's last successful deploy, and on
# production the release's notes.
#
# Everything about the deploy is read from its GitHub Deployment: the commit,
# the environment, when it started, and the payload deploy.yml gives it
# (release_tag, branch, correlation_id). The commit the environment had before
# is the newest earlier deployment to it that ever reached `success`; GitHub
# marks a superseded staging deployment inactive, so the status history is read
# rather than the latest state.
#
# Logging never fails a deploy: deploy.yml runs this with continue-on-error, so
# a refusal shows as a warning on the run instead of passing silently.
#
# Run it locally to see what it would send, without credentials:
#
#   GH_REPO=linchpin/linchpin.com DEPLOYMENT_ID=7180278280 STATUS=success \
#     DRY_RUN=true actions/report-deployment/report-deployment.sh
#
# Env: GH_REPO (owner/name), DEPLOYMENT_ID, STATUS (the job's: success, failure
# or cancelled), GH_TOKEN (gh's own login otherwise), CLIENT_ID and
# CLIENT_SECRET (an api.linchpin.com client with deployments:write),
# ENVIRONMENT_URL, API_URL, RUN_ID, ACTOR, LOG_URL, DRY_RUN (true prints the
# report instead of sending it), GITHUB_STEP_SUMMARY.

set -euo pipefail

: "${GH_REPO:?Set GH_REPO to owner/name}"
: "${DEPLOYMENT_ID:?Set DEPLOYMENT_ID to the GitHub Deployment to report}"
: "${STATUS:?Set STATUS to the job status}"
[[ $DEPLOYMENT_ID =~ ^[0-9]+$ ]] || { echo "DEPLOYMENT_ID must be a number" >&2; exit 1; }

API_URL=${API_URL:-https://api.linchpin.com/api/v1}
API_URL=${API_URL%/}
DRY_RUN=${DRY_RUN:-false}
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/null}
RUN_ID=${RUN_ID:-${GITHUB_RUN_ID:-0}}
LOG_URL=${LOG_URL:-https://github.com/$GH_REPO/actions/runs/$RUN_ID}

fail() {
	echo "::warning title=Deployment log::Not reported to the deployment log: $*"
	exit 1
}

if [ "$DRY_RUN" != "true" ] && { [ -z "${CLIENT_ID:-}" ] || [ -z "${CLIENT_SECRET:-}" ]; }; then
	echo "::notice title=Deployment log::Not reported: DEPLOYMENTS_API_CLIENT_ID and DEPLOYMENTS_API_CLIENT_SECRET are not set."
	exit 0
fi

# GitHub's deployment states: a cancelled job is an error, not a failure of the code.
case "$STATUS" in
success | failure) ;;
*) STATUS=error ;;
esac

deployment=$(gh api "repos/$GH_REPO/deployments/$DEPLOYMENT_ID") ||
	fail "could not read deployment $DEPLOYMENT_ID."
sha=$(jq -r '.sha' <<<"$deployment")
environment=$(jq -r '.environment' <<<"$deployment")
started_at=$(jq -r '.created_at' <<<"$deployment")
# An older deployment's payload is an empty object, or a string.
ref=$(jq -r '.payload | objects | .branch // ""' <<<"$deployment")
tag=$(jq -r '.payload | objects | .release_tag // ""' <<<"$deployment")
correlation_id=$(jq -r '.payload | objects | .correlation_id // ""' <<<"$deployment")

# The commit the environment had before this deploy.
previous=""
encoded=$(jq -rn --arg value "$environment" '$value | @uri')
while read -r id candidate; do
	[ -n "$id" ] || continue
	# The job's `environment:` makes GitHub keep a second deployment of this same
	# run; its statuses link to the run, so it is never "before".
	state=$(gh api "repos/$GH_REPO/deployments/$id/statuses?per_page=100" --jq "
		if any(.[]; (.log_url // \"\") | test(\"/actions/runs/$RUN_ID(/|\$)\")) then \"this run\"
		elif any(.[]; .state == \"success\") then \"succeeded\"
		else \"no\" end" 2>/dev/null || echo no)
	if [ "$state" = "succeeded" ]; then
		previous=$candidate
		break
	fi
done < <(gh api "repos/$GH_REPO/deployments?environment=$encoded&per_page=30" \
	--jq ".[] | select(.id < $DEPLOYMENT_ID) | \"\(.id) \(.sha)\"" 2>/dev/null || true)

# What changed since: one line per commit, oldest first, 250 at most.
compare=""
commit_count=0
commits='[]'
if [ -n "$previous" ]; then
	if comparison=$(gh api "repos/$GH_REPO/compare/$previous...$sha" --jq '{
		status,
		total_commits,
		commits: [.commits[] | {
			sha,
			message: (.commit.message | split("\n")[0] | .[0:1000]),
			author: (.author.login // .commit.author.name // ""),
			merge: ((.parents | length) > 1),
			breaking: (.commit.message | test("BREAKING[ -]CHANGE:"))
		}]
	}' 2>/dev/null); then
		compare=$(jq -r '.status' <<<"$comparison")
		commit_count=$(jq -r '.total_commits' <<<"$comparison")
		commits=$(jq -c '.commits' <<<"$comparison")
	else
		echo "::warning title=Deployment log::Could not compare ${previous:0:7} with ${sha:0:7}, so the entry lists no changes."
	fi
fi

# A release's own notes, unless this deploy went back to it.
release_notes=""
if [ -n "$tag" ] && [ "$compare" != "behind" ]; then
	release_notes=$(gh api "repos/$GH_REPO/releases/tags/$tag" --jq '(.body // "")[0:100000]' 2>/dev/null || true)
fi

report=$(jq -n \
	--argjson deployment_id "$DEPLOYMENT_ID" \
	--argjson workflow_run_id "$RUN_ID" \
	--arg repository "$GH_REPO" \
	--arg environment "$environment" \
	--arg environment_url "${ENVIRONMENT_URL:-}" \
	--arg ref "$ref" \
	--arg sha "$sha" \
	--arg previous_sha "$previous" \
	--arg tag_name "$tag" \
	--arg status "$STATUS" \
	--arg creator_login "${ACTOR:-}" \
	--arg log_url "$LOG_URL" \
	--arg correlation_id "$correlation_id" \
	--arg started_at "$started_at" \
	--arg compare "$compare" \
	--argjson commit_count "$commit_count" \
	--argjson commits "$commits" \
	--arg release_notes "$release_notes" \
	'$ARGS.named')

if [ "$DRY_RUN" = "true" ]; then
	echo "Dry run, would report to $API_URL/deployments:"
	jq '.commits |= (length | tostring) + " commits" | .release_notes |= .[0:200]' <<<"$report"
	exit 0
fi

token_request=$(jq -n --arg id "$CLIENT_ID" --arg secret "$CLIENT_SECRET" \
	'{grant_type: "client_credentials", client_id: $id, client_secret: $secret}')
token_response=$(curl --fail-with-body --silent --show-error --max-time 20 \
	-X POST "$API_URL/auth/token" -H 'Content-Type: application/json' --data "$token_request") ||
	fail "api.linchpin.com refused the client: $token_response"
token=$(jq -r '.access_token // empty' <<<"$token_response")
[ -n "$token" ] || fail "api.linchpin.com issued no token."
echo "::add-mask::$token"

response=$(curl --fail-with-body --silent --show-error --max-time 30 \
	-X POST "$API_URL/deployments" \
	-H "Authorization: Bearer $token" \
	-H 'Content-Type: application/json' \
	--data-binary @- <<<"$report") ||
	fail "api.linchpin.com answered: $response"

site=$(jq -r '.data.hostname // "no site yet"' <<<"$response")
changes=$(jq -r '.data.changes | length' <<<"$response")
echo "::notice title=Deployment log::Logged ${sha:0:7} to $environment for $site, with $changes change(s)."
{
	echo "### Deployment log: $environment"
	echo
	jq -r '.data.notes' <<<"$response"
} >>"$SUMMARY"
