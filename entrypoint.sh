#!/bin/bash
echo "PHP:"
php --version
echo "PHPCS:"
phpcs --version
echo "Reviewdog:"
reviewdog --version
echo "Composer:"
composer --version
echo "NodeJS:"
node -v

INPUT_LINTERS="${INPUT_LINTERS:-php}"
INPUT_LINTERS_PARAM="${INPUT_LINTERS}"
IFS=',' read -r -a INPUT_LINTERS <<< "${INPUT_LINTERS}"

cd "${GITHUB_WORKSPACE}" || exit 1

# unshallow clone
git remote set-branches origin '*'
git fetch --depth 1 --quiet

git diff "origin/${GITHUB_BASE_REF}" "origin/${GITHUB_HEAD_REF}" > /worker/curr-diff.diff

export REVIEWDOG_GITHUB_API_TOKEN="$INPUT_GITHUB_TOKEN"
export FIXABLE_ERRORS
FIXABLE_ERRORS=$(mktemp)
echo -n "0" > "${FIXABLE_ERRORS}"

mkdir -p /worker/executions
mkdir -p /worker/fixables

for INPUT_LINTER in "${INPUT_LINTERS[@]}"; do
    /worker/run-lint.sh "${INPUT_LINTER}"
    LINT_EXIT_CODE=$?
    if [ "${LINT_EXIT_CODE}" -ne "0" ]; then
        exit "${LINT_EXIT_CODE}"
    fi
done

FIXABLE_ERRORS=$(cat "${FIXABLE_ERRORS}")

if [ "${FIXABLE_ERRORS}" -gt "0" ]; then
    echo "fixables=${FIXABLE_ERRORS}"
    COMMENT_ID=$(curl -s --request POST \
        --url "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${INPUT_PR_NUMBER}/comments" \
        --header "Authorization: Bearer ${INPUT_GITHUB_TOKEN}" \
        --header "Content-Type: application/json" \
        --data '{"body":"Please run fixers on your code, as there'\''s still code that can be autofixed in this PR."}' | jq -r '.id')

    echo "comment_created=${COMMENT_ID}"
    
    REACTION_ID=$(curl -s --request POST \
        --url "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/comments/${COMMENT_ID}/reactions" \
        --header "Accept: application/vnd.github.squirrel-girl-preview+json" \
        --header "Authorization: Bearer ${INPUT_GITHUB_TOKEN}" \
        --header "Content-Type: application/json" \
        --data '{"content":"rocket"}' | jq -r '.id')

    echo "reaction_created=${REACTION_ID}"

    exit 1
else
    reviewdog \
        -runners="${INPUT_LINTERS_PARAM}" \
        -conf="/worker/.reviewdog.yml" \
        -reporter="${INPUT_REPORTER:-github-pr-review}" \
        -filter-mode="${INPUT_FILTER_MODE:-added}" \
        -fail-on-error="${INPUT_FAIL_ON_ERROR:-true}" \
        -level="${INPUT_LEVEL:-warning}" || REVIEWDOG_EXIT_CODE=$?

    exit "${REVIEWDOG_EXIT_CODE:-0}"
fi
