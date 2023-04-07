alias git-move-diff='git rev-parse --abbrev-ref HEAD | git show --color-moved-ws=ignore-all-space -w --patch-with-stat  --color-moved'

# Get the current commit hash
git_current_commit() {
    git rev-parse HEAD
}

# Get the current branch name
git_current_branch() {
    git rev-parse --abbrev-ref HEAD
}

# Get the child of a commit on the current branch
git_commit_child() {
    if [ -z "$1" ]; then echo "Usage: git_commit_child <COMMIT>"; return -1; fi

    git rev-list HEAD~$(expr $(git rev-list --ancestry-path $1.. --count) - 1) --max-count=1
}

# Determine the first common commit between the current branch and the input branch
git_branch_point() {
    if [ -z "$1" ]; then echo "Usage: git_branch_point <MAIN_BRANCH>"; return -1; fi

    GIT_BRANCH_POINT_OG_BRANCH=$1
    GIT_BRANCH_POINT_CURRENT_BRANCH=$(git_current_branch)
    diff -u <(git rev-list --first-parent ${GIT_BRANCH_POINT_CURRENT_BRANCH}) \
             <(git rev-list --first-parent ${GIT_BRANCH_POINT_OG_BRANCH}) \
             | sed -ne 's/^ //p' | head -1
}

# Squash all commits on the current branch (from branching point off of the input branch) into a single commit
# with the provided message.
git_branch_squash() {
    if [ -z "$1" ] || [ -z "$3" ]; then
        echo "Usage: git_branch_squash <MAIN_BRANCH> <SQUASH_MESSAGE>";
        return -1;
    fi

    GIT_BRANCH_SQUASH_OG_BRANCH=$(git_current_branch)
    GIT_BRANCH_SQUASH_BP=$(git_branch_point $1)
    GIT_BRANCH_SQUASH_DEST="$GIT_BRANCH_SQUASH_OG_BRANCH-squishy-squashy"

    git checkout -b $GIT_BRANCH_SQUASH_DEST && \
    git reset --soft $GIT_BRANCH_SQUASH_BP && \
    git commit -m "$3" && \
    COMMIT=$(git_current_commit) && \
    git checkout $GIT_BRANCH_SQUASH_OG_BRANCH && \
    git branch -D $GIT_BRANCH_SQUASH_DEST && \
    echo "Squashed commit: $COMMIT"
}

# Solana repository - run clippy and fmt checks
sol_checks() {
    ./cargo nightly clippy --all-targets -- -D warnings && \
    ./cargo nightly fmt --all -- --check
}

# Solana repository - run checks then commit with message
sol_commit() {
    if [ -z "$1" ]; then echo "Usage: sol_commit <MESSAGE>"; return -1; fi

    sol_checks && git commit -am "$1";
}

# Solana repository - rebase on master, run checks, then merge the input PR
sol_merge() {
    if [ -z "$1" ]; then echo "Usage: sol_merge <GitHub PR #>"; return -1; fi

    SOL_MERGE_OG_BRANCH=$(git_current_branch)
    if [ "$SOL_MERGE_OG_BRANCH" = "$SOL_MERGE_MG_BRANCH" ]; then
        echo "You are already on the branch for this PR. Please check out another so that the '-d' flag works correctly.";
        return 1;
    fi

    gh pr checkout "$1"
    SOL_MERGE_MG_BRANCH=$(git_current_branch)
    SOL_MERGE_MG_BRANCH_REBASE="${SOL_MERGE_MG_BRANCH}_rebase"

    git checkout -b "$SOL_MERGE_MG_BRANCH_REBASE"

    git fetch --all && \
    git rebase upstream/master --no-gpg-sign && \
    sol_checks && \
    git checkout "$SOL_MERGE_OG_BRANCH" && \
    gh pr checks "$1" && \
    gh pr merge -sd "$1" --body ""

    git branch -D "$SOL_MERGE_MG_BRANCH_REBASE"
    git checkout "$SOL_MERGE_OG_BRANCH" # fall-back in case of failure - switch back to original branch
}
