# run clippy and fmt checks
sol_checks() {
    ./cargo nightly clippy --all-targets -- -D warnings && \
    ./cargo nightly fmt --all -- --check
}

# run checks then commit with message
sol_commit() {
    if [ -z "$1" ]; then echo "Usage: sol_commit <MESSAGE>"; return -1; fi

    sol_checks && git commit -am "$1";
}

# rebase on master, run checks, then merge the input PR
sol_merge() {
    if [ -z "$1" ]; then echo "Usage: sol_merge <GitHub PR #>"; return -1; fi

    SOL_MERGE_OG_BRANCH=$(git_current_branch)
    git_stash_if_diff
    local stashed=$?

    gh pr checkout "$1" || return 1
    SOL_MERGE_MG_BRANCH=$(git_current_branch)

    if [ "$SOL_MERGE_OG_BRANCH" = "$SOL_MERGE_MG_BRANCH" ]; then
        echo "You are already on the branch for this PR. Please check out another so that the '-d' flag works correctly.";
        return 1;
    fi

    SOL_MERGE_MG_BRANCH_REBASE="${SOL_MERGE_MG_BRANCH}_rebase"
    git checkout -b "$SOL_MERGE_MG_BRANCH_REBASE" && \
    git fetch --all && \
    git rebase upstream/master --no-gpg-sign && \
    sol_checks && \
    git checkout "$SOL_MERGE_OG_BRANCH" && \
    gh pr checks "$1" && \
    gh pr merge -sd "$1" --body ""

    git branch -D "$SOL_MERGE_MG_BRANCH_REBASE"
    git checkout "$SOL_MERGE_OG_BRANCH" # fall-back in case of failure - switch back to original branch

    if [ $stashed -eq 1 ]; then git stash pop; fi
}

sol_feature_status() {
    if [ -z "$1" ]; then echo "Usage: sol_feature_status <Feature ID>"; return -1; fi

    # print header
    echo "         " "Feature                                      | Status                  | Activation Slot | Description"
    echo "devnet:  " $(solana -ud feature status $1 | head -n 2 | tail -n 1)
    echo "testnet: " $(solana -ut feature status $1 | head -n 2 | tail -n 1)
    echo "mainnet: " $(solana -um feature status $1 | head -n 2 | tail -n 1)
}